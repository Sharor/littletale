# Getting started on development

## Dependencies

```sh
sudo apt install -y imagemagick libsqlite3-dev sqlite3 libvips-dev
curl -o- -L https://yarnpkg.com/install.sh | bash
bundle install
yarn install
bin/setup
```

## Running locally

Run the web server, asset watchers, and a Solid Queue worker from WSL:

```sh
bin/dev
```

The application uses `storage/development.sqlite3`. Durable development jobs use
`storage/development_queue.sqlite3`. Live character and book updates use
`storage/development_cable.sqlite3` to deliver worker broadcasts to the web server.
Run `bin/jobs` separately if you do not use
`bin/dev`.

## Running tests from WSL

Tests use the isolated `storage/test.sqlite3` file and do not need Docker:

```sh
bin/rails db:prepare RAILS_ENV=test
bin/rails test
```

## Troubleshooting

Prepare missing or stale databases with `bin/rails db:prepare`. Each database has
an explicit SQLite URL so an inherited `DATABASE_URL` cannot switch adapters; keep
database URL variables unset because they are no longer part of this deployment.

The previous PostgreSQL services and named volumes remain intact. They are excluded
from normal startup and can be inspected explicitly with:

```sh
docker compose --profile legacy-postgres up -d db worker_db
```

Development data was not imported because a reliable import would require more
than the approved single migration and changes to historical migrations. The old
PostgreSQL volumes were not changed.

## Env

```sh
OPENAI_ACCESS_TOKEN='sk....'
```

## Kamal deployment

This repository currently runs Rails 8.0.2.1. Its deployment and database layout
have been compared with the Rails 8.1.3.1 application generator: Kamal 2 and
Thruster build the container, while production uses separate SQLite databases for
the application, Solid Cache, Solid Queue, and Solid Cable. All four files live in
the persistent `little_stories_storage` volume. Development deliberately uses a
separate Solid Queue database and worker for closer production parity. Existing
MinIO upload storage remains in use.

