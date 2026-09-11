# Local development and test workflow

Run Rails and all `bin/rails` commands from the WSL terminal, not from a Docker
application container. The application uses SQLite files under `storage/`; no
database service is required for development or tests.

## Databases

Never recreate, reset, drop, or replace any database without first asking the
user and receiving explicit permission. This applies to every environment,
including development databases, but excluding test databases, and to commands such as `db:reset`, `db:drop`, and
schema loads that overwrite existing data. A request to fix a bug, run tests,
or apply a migration does not authorize database recreation. If a required
workflow would recreate a database, stop and ask for permission first.

| Environment | Role | SQLite file |
| --- | --- | --- |
| development | primary | `storage/development.sqlite3` |
| development | queue | `storage/development_queue.sqlite3` |
| test | primary | `storage/test.sqlite3` |
| production | primary/cache/queue/cable | separate `storage/production*.sqlite3` files |

Prepare and run tests directly from WSL:

```sh
bin/rails db:prepare RAILS_ENV=test
bin/rails test
```

Use `bin/rails test path/to/test.rb` for a focused test. Do not point
`RAILS_ENV=test` at development databases. Do not delete SQLite files or the
legacy PostgreSQL Docker volumes unless the user explicitly asks to recreate data.
The legacy PostgreSQL services remain under the `legacy-postgres` Compose profile
only to preserve old development data.

## Required engineering workflow

- Use test-driven development for every bug fix and feature: write or update a
  failing test first, implement the smallest change that makes it pass, then
  run the relevant focused tests.
- Before handing off any code change, run the full Rails test suite with
  `bin/rails test`. All tests must pass.
- Do not guess whether a failing test is acceptable, unrelated, or should be
  changed. If its cause or intended behavior is uncertain, stop and ask the
  user for direction.
- When adding a migration, apply it immediately to both databases from WSL:

  ```sh
  bin/rails db:migrate
  bin/rails db:prepare RAILS_ENV=test
  ```

  Restart any already-running Rails process after a schema change so it reloads
  model column information.

# Codex Agent Rules

## Feature Guardrails
- Whenever I ask for a new feature, complex refactoring, or a fresh task, DO NOT write any application code immediately.
- **Mandatory Step:** You must pause and ask me explicitly: *"Would you like to run the `create-plan` skill for this feature?"*
- If I reply "Yes", you must invoke the local `$create-plan` skill to generate the scope boundaries, milestones, and testing checklist before we begin.
