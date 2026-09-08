# Getting started on development

## Dependencies
sudo apt install -y libvips-dev libpq-dev
curl -o- -L https://yarnpkg.com/install.sh | bash
sudo apt install -y imagemagick

## Running in the Dockerized setup
docker-compose up -d --build
(might need to run docker-compose up bin/dev for javascript errors, should be fixed better eventually.)

## Running tests from WSL

Rails commands run in WSL; PostgreSQL runs in Docker. Start the isolated test
databases, prepare them, then run the test suite:

```sh
docker compose up -d test_db test_worker_db
bin/rails db:prepare RAILS_ENV=test
bin/rails test
```

## Troubleshooting
Missing database: 
docker-compose run web rake db:create RAILS_ENV=development
docker-compose run web rake db:migrate RAILS_ENV=development

## Env
OPENAI_ACCESS_TOKEN='sk....'

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