Rails 8.1 changed the generated SQLite connection setting from `pool` to
`max_connections`. This app keeps `pool` until Rails itself is upgraded because
Rails 8.0 does not understand the newer option. During the Rails upgrade, run
`bin/rails app:update` and review `config/database.yml` against the generated
8.1 configuration. See the [Rails releases](https://rubyonrails.org/releases) and
[Rails 8.1 SQLite template](https://github.com/rails/rails/blob/v8.1.3.1/railties/lib/rails/generators/rails/app/templates/config/databases/sqlite3.yml.tt).

Before the first deployment:

1. Replace the server address, proxy host, image name, and registry settings in
   `config/deploy.yml`. Keep one application host while SQLite is in use.
2. Copy `.kamal/secrets.example` to `.kamal/secrets` and fill it from the password
   manager. Never commit that file. Ensure `DATABASE_URL` is absent from the host
   and Kamal environment.
3. Point DNS at the server and make sure Docker is installed there.
4. Run `bin/kamal setup`. Later releases use `bin/kamal deploy`; inspect them with
   `bin/kamal details` and `bin/kamal logs`.

The container entrypoint runs `db:prepare` before Thruster starts Rails. The web
container sets `SOLID_QUEUE_IN_PUMA=true`, so do not add a separate job role unless
you also remove that setting. A second supervisor would process the same queue.

SQLite's `.backup` command produces a consistent online snapshot, including data
held in WAL. Back up every durable database, then copy the snapshots off the host:

```sh
bin/kamal app exec --reuse 'mkdir -p /rails/storage/backups'
bin/kamal app exec --reuse "sqlite3 /rails/storage/production.sqlite3 '.backup /rails/storage/backups/production.sqlite3'"
bin/kamal app exec --reuse "sqlite3 /rails/storage/production_cache.sqlite3 '.backup /rails/storage/backups/production_cache.sqlite3'"
bin/kamal app exec --reuse "sqlite3 /rails/storage/production_queue.sqlite3 '.backup /rails/storage/backups/production_queue.sqlite3'"
bin/kamal app exec --reuse "sqlite3 /rails/storage/production_cable.sqlite3 '.backup /rails/storage/backups/production_cable.sqlite3'"
```

Cache and Cable data can be recreated, but include them for a complete snapshot.
Keep timestamped copies outside `little_stories_storage`. Rehearse a restore with a
disposable file before relying on a backup:

```sh
sqlite3 storage/development.sqlite3 ".backup '/tmp/little_stories_restore.sqlite3'"
sqlite3 /tmp/little_stories_restore.sqlite3 'PRAGMA integrity_check;'
```

For a production restore, stop the app, preserve the current volume, replace each
database from its verified snapshot, confirm `PRAGMA integrity_check` returns `ok`,
and start the app. Do not copy only a live `.sqlite3` file while writes are active.

## Character image screening

New and edited character images are screened before image generation. A review
holds only that request; other characters and unrelated books can still generate.
Owners see rejection reasons, but pending-review evidence is visible only to admins.
Open `/console` → **Character image reviews** to review requests and inspect
rejections (including image-provider refusals).

Identical photo bytes and effective prompts share screening within the same user,
including uploads for different characters. Renaming a file does not cause another
check. Changed prompts, models, or screening policy versions require a fresh check.
Previously completed inputs for the same character reuse their stored illustration.

Screening decisions are retained separately from generation allowances:

```ruby
user.character_image_decisions.group(:outcome).count
user.character_image_decisions.where(source: "admin").order(:created_at)
user.character_image_requests.includes(:assessment, :generation_attempt)
```

A shared assessment records one decision, not another decision for every cache hit.
Its requests identify all affected characters. Generation reservations continue
using the existing `setup_illustration` action logs. Deleting a character retains
its request, decision history, and generation accounting.

### Rollout and recovery

Stop old workers before deploying these changes. From WSL run:

```sh
bin/rails db:migrate
bin/rails db:prepare RAILS_ENV=test
bin/rails restart
```

Restart any standalone job workers as well. Existing completed characters remain
usable; old queued character jobs now enter screening. Keep the existing image
provider credentials configured as `OPENAI_ACCESS_TOKEN`.

Production Solid Queue runs `RecoverCharacterImagesJob` every five minutes.
Development uses its existing Active Job adapter; recovery can be invoked manually:

```sh
bin/rails runner 'RecoverCharacterImagesJob.perform_now'
```

Recovery resumes abandoned screening and unclaimed generation reservations. A paid
call interrupted for more than an hour becomes `outcome_unknown` and is not sent
again. If image bytes were already persisted, only local publication is retried.
Admins can inspect failures in the request's assessment detail. Do not manually
reset an unknown paid attempt to reserved: the provider may already have charged.

Moderation is an application pre-check, not a guarantee of provider acceptance.
Flagged or uncertain assessments go to review; invalid uploads and explicit
provider moderation refusals reject with a public explanation. Wardrobe changes
for book environments are a separate follow-up feature.

### Book page illustration retries

New explicit image-provider moderation rejections automatically queue a revised
prompt and another image request for that page. The revision uses the book plot,
current story pages, character identities and ages, and prior prompt, asking for
an appropriate depiction and activity-appropriate clothing. Provider safety
checks still apply.

Automatic generation stops after three reservations per illustration: the original
plus two retries. Admins can explicitly request further retries without a count limit;
these do not restart automatic retries beyond that cap. All attempts remain recorded. Duplicate
clicks and duplicate job deliveries cannot start another concurrent request.
Prompt-revision failures also consume their reservation conservatively. Timeouts
and other uncertain failures do not trigger automatic paid retries.

Admins can use **Regenerate illustration** beside a missing image or in
`/admin/failed_books`. Existing pages and successful images are retained. When all
current pages have images, the book becomes completed again. Per-page prompts,
outcomes, requesting admin, and owner are recorded under
`illustration.generation_metadata["page_generation"]`; the failed-books screen
shows the attempt history. Legacy illustrations without attempt records are
counted as having one original attempt; historical hidden network retries cannot
be reconstructed. Existing failed books are not retried merely by deploying this
change; an admin can initiate a retry.

No database migration is required. Restart standalone workers during deployment
so old workers cannot use the former internal image retry loop. A worker interrupted
after claiming an attempt leaves it running; it is deliberately not automatically
replayed because the provider outcome may be unknown.

### Book-specific wardrobes

New book generations save a complete story and wardrobe plan before page images
start. Story instructions prefer a single outfit per character, while preserving
explicitly requested activities and required outfit transitions. Each distinct
character/outfit gets one dressed reference image; pages and their retries reuse
that image and the same clothing description. Original character images and
existing books are unchanged. Whole-book regeneration creates a new plan.

Character details and approved source pixels are captured before planning calls,
so later character edits do not change a prepared book. Outfit assignments are
validated for every character and page before reference-image requests. Page jobs
wait until all references are ready and keep stable story positions on duplicate
delivery. Page retry rules remain three automatic attempts and unlimited explicit
admin retries, preserving the saved wardrobe.

This adds one wardrobe-planning text request and one image request per distinct
character/outfit. References are saved rather than regenerated per page. A rejected
reference stops page generation with a visible notice; uncertain image requests
are not automatically resent. No additional requests are made for old books merely
by deploying this feature.

Run the migration in development and test and restart Rails/workers. Production
runs `RecoverBookWardrobesJob` every five minutes. In development it can be invoked
with `bin/rails runner 'RecoverBookWardrobesJob.perform_now'`. Recovery queues
unclaimed references/pages and reuses saved reference results; interrupted paid
requests without saved bytes become `outcome_unknown` for investigation. Inspect
`book.current_wardrobe_plan`, its `book_outfits`, and their `generation_metadata`
for details. Visual outfit fidelity still depends on the image provider; local
tests verify reference reuse and prompt consistency without paid image calls.
