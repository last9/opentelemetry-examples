# uwsgi Django App with OpenTelemetry Instrumentation

A simple Django polling application where users can vote on questions and view results with OpenTelemetry instrumentation. This example shows how to instrument Django apps running with uwsgi using OpenTelemetry.

## Prerequisites

- Python 3.x
- Django 5.1.2
- uwsgi
- virtualenv

## Installation

1. Clone the repository

```
git clone https://github.com/last9/opentelemetry-examples.git
cd opentelemetry-examples/python/django/mysite
```

2. Run the application

```
python manage.py runserver
```

3. Instrument the application with OpenTelemetry

```
pip install aws-opentelemetry-distro opentelemetry-exporter-otlp
```

Install all the relevant instrumentation packages for your application.

```
opentelemetry-bootstrap -a install
```

> You can freeze the requirements by running `pip freeze > requirements.txt` after this step.

4. Set following environment variables

```bash
export OTEL_EXPORTER_OTLP_ENDPOINT=<LAST9_OTLP_ENDPOINT> # https://otlp.last9.io OR https://otlp-aps1.last9.io
export  OTEL_EXPORTER_OTLP_HEADERS=<LAST9_OTLP_BASIC_AUTH_HEADERS> # Last9 OTLP Basic Auth Headers. Make sure you use %20 for spaces in the header. Read more here: https://last9.io/blog/whitespace-in-otlp-headers-and-opentelemetry-python-sdk/
export OTEL_SERVICE_NAME=polls-service # This is the service name that will be used for the traces
export OTEL_PYTHON_DISTRO="aws_distro" # This is the OpenTelemetry Python Distro that will be used for the instrumentation
export OTEL_PYTHON_CONFIGURATOR="aws_configurator" # This is the OpenTelemetry Python Configurator that will be used for the instrumentation
export OTEL_EXPORTER_PROTOCOL="http/protobuf" # This is the protocol that will be used for the instrumentation
export OTEL_AWS_PYTHON_DEFER_TO_WORKERS_ENABLED=true # This is to defer the instrumentation to the worker threads spawned by uwsgi instead of the master process
```

5. Update the uwsgi.ini file to include the following

```ini
import = last9_apm.py
```

The `last9_apm.py` file is a custom module that is used to instrument the application for each worker spawned by uwsgi. Make sure to update your existing `uwsgi.ini` file with this import statement.


6. Run the application with uwsgi and opentelemetry-instrument

`opentelementry-instrument` command performs automatic instrumentation of the Django application.

```
opentelemetry-instrument uwsgi --http 8000 --ini uwsgi.ini
```

7. View traces in Last9 here: https://app.last9.io/traces
