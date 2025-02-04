# Django App with OpenTelemetry Instrumentation

A simple Django polling application instrumented with OpenTelemetry, supporting both uWSGI and Gunicorn deployments.

## Prerequisites

- Python 3.x
- Django 5.1.2
- uWSGI or Gunicorn
- virtualenv

## Setup

1. Clone and navigate to the project:

```bash
git clone https://github.com/last9/opentelemetry-examples.git
cd opentelemetry-examples/python/django/mysite
```

2. Install OpenTelemetry dependencies:

```bash
pip install aws-opentelemetry-distro opentelemetry-exporter-otlp
opentelemetry-bootstrap -a install
```

3. Configure environment variables:
```bash
export OTEL_EXPORTER_OTLP_ENDPOINT="https://otlp.last9.io"  # or https://otlp-aps1.last9.io
export OTEL_EXPORTER_OTLP_HEADERS="<LAST9_OTLP_BASIC_AUTH_HEADER>"  # Use %20 for spaces
export OTEL_SERVICE_NAME="polls-service" # This is the name of your service
export OTEL_PYTHON_DISTRO="aws_distro"
export OTEL_PYTHON_CONFIGURATOR="aws_configurator"
export OTEL_EXPORTER_PROTOCOL="http/protobuf"
export OTEL_AWS_PYTHON_DEFER_TO_WORKERS_ENABLED=true
```

## Running the Application

### With uWSGI

1. Add the [last9_uwsgi.py](./mysite/last9_uwsgi.py) to your `uwsgi.ini`:

This file is responsible for initializing the OpenTelemetry instrumentation after the worker is spawned by uwsgi.

```ini
import = last9_uwsgi.py
env = DJANGO_SETTINGS_MODULE=mysite.settings # This is the name of your settings file
```

2. Start the server:
```bash
opentelemetry-instrument uwsgi --http 8000 --ini uwsgi.ini
```

### With Gunicorn

Set the environment variable for the settings file:
```bash
export DJANGO_SETTINGS_MODULE=mysite.settings
```

Use the [last9_gunicorn.py](./mysite/last9_gunicorn.py) as configuration file for gunicorn.
This file is responsible for initializing the OpenTelemetry instrumentation after the worker is spawned by gunicorn.

Start the server:
```bash
opentelemetry-instrument gunicorn mysite.wsgi:application -c last9_gunicorn.py
```

## Viewing Traces

Monitor your application traces at [Last9 Traces](https://app.last9.io/traces)

## Development

For local development, you can use Django's built-in server:
```bash
python manage.py runserver
```

> Note: Remember to run `pip freeze > requirements.txt` after installing dependencies.
