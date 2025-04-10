# Ruby DataDog Tracer Example

This is a simple Ruby application that demonstrates DataDog tracing with a hello world endpoint that makes a call to a third-party API.

## Prerequisites

- Ruby 3.2 or higher
- Bundler

## Setup

1. Install dependencies:
```bash
bundle install
```

2. Configure DataDog (optional):
   - Set environment variables for DataDog configuration:
     - `DD_SERVICE`: Your service name (default: "ruby-app")
     - `DD_ENV`: Your environment (default: "development")
     - `DD_TRACE_AGENT_URL`: DataDog agent URL (default: "http://localhost:8126")

## Running the Application

1. Start the application:
```bash
ruby app.rb
```

2. Access the endpoints:
```
http://localhost:4567/hello
http://localhost:4567/health
```

The `/hello` endpoint will return a JSON response with a hello world message and data from a third-party API (JSONPlaceholder).

## Features

- DataDog tracing integration
- Hello World endpoint
- Third-party API integration (JSONPlaceholder)
- Error handling
- JSON response format
- Health check endpoint 