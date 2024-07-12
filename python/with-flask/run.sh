#!/bin/bash

# Check if .env file exists
if [ ! -f .env ]; then
  echo ".env file not found!"
  exit 1
fi

# Read .env file and export variables
export $(grep -v '^#' .env | xargs)

echo "Environment variables exported successfully."

# Run the Flask app

opentelemetry-instrument flask run 