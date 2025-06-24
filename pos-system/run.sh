#!/bin/bash
set -e

# Usage: ./run.sh store1.env
# Pass the store environment file to load env vars

if [ $# -eq 0 ]; then
  echo "Usage: $0 <store.env>"
  exit 1
fi

ENV_FILE=$1

# Run docker container with environment variables from the specified env file
docker build -t pos-store-app .

docker run --rm -p 5000:5000 --env-file $ENV_FILE pos-store-app
