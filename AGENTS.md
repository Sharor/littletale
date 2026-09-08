# Local development and test workflow

Run Rails and all `bin/rails` commands from the WSL terminal, not from a Docker
application container. PostgreSQL runs in Docker and is exposed to WSL on
localhost.

## Databases

| Environment | Database | Docker service | WSL port |
| --- | --- | --- | --- |
| development primary | `little_stories_development` | `db` | 5434 |
| development queue | `worker_db` | `worker_db` | 5433 |
| test primary | `little_stories_test` | `test_db` | 5435 |
| test queue | `test_worker_db` | `test_worker_db` | 5436 |

Before running tests, start only the test databases from WSL:

```sh
docker compose up -d test_db test_worker_db
bin/rails db:prepare RAILS_ENV=test
bin/rails test
```

Use `bin/rails test path/to/test.rb` for a focused test. Do not point `RAILS_ENV=test`
at development databases, and do not remove Docker volumes unless the user explicitly
asks to recreate database data.

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