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

