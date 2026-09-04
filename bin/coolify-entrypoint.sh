#!/bin/bash
set -e

# 2. Load Queue Schema
# We use a Ruby runner but keep the quotes safe inside this file
bundle exec rails runner 'ActiveRecord::Base.establish_connection(:queue); eval(File.read(%Q(db/queue_schema.rb)))' 

RAILS_ENV=production bundle exec rake solid_queue:start