from django.apps import AppConfig


class HelloConfig(AppConfig):
    default_auto_field = 'django.db.models.BigAutoField'
    name = 'hello'

    def ready(self):
        """Initialize OpenTelemetry when Django app starts"""
        from hello.tracing import initialize_otel
        initialize_otel()
