from opentelemetry import trace
from opentelemetry.trace import SpanKind
import os
import inspect

tracer = trace.get_tracer(__name__)

def traced_function(span_kind=SpanKind.INTERNAL):
    def decorator(func):
        def wrapper(*args, **kwargs):
            # Get the caller's file name (where the decorator is applied)
            frame = inspect.currentframe()
            outer_frames = inspect.getouterframes(frame)
            # The function being decorated is at index 1 in the call stack
            caller_file = outer_frames[1].filename
            file_name = os.path.basename(caller_file)
            span_name = f"{file_name}:{func.__name__}"
            with tracer.start_as_current_span(span_name, kind=span_kind):
                return func(*args, **kwargs)
        return wrapper
    return decorator 