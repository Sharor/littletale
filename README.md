# Getting started on development

## Dependencies
sudo apt install -y libvips-dev libpq-dev
curl -o- -L https://yarnpkg.com/install.sh | bash
sudo apt install -y imagemagick

## Running in the Dockerized setup
docker-compose up -d --build
(might need to run docker-compose up bin/dev for javascript errors, should be fixed better eventually.)

## Troubleshooting
Missing database: 
docker-compose run web rake db:create RAILS_ENV=development
docker-compose run web rake db:migrate RAILS_ENV=development

## Env 
OPENAI_ACCESS_TOKEN='sk....'