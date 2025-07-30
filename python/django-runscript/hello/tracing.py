"""
OpenTelemetry tracing module with built-in bootstrap functionality
"""
from opentelemetry import trace
from opentelemetry.trace import SpanKind, Status, StatusCode
import os
import sys
import inspect
import logging
import functools
from typing import Optional

# Configure logging first
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class OTelBootstrap:
    """OpenTelemetry initialization with fallbacks and validation"""
    
    def __init__(self):
        self.is_initialized = False
        self.service_name = None
        self.endpoint = None
        
    def _get_service_name(self) -> str:
        """Get service name with intelligent fallbacks"""
        # Try environment variable first
        service_name = os.getenv('OTEL_SERVICE_NAME')
        if service_name:
            return service_name
            
        # Fallback to Django project name
        try:
            django_settings = os.getenv('DJANGO_SETTINGS_MODULE', '')
            if django_settings:
                project_name = django_settings.split('.')[0]
                return f"{project_name}-service"
        except Exception:
            pass
            
        # Final fallback
        return "django-application"
    
    def _get_endpoint(self) -> Optional[str]:
        """Get OTLP endpoint with validation"""
        endpoint = os.getenv('OTEL_EXPORTER_OTLP_ENDPOINT')
        if not endpoint:
            logger.warning("OTEL_EXPORTER_OTLP_ENDPOINT not set")
            return None
            
        # Validate endpoint format
        if not (endpoint.startswith('http://') or endpoint.startswith('https://')):
            logger.warning(f"Invalid endpoint format: {endpoint}")
            return None
            
        return endpoint
    
    def _test_connectivity(self, endpoint: str) -> bool:
        """Test if OTLP endpoint is reachable"""
        try:
            import requests
            from urllib.parse import urlparse
            
            parsed = urlparse(endpoint)
            # Try health check on common ports
            health_urls = [
                f"{parsed.scheme}://{parsed.hostname}/metrics",  # Common health port
                f"{parsed.scheme}://{parsed.hostname}/health",
                endpoint.replace('/v1/traces', '/health')
            ]
            
            for health_url in health_urls:
                try:
                    response = requests.get(health_url, timeout=2)
                    if response.status_code < 400:
                        logger.info(f"OTLP endpoint healthy at {health_url} (status: {response.status_code})")
                        return True
                    elif response.status_code < 500:
                        logger.warning(f"OTLP endpoint client error at {health_url} (status: {response.status_code})")
                        return True  # Still reachable, just client error
                    else:
                        logger.error(f"OTLP endpoint server error at {health_url} (status: {response.status_code})")
                        # Continue trying other URLs
                except requests.exceptions.Timeout:
                    logger.warning(f"OTLP endpoint timeout at {health_url}")
                except requests.exceptions.ConnectionError:
                    logger.warning(f"OTLP endpoint connection refused at {health_url}")
                except Exception as e:
                    logger.warning(f"OTLP endpoint check failed at {health_url}: {e}")
                    continue
                    
            logger.warning(f"OTLP endpoint {endpoint} may not be reachable")
            return False
            
        except ImportError:
            logger.info("Requests not available, skipping connectivity test")
            return True
        except Exception as e:
            logger.warning(f"Connectivity test failed: {e}")
            return False
    
    def _set_defaults(self):
        """Set sensible defaults for all OTEL environment variables"""
        defaults = {
            'OTEL_SERVICE_NAME': self._get_service_name(),
            'OTEL_TRACES_EXPORTER': 'otlp',
            'OTEL_METRICS_EXPORTER': 'otlp', 
            'OTEL_TRACES_SAMPLER': 'always_on',
            'OTEL_PYTHON_LOG_CORRELATION': 'true',
            'OTEL_PYTHON_LOGGING_AUTO_INSTRUMENTATION_ENABLED': 'true',
            'OTEL_LOG_LEVEL': os.getenv('OTEL_LOG_LEVEL', 'info'),
        }
        
        for key, value in defaults.items():
            if not os.getenv(key):
                os.environ[key] = value
                logger.debug(f"Set default {key}={value}")
    
    def _configure_console_fallback(self):
        """Configure console exporter as fallback when endpoint unreachable"""
        current_exporter = os.getenv('OTEL_TRACES_EXPORTER', '')
        if 'console' not in current_exporter:
            # Add console as fallback
            if current_exporter:
                os.environ['OTEL_TRACES_EXPORTER'] = f"{current_exporter},console"
            else:
                os.environ['OTEL_TRACES_EXPORTER'] = 'console'
            logger.info("Added console exporter as fallback")
    
    def initialize(self, force_console_fallback: bool = False) -> bool:
        """
        Initialize OpenTelemetry with robust error handling
        
        Args:
            force_console_fallback: If True, always add console exporter
            
        Returns:
            bool: True if initialization successful
        """
        try:
            # Set defaults first
            self._set_defaults()
            
            self.service_name = os.getenv('OTEL_SERVICE_NAME')
            self.endpoint = self._get_endpoint()
            
            logger.info(f"Initializing OTEL for service: {self.service_name}")
            
            # Test connectivity if endpoint provided
            endpoint_reachable = True
            if self.endpoint:
                endpoint_reachable = self._test_connectivity(self.endpoint)
                if not endpoint_reachable or force_console_fallback:
                    self._configure_console_fallback()
            else:
                logger.warning("No OTLP endpoint configured, using console exporter")
                os.environ['OTEL_TRACES_EXPORTER'] = 'console'
            
            # Initialize OpenTelemetry
            from opentelemetry.sdk.trace import TracerProvider
            from opentelemetry.sdk.trace.export import BatchSpanProcessor
            
            # Check if already initialized
            current_provider = trace.get_tracer_provider()
            if hasattr(current_provider, '_active_span_processor'):
                logger.info("OpenTelemetry already initialized")
                self.is_initialized = True
                return True
            
            # Test tracer creation
            tracer = trace.get_tracer("bootstrap-test")
            with tracer.start_as_current_span("initialization-test") as span:
                span.set_attribute("otel.bootstrap.success", True)
                span.set_attribute("service.name", self.service_name)
                span.set_attribute("endpoint.reachable", endpoint_reachable)
                span.set_attribute("exporter.type", os.getenv('OTEL_TRACES_EXPORTER', 'unknown'))
                
                # Log span creation success
                logger.info(f"Test span created successfully with trace_id: {format(span.get_span_context().trace_id, '032x')}")
            
            self.is_initialized = True
            logger.info("OpenTelemetry initialized successfully")
            return True
            
        except Exception as e:
            logger.error(f"Failed to initialize OpenTelemetry: {e}")
            logger.info("Continuing without tracing...")
            return False
    
    def get_status(self) -> dict:
        """Get current OTEL status for debugging"""
        return {
            'initialized': self.is_initialized,
            'service_name': self.service_name,
            'endpoint': self.endpoint,
            'exporter': os.getenv('OTEL_TRACES_EXPORTER'),
            'sampler': os.getenv('OTEL_TRACES_SAMPLER'),
            'log_level': os.getenv('OTEL_LOG_LEVEL')
        }

# Global bootstrap instance
_bootstrap = OTelBootstrap()

def initialize_otel(force_console_fallback: bool = False) -> bool:
    """
    Initialize OpenTelemetry with error handling
    This function can be called multiple times safely
    """
    return _bootstrap.initialize(force_console_fallback)

def get_otel_status() -> dict:
    """Get current OpenTelemetry status"""
    return _bootstrap.get_status()

def ensure_otel_initialized():
    """Decorator to ensure OTEL is initialized before function execution"""
    def decorator(func):
        def wrapper(*args, **kwargs):
            if not _bootstrap.is_initialized:
                initialize_otel()
            return func(*args, **kwargs)
        return wrapper
    return decorator

# Auto-initialize when module is imported
if not _bootstrap.is_initialized:
    initialize_otel()

class SafeTracer:
    """Tracer wrapper that handles failures gracefully"""
    
    def __init__(self):
        self._tracer = None
        self._initialize_tracer()
    
    def _initialize_tracer(self):
        """Initialize tracer with fallback handling"""
        try:
            # Ensure OTEL is initialized
            initialize_otel()
            self._tracer = trace.get_tracer(__name__)
        except Exception as e:
            logger.warning(f"Failed to initialize tracer: {e}")
            self._tracer = None
    
    def start_as_current_span(self, name, **kwargs):
        """Start span with graceful fallback"""
        if self._tracer:
            try:
                return self._tracer.start_as_current_span(name, **kwargs)
            except Exception as e:
                logger.warning(f"Failed to create span '{name}': {e}")
        
        # Return a no-op context manager
        return NoOpSpan()
    
    def is_available(self) -> bool:
        """Check if tracing is available"""
        return self._tracer is not None

# Global safe tracer instance
tracer = SafeTracer()

class NoOpSpan:
    """No-op span for when tracing fails"""
    
    def __enter__(self):
        return self
    
    def __exit__(self, exc_type, exc_val, exc_tb):
        pass
    
    def set_attribute(self, key, value):
        pass
    
    def set_status(self, status):
        pass
    
    def record_exception(self, exception):
        pass

def traced_function(span_kind=SpanKind.INTERNAL, include_args=False, include_result=False):
    """
    Enhanced tracing decorator with error handling
    
    Args:
        span_kind: OpenTelemetry span kind
        include_args: Whether to include function arguments as span attributes
        include_result: Whether to include return value as span attribute
    """
    def decorator(func):
        @functools.wraps(func)
        def wrapper(*args, **kwargs):
            # Get the caller's file name (where the decorator is applied)
            try:
                frame = inspect.currentframe()
                outer_frames = inspect.getouterframes(frame)
                caller_file = outer_frames[1].filename
                file_name = os.path.basename(caller_file)
                span_name = f"{file_name}:{func.__name__}"
            except Exception:
                # Fallback naming
                span_name = f"{func.__module__}:{func.__name__}"
            
            # Create span with error handling
            with tracer.start_as_current_span(span_name, kind=span_kind) as span:
                try:
                    # Add OpenTelemetry semantic convention attributes for code
                    span.set_attribute("code.function", func.__name__)
                    span.set_attribute("code.namespace", func.__module__)
                    span.set_attribute("code.filepath", file_name)
                    
                    # Add optional code attributes if available
                    if hasattr(func, '__qualname__'):
                        span.set_attribute("code.qualified_name", func.__qualname__)
                    
                    # Add line number if available from stack inspection
                    try:
                        frame = inspect.currentframe()
                        if frame and frame.f_back:
                            span.set_attribute("code.lineno", frame.f_back.f_lineno)
                    except Exception:
                        pass  # Skip if line number unavailable
                    
                    # Add arguments if requested (using custom attributes, not OTel standard)
                    if include_args and (args or kwargs):
                        span.set_attribute("function.args.count", len(args))
                        span.set_attribute("function.kwargs.count", len(kwargs))
                        # Add first few args (be careful with sensitive data)
                        for i, arg in enumerate(args[:3]):  # Limit to first 3 args
                            if isinstance(arg, (str, int, float, bool)):
                                span.set_attribute(f"function.arg.{i}", str(arg)[:100])
                    
                    # Execute function
                    result = func(*args, **kwargs)
                    
                    # Add result info if requested (using custom attributes)
                    if include_result and result is not None:
                        span.set_attribute("function.result.type", type(result).__name__)
                        if isinstance(result, (str, int, float, bool)):
                            span.set_attribute("function.result.value", str(result)[:100])
                    
                    # Set span status to OK on success
                    from opentelemetry.trace import Status, StatusCode
                    span.set_status(Status(StatusCode.OK))
                    
                    span.set_attribute("function.success", True)
                    return result
                    
                except Exception as e:
                    # Record the exception following OTel semantic conventions
                    span.set_attribute("function.success", False)
                    
                    # Use OTel semantic conventions for exceptions
                    span.set_attribute("exception.type", type(e).__name__)
                    span.set_attribute("exception.message", str(e))
                    
                    # Record the full exception with stack trace
                    span.record_exception(e)
                    
                    # Set span status to error
                    from opentelemetry.trace import Status, StatusCode
                    span.set_status(Status(StatusCode.ERROR, str(e)))
                    
                    raise
                    
        return wrapper
    return decorator

def get_trace_status():
    """Get current tracing status for debugging"""
    status = get_otel_status()
    status['tracer_available'] = tracer.is_available()
    return status

def log_trace_status():
    """Log current trace status - useful for debugging"""
    status = get_trace_status()
    logger.info(f"Trace Status: {status}")
    
    # Log export configuration details
    endpoint = os.getenv('OTEL_EXPORTER_OTLP_ENDPOINT')
    if endpoint:
        logger.info(f"OTLP Endpoint: {endpoint}")
        headers = os.getenv('OTEL_EXPORTER_OTLP_HEADERS')
        if headers:
            # Don't log full headers for security, just presence
            logger.info(f"OTLP Headers configured: {len(headers.split(','))} headers")
        else:
            logger.warning("OTLP Headers not configured")
    else:
        logger.warning("OTLP Endpoint not configured")
    
    return status 