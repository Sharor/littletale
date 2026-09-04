#!/bin/bash
set -e

echo "Waiting for worker_db to be ready..."
until pg_isready -h worker_db -U worker; do
  sleep 1
done

echo "Starting SolidQueue..."
bundle exec rails solid_queue:start
