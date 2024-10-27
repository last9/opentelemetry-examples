# uwsgi Django App with OpenTelemetry Instrumentation

A simple Django polling application where users can vote on questions and view results with OpenTelemetry instrumentation.

## Prerequisites

- Python 3.x
- Django 5.1.2

## Installation

1. Clone the repository

```
git clone https://github.com/last9/opentelemetry-examples.git
```

2. Install dependencies

```
cd opentelemetry-examples/python/django/mysite
pip install -r requirements.txt
```

3. Run the application

```
python manage.py runserver
```

4. Instrument the application

``` 
pip install aws-opentelemetry-distro opentelemetry-exporter-otlp 
```

``` 
opentelemetry-bootstrap -a install 
```

> You can freeze the requirements by running `pip freeze > requirements.txt` after this step.

5. Set following environment variables

```bash
export OTEL_EXPORTER_OTLP_ENDPOINT=<LAST9_OTLP_ENDPOINT>
export  OTEL_EXPORTER_OTLP_HEADERS=<LAST9_OTLP_BASIC_AUTH_HEADERS> # Last9 OTLP Basic Auth Headers. Make sure you use %20 for spaces in the header. Read more here: https://last9.io/blog/whitespace-in-otlp-headers-and-opentelemetry-python-sdk/
export OTEL_SERVICE_NAME=polls-service # This is the service name that will be used for the traces
export OTEL_PYTHON_DISTRO="aws_distro" # This is the OpenTelemetry Python Distro that will be used for the instrumentation
export OTEL_PYTHON_CONFIGURATOR="aws_configurator" # This is the OpenTelemetry Python Configurator that will be used for the instrumentation
export OTEL_EXPORTER_PROTOCOL="http/protobuf" # This is the protocol that will be used for the instrumentation
export OTEL_AWS_PYTHON_DEFER_TO_WORKERS_ENABLED=true # This is to defer the instrumentation to the worker threads spawned by uwsgi instead of the master process


7. Update the uwsgi.ini file to include the following

```ini
import last9_apm.py
```

The `last9_apm.py` file is a custom module that is used to instrument the application for each worker spawned by uwsgi.

8. Run the application with uwsgi

``` opentelemetry-instrument uwsgi --http 8000 --ini uwsgi.ini```

9. View traces in Last9 here: https://app.last9.io/traces
