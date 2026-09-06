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
