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

## Testing with tox

A `tox.ini` configuration at the repository root defines a matrix for Python 3.8
through 3.11 and Django 3.2, 4.2, 5.0 and 5.1. Run all environments with:

```bash
tox
```

Each environment installs `Django==${DJANGO}` and only the OpenTelemetry
packages listed in `mysite/requirements.txt`, then bootstraps instrumentation
and executes `python manage.py check`. The detailed output for every run is
available under `.tox/<env>/log/`.

> **Note:** This matrix is for testing OpenTelemetry compatibility only. Django/Python compatibility is determined by the Django project. See below for the official compatibility table.

### Official Django/Python Compatibility

| Django Version | Python 3.8 | Python 3.9 | Python 3.10 | Python 3.11 | Python 3.12 |
|---------------|:----------:|:----------:|:-----------:|:-----------:|:-----------:|
| 3.2 (LTS)     |     ✅     |     ✅     |     ✅      |     ❌      |     ❌      |
| 4.2 (LTS)     |     ✅     |     ✅     |     ✅      |     ✅      |     ❌      |
| 5.0           |     ✅     |     ✅     |     ✅      |     ✅      |     ✅      |
| 5.1           |     ✅     |     ✅     |     ✅      |     ✅      |     ✅      |

_Source: [Django/Python compatibility](https://docs.djangoproject.com/en/stable/faq/install/#what-python-version-can-i-use-with-django)_

### Collecting OTEL package lists

After the tox run completes, you can aggregate the installed package list for
each environment using the helper script:

```bash
python list_otel_packages.py
```

The script prints a table showing the OpenTelemetry packages present in each
virtual environment.

## OpenTelemetry Package Matrix

This matrix shows the OpenTelemetry packages installed in each test environment:

```
| Environment | OTEL Packages |
|------------|--------------|
| py38-django32 | opentelemetry-api, opentelemetry-sdk |
| py38-django42 | opentelemetry-api, opentelemetry-sdk |
| py38-django50 | opentelemetry-api, opentelemetry-sdk |
| py38-django51 | opentelemetry-api, opentelemetry-sdk |
| py39-django32 | opentelemetry-api, opentelemetry-sdk |
| py39-django42 | opentelemetry-api, opentelemetry-sdk |
| py39-django50 | opentelemetry-api, opentelemetry-sdk |
| py39-django51 | opentelemetry-api, opentelemetry-sdk |
| py310-django32 | opentelemetry-api, opentelemetry-sdk |
| py310-django42 | opentelemetry-api, opentelemetry-sdk |
| py310-django50 | opentelemetry-api, opentelemetry-sdk |
| py310-django51 | opentelemetry-api, opentelemetry-sdk |
| py311-django32 | opentelemetry-api, opentelemetry-sdk |
| py311-django42 | opentelemetry-api, opentelemetry-sdk |
| py311-django50 | opentelemetry-api, opentelemetry-sdk |
| py311-django51 | opentelemetry-api, opentelemetry-sdk |
```

*Last updated: 2024-01-01 00:00:00 UTC*

> **Note**: This matrix is automatically updated by GitHub Actions when tests are run. The actual packages will be populated after the first successful CI run.
