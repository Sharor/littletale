Implemented the Kamal, SQLite, and Solid stack migration directly on master. Changes remain uncommitted.
Key results:
- SQLite now provides separate production primary, cache, queue, and cable databases in [config/database.yml (line 1)](/home/home/source/repos/little_stories/config/database.yml:1).
- Solid Queue runs through Puma in production and through bin/jobs during development.
- Kamal configuration, persistent storage, secrets template, and non-root production image are ready in [config/deploy.yml (line 1)](/home/home/source/repos/little_stories/config/deploy.yml:1) and [Dockerfile (line 1)](/home/home/source/repos/little_stories/Dockerfile:1).
- PostgreSQL-specific schema types and queries were converted. Legacy PostgreSQL volumes remain available through the legacy-postgres Compose profile.
- Development data was not imported because a reliable transfer exceeded the approved single-migration constraint.
- Compared against Rails 8.1.3.1, currently listed as the latest stable release. Rails remains at 8.0.2.1; the documented upgrade note covers the newer max_connections SQLite setting. Rails releases, Rails 8.1 SQLite template.
- Development, deployment, backup, and restore instructions are in [README.md (line 57)](/home/home/source/repos/little_stories/README.md:57) and [AGENTS.md (line 1)](/home/home/source/repos/little_stories/AGENTS.md:1).
- The implementation plan is marked complete in [2026-09-10-kamal-sqlite-solid-stack.md (line 1)](/home/home/source/repos/little_stories/docs/superpowers/plans/2026-09-10-kamal-sqlite-solid-stack.md:1).
Verification completed:
- bin/rails test: 206 runs, 813 assertions, 0 failures
- Production Docker image built successfully.
- /up returned HTTP 200.
- Solid Queue worker and recurring scheduler started and executed a recovery job.
- Solid Cache persisted across container replacement.
- Solid Cable delivered across separate processes.
- ImageMagick/RMagick loaded and processed an image.
- SQLite backup restored with PRAGMA integrity_check returning ok.
- bin/kamal config, Compose validation, Ruby/shell syntax checks, RuboCop, Bundler, and git diff --check passed.
A real deployment still needs the server address, domain, registry choice, credentials, and backup destination filled into the documented placeholders.