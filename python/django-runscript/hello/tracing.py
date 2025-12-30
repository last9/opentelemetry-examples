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

def _env_truthy(name: str, default: bool = False) -> bool:
    val = os.getenv(name)
    if val is None:
        return default
    return val.strip().lower() in ("1", "true", "yes", "y", "on")

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

    def extract_queue_metadata(self, queue_url: str) -> dict:
        """
        Extract queue metadata from SQS queue URL automatically.

        Supports AWS and LocalStack URL formats:
        - AWS: https://sqs.{region}.amazonaws.com/{account_id}/{queue_name}
        - LocalStack: http://localhost:4566/{account_id}/{queue_name}

        Returns:
            dict: Queue metadata including queue_url, server_address, server_port,
                  account_id, queue_name, and region (if AWS)
        """
        try:
            from urllib.parse import urlparse
            parsed = urlparse(queue_url)
            path_parts = [p for p in parsed.path.split('/') if p]

            metadata = {
                'queue_url': queue_url,
                'server_address': parsed.hostname or 'unknown',
                'server_port': parsed.port or (443 if parsed.scheme == 'https' else 80)
            }

            # Extract account ID and queue name from path
            if len(path_parts) >= 2:
                metadata['account_id'] = path_parts[0]
                metadata['queue_name'] = path_parts[1]
            elif len(path_parts) == 1:
                metadata['queue_name'] = path_parts[0]

            # Extract region from AWS hostname
            if parsed.hostname and 'amazonaws.com' in parsed.hostname:
                hostname_parts = parsed.hostname.split('.')
                if len(hostname_parts) >= 3 and hostname_parts[0] == 'sqs':
                    metadata['region'] = hostname_parts[1]

            return metadata
        except Exception as e:
            logger.warning(f"Failed to extract queue metadata: {e}")
            return {'queue_url': queue_url}

    def _instrument_boto(self):
        """Instrument boto3/botocore for automatic AWS SDK tracing with context propagation"""
        try:
            from opentelemetry.instrumentation.botocore import BotocoreInstrumentor
            from opentelemetry import propagate, context as otel_context
            import boto3
            import boto3.session

            def sqs_request_hook(span, service_name, operation_name, api_params, **kwargs):
                """
                Enhanced hook: Automatically inject trace context and capture comprehensive SQS attributes
                This hook is called before sending AWS requests
                """
                # BotocoreInstrumentor commonly passes service names like "SQS"
                if (service_name or "").lower() == 'sqs':
                    # COMMON: Extract and add queue metadata for all operations
                    queue_url = api_params.get('QueueUrl')
                    if queue_url:
                        queue_meta = _bootstrap.extract_queue_metadata(queue_url)
                        span.set_attribute('aws.sqs.queue.url', queue_meta['queue_url'])
                        span.set_attribute('messaging.destination.name', queue_meta.get('queue_name', 'unknown'))
                        span.set_attribute('server.address', queue_meta.get('server_address', 'unknown'))
                        if 'server_port' in queue_meta:
                            span.set_attribute('server.port', queue_meta['server_port'])
                        if 'account_id' in queue_meta:
                            span.set_attribute('messaging.sqs.queue.account_id', queue_meta['account_id'])
                        if 'region' in queue_meta:
                            span.set_attribute('messaging.sqs.queue.region', queue_meta['region'])

                    # SENDMESSAGE: Capture message details and inject trace context
                    if operation_name == 'SendMessage':
                        span.set_attribute('messaging.operation.name', 'send')
                        span.set_attribute('messaging.operation.type', 'send')

                        # Capture message body size
                        message_body = api_params.get('MessageBody', '')
                        span.set_attribute('messaging.sqs.message.body_size', len(message_body))

                        # Capture delay seconds if specified
                        if 'DelaySeconds' in api_params:
                            span.set_attribute('messaging.sqs.message.delay_seconds', api_params['DelaySeconds'])

                        # Initialize MessageAttributes if not present
                        message_attrs = api_params.get('MessageAttributes', {})

                        # Capture custom MessageAttributes (business data) before adding trace context
                        custom_attrs = {k: v for k, v in message_attrs.items()
                                      if k not in ['traceparent', 'tracestate']}
                        if custom_attrs:
                            span.set_attribute('messaging.sqs.message.custom_attributes_count', len(custom_attrs))
                            # Capture specific business attributes
                            for attr_name in ['MessageType', 'Priority', 'Source']:
                                if attr_name in custom_attrs:
                                    attr_data = custom_attrs[attr_name]
                                    if isinstance(attr_data, dict):
                                        attr_value = attr_data.get('StringValue')
                                        if attr_value:
                                            span.set_attribute(f'messaging.sqs.message.{attr_name.lower()}', attr_value)

                        # Inject trace context into a carrier
                        carrier = {}
                        propagate.inject(carrier)

                        # Add trace context to MessageAttributes
                        for key, value in carrier.items():
                            if key not in message_attrs:  # Don't overwrite existing attributes
                                message_attrs[key] = {
                                    'StringValue': value,
                                    'DataType': 'String'
                                }

                        api_params['MessageAttributes'] = message_attrs
                        logger.debug(f"Auto-injected trace context into SQS SendMessage: {list(carrier.keys())}")

                    # RECEIVEMESSAGE: Capture receive parameters
                    elif operation_name == 'ReceiveMessage':
                        span.set_attribute('messaging.operation.name', 'receive')
                        span.set_attribute('messaging.operation.type', 'receive')

                        if 'MaxNumberOfMessages' in api_params:
                            span.set_attribute('messaging.sqs.receive.max_messages', api_params['MaxNumberOfMessages'])
                        if 'WaitTimeSeconds' in api_params:
                            span.set_attribute('messaging.sqs.receive.wait_time_seconds', api_params['WaitTimeSeconds'])
                        if 'VisibilityTimeout' in api_params:
                            span.set_attribute('messaging.sqs.receive.visibility_timeout', api_params['VisibilityTimeout'])

                    # DELETEMESSAGE: Mark as settle operation
                    elif operation_name == 'DeleteMessage':
                        span.set_attribute('messaging.operation.name', 'settle')
                        span.set_attribute('messaging.operation.type', 'settle')

                    # SENDMESSAGEBATCH: Capture batch details and inject trace context
                    elif operation_name == 'SendMessageBatch' and 'Entries' in api_params:
                        span.set_attribute('messaging.operation.name', 'send')
                        span.set_attribute('messaging.operation.type', 'send')

                        entries = api_params.get('Entries', [])
                        span.set_attribute('messaging.sqs.batch.size', len(entries))

                        total_body_size = sum(len(entry.get('MessageBody', '')) for entry in entries)
                        span.set_attribute('messaging.sqs.batch.total_body_size', total_body_size)

                        # Inject trace context for each message in batch
                        for entry in entries:
                            # Initialize MessageAttributes if not present
                            message_attrs = entry.get('MessageAttributes', {})

                            # Inject trace context for each message
                            carrier = {}
                            propagate.inject(carrier)

                            for key, value in carrier.items():
                                if key not in message_attrs:
                                    message_attrs[key] = {
                                        'StringValue': value,
                                        'DataType': 'String'
                                    }

                            entry['MessageAttributes'] = message_attrs

                        logger.debug(f"Auto-injected trace context into {len(entries)} batch messages")

            def sqs_response_hook(span, service_name, operation_name, api_params, result, **kwargs):
                """
                Enhanced hook: Capture comprehensive response metadata from SQS operations
                This hook is called after receiving AWS responses
                """
                if (service_name or "").lower() == 'sqs':
                    # COMMON: Capture AWS request ID and HTTP status
                    response_metadata = result.get('ResponseMetadata', {})
                    request_id = response_metadata.get('RequestId')
                    if request_id:
                        span.set_attribute('aws.request_id', request_id)

                    http_status = response_metadata.get('HTTPStatusCode')
                    if http_status:
                        span.set_attribute('http.status_code', http_status)

                    # SENDMESSAGE: Capture message response
                    if operation_name == 'SendMessage':
                        message_id = result.get('MessageId')
                        if message_id:
                            span.set_attribute('messaging.message.id', message_id)
                            span.set_attribute('messaging.sqs.message.id', message_id)

                        md5_body = result.get('MD5OfMessageBody')
                        if md5_body:
                            span.set_attribute('messaging.sqs.message.md5_of_body', md5_body)

                        sequence_number = result.get('SequenceNumber')
                        if sequence_number:
                            span.set_attribute('messaging.sqs.message.sequence_number', sequence_number)

                    # RECEIVEMESSAGE: Capture message details
                    elif operation_name == 'ReceiveMessage':
                        messages = result.get('Messages', [])
                        message_count = len(messages)
                        span.set_attribute('messaging.sqs.receive.message_count', message_count)

                        if messages:
                            # Capture total body size
                            total_body_size = sum(len(msg.get('Body', '')) for msg in messages)
                            span.set_attribute('messaging.sqs.receive.total_body_size', total_body_size)

                            # Capture first message details (representative)
                            first_msg = messages[0]

                            message_id = first_msg.get('MessageId')
                            if message_id:
                                span.set_attribute('messaging.message.id', message_id)

                            # Capture system attributes
                            msg_attrs = first_msg.get('Attributes', {})
                            if msg_attrs:
                                if 'SentTimestamp' in msg_attrs:
                                    span.set_attribute('messaging.sqs.message.sent_timestamp', msg_attrs['SentTimestamp'])
                                if 'ApproximateReceiveCount' in msg_attrs:
                                    span.set_attribute('messaging.sqs.message.approximate_receive_count',
                                                     int(msg_attrs['ApproximateReceiveCount']))
                                if 'ApproximateFirstReceiveTimestamp' in msg_attrs:
                                    span.set_attribute('messaging.sqs.message.approximate_first_receive_timestamp',
                                                     msg_attrs['ApproximateFirstReceiveTimestamp'])

                            # Capture custom MessageAttributes
                            custom_msg_attrs = first_msg.get('MessageAttributes', {})
                            if custom_msg_attrs:
                                custom_attrs = {k: v for k, v in custom_msg_attrs.items()
                                              if k not in ['traceparent', 'tracestate']}
                                if custom_attrs:
                                    span.set_attribute('messaging.sqs.message.custom_attributes_count', len(custom_attrs))
                                    # Capture specific business attributes
                                    for attr_name in ['MessageType', 'Priority', 'Source']:
                                        if attr_name in custom_attrs:
                                            attr_data = custom_attrs[attr_name]
                                            if isinstance(attr_data, dict):
                                                attr_value = attr_data.get('StringValue')
                                                if attr_value:
                                                    span.set_attribute(f'messaging.sqs.message.{attr_name.lower()}', attr_value)

                            # Log for debugging
                            logger.debug(f"Received {message_count} SQS messages")
                            for msg in messages:
                                msg_attrs = msg.get('MessageAttributes', {})
                                has_context = any(
                                    key in ['traceparent', 'tracestate']
                                    for key in msg_attrs.keys()
                                )
                                if has_context:
                                    logger.debug(f"Message {msg.get('MessageId', 'unknown')} contains trace context")

                    # SENDMESSAGEBATCH: Capture batch results
                    elif operation_name == 'SendMessageBatch':
                        successful = result.get('Successful', [])
                        failed = result.get('Failed', [])

                        span.set_attribute('messaging.sqs.batch.success_count', len(successful))
                        span.set_attribute('messaging.sqs.batch.failed_count', len(failed))

                        if failed:
                            failure_codes = [f.get('Code', 'Unknown') for f in failed]
                            span.set_attribute('messaging.sqs.batch.failure_codes', ','.join(failure_codes))

            # Check if already instrumented (for span creation). This does not cover
            # message attribute mutation; we register native botocore handlers below.
            if not BotocoreInstrumentor().is_instrumented_by_opentelemetry:
                BotocoreInstrumentor().instrument(
                    request_hook=sqs_request_hook,
                    response_hook=sqs_response_hook
                )
                logger.info("Botocore instrumentation enabled with automatic SQS context propagation")
            else:
                logger.debug("Botocore already instrumented")

            # ----
            # IMPORTANT: Reliable SQS context injection + attribute enrichment
            #
            # In some botocore/opentelemetry-instrumentation versions, mutating `api_params`
            # inside BotocoreInstrumentor request hooks does not reliably affect the outgoing request.
            #
            # To guarantee "no manual input" context propagation, we also register native botocore
            # event handlers that mutate the real request params in-place.
            # ----

            def _set_common_sqs_span_attrs(span, queue_url: str):
                try:
                    queue_meta = _bootstrap.extract_queue_metadata(queue_url)
                    span.set_attribute('aws.sqs.queue.url', queue_meta.get('queue_url', queue_url))
                    span.set_attribute('messaging.destination.name', queue_meta.get('queue_name', 'unknown'))
                    span.set_attribute('server.address', queue_meta.get('server_address', 'unknown'))
                    if 'server_port' in queue_meta:
                        span.set_attribute('server.port', queue_meta['server_port'])
                    if 'account_id' in queue_meta:
                        span.set_attribute('messaging.sqs.queue.account_id', queue_meta['account_id'])
                    if 'region' in queue_meta:
                        span.set_attribute('messaging.sqs.queue.region', queue_meta['region'])
                except Exception as e:
                    logger.debug(f"Failed to set common SQS span attrs: {e}")

            def _inject_trace_context_into_message_attributes(message_attrs: dict):
                carrier = {}
                propagate.inject(carrier)
                if not carrier:
                    return
                for key, value in carrier.items():
                    message_attrs.setdefault(key, {'StringValue': value, 'DataType': 'String'})

            def _before_parameter_build_sqs_send(params, **kwargs):
                try:
                    if not isinstance(params, dict):
                        return
                    span = trace.get_current_span()
                    queue_url = params.get('QueueUrl')
                    if span and span.is_recording() and queue_url:
                        _set_common_sqs_span_attrs(span, queue_url)
                        span.set_attribute('messaging.operation.name', 'send')
                        span.set_attribute('messaging.operation.type', 'send')

                    # Capture custom (business) attributes count before injection
                    msg_attrs = params.setdefault('MessageAttributes', {}) or {}
                    if isinstance(msg_attrs, dict):
                        custom_attrs = {k: v for k, v in msg_attrs.items() if k not in ['traceparent', 'tracestate']}
                        if span and span.is_recording() and custom_attrs:
                            span.set_attribute('messaging.sqs.message.custom_attributes_count', len(custom_attrs))
                            for attr_name in ['MessageType', 'Priority', 'Source']:
                                if attr_name in custom_attrs:
                                    attr_data = custom_attrs[attr_name]
                                    if isinstance(attr_data, dict):
                                        attr_value = attr_data.get('StringValue')
                                        if attr_value:
                                            span.set_attribute(f'messaging.sqs.message.{attr_name.lower()}', attr_value)

                        # Inject W3C trace context (traceparent/tracestate) automatically
                        _inject_trace_context_into_message_attributes(msg_attrs)
                        params['MessageAttributes'] = msg_attrs
                except Exception as e:
                    logger.debug(f"SQS SendMessage before-parameter-build handler failed: {e}")

            def _before_parameter_build_sqs_send_batch(params, **kwargs):
                try:
                    if not isinstance(params, dict):
                        return
                    span = trace.get_current_span()
                    queue_url = params.get('QueueUrl')
                    if span and span.is_recording() and queue_url:
                        _set_common_sqs_span_attrs(span, queue_url)
                        span.set_attribute('messaging.operation.name', 'send')
                        span.set_attribute('messaging.operation.type', 'send')

                    entries = params.get('Entries') or []
                    if isinstance(entries, list):
                        if span and span.is_recording():
                            span.set_attribute('messaging.sqs.batch.size', len(entries))
                        for entry in entries:
                            if not isinstance(entry, dict):
                                continue
                            msg_attrs = entry.setdefault('MessageAttributes', {}) or {}
                            if isinstance(msg_attrs, dict):
                                _inject_trace_context_into_message_attributes(msg_attrs)
                                entry['MessageAttributes'] = msg_attrs
                except Exception as e:
                    logger.debug(f"SQS SendMessageBatch before-parameter-build handler failed: {e}")

            def _before_parameter_build_sqs_receive(params, **kwargs):
                try:
                    if not isinstance(params, dict):
                        return
                    span = trace.get_current_span()
                    queue_url = params.get('QueueUrl')
                    if span and span.is_recording() and queue_url:
                        _set_common_sqs_span_attrs(span, queue_url)
                        span.set_attribute('messaging.operation.name', 'receive')
                        span.set_attribute('messaging.operation.type', 'receive')

                    # IMPORTANT: consumers must request MessageAttributes to receive `traceparent`.
                    # This ensures distributed tracing can continue without the customer needing
                    # to remember MessageAttributeNames=["All"] everywhere.
                    if _env_truthy("OTEL_SQS_AUTO_INCLUDE_MESSAGE_ATTRIBUTES", default=True):
                        if 'MessageAttributeNames' not in params:
                            params['MessageAttributeNames'] = ['All']
                except Exception as e:
                    logger.debug(f"SQS ReceiveMessage before-parameter-build handler failed: {e}")

            def _before_parameter_build_sqs_delete(params, **kwargs):
                try:
                    if not isinstance(params, dict):
                        return
                    span = trace.get_current_span()
                    queue_url = params.get('QueueUrl')
                    if span and span.is_recording() and queue_url:
                        _set_common_sqs_span_attrs(span, queue_url)
                        span.set_attribute('messaging.operation.name', 'settle')
                        span.set_attribute('messaging.operation.type', 'settle')
                except Exception as e:
                    logger.debug(f"SQS DeleteMessage before-parameter-build handler failed: {e}")

            def _register_sqs_param_handlers(botocore_session):
                """
                Register handlers on a specific botocore session.

                Why: customers often create clients via boto3.Session().client(...),
                which uses that session’s underlying botocore session (not boto3.DEFAULT_SESSION).
                """
                # Use unique IDs so repeated calls don't duplicate handlers.
                botocore_session.register(
                    'before-parameter-build.sqs.SendMessage',
                    _before_parameter_build_sqs_send,
                    unique_id='otel_sqs_before_send',
                )
                botocore_session.register(
                    'before-parameter-build.sqs.SendMessageBatch',
                    _before_parameter_build_sqs_send_batch,
                    unique_id='otel_sqs_before_send_batch',
                )
                botocore_session.register(
                    'before-parameter-build.sqs.ReceiveMessage',
                    _before_parameter_build_sqs_receive,
                    unique_id='otel_sqs_before_receive',
                )
                botocore_session.register(
                    'before-parameter-build.sqs.DeleteMessage',
                    _before_parameter_build_sqs_delete,
                    unique_id='otel_sqs_before_delete',
                )

            # 1) Register on boto3 default session (covers boto3.client(...))
            if boto3.DEFAULT_SESSION is None:
                boto3.setup_default_session()
            _register_sqs_param_handlers(boto3.DEFAULT_SESSION._session)

            # 2) Patch boto3.session.Session.client to register on *that* session too (covers boto3.Session().client(...))
            # Guard so we patch only once per process.
            if not getattr(boto3.session.Session, "_otel_sqs_client_patched", False):
                _orig_client = boto3.session.Session.client

                def _otel_wrapped_client(self, *args, **kwargs):
                    try:
                        _register_sqs_param_handlers(self._session)
                    except Exception as e:
                        logger.debug(f"Failed to register SQS param handlers on boto3.Session: {e}")
                    return _orig_client(self, *args, **kwargs)

                boto3.session.Session.client = _otel_wrapped_client
                boto3.session.Session._otel_sqs_client_patched = True

            return True
        except ImportError:
            logger.warning("opentelemetry-instrumentation-botocore not installed. Run: pip install opentelemetry-instrumentation-botocore")
            return False
        except Exception as e:
            logger.warning(f"Failed to instrument botocore: {e}")
            return False

    def _set_defaults(self):
        """Set sensible defaults for all OTEL environment variables"""
        defaults = {
            'OTEL_SERVICE_NAME': self._get_service_name(),
            'OTEL_TRACES_EXPORTER': 'otlp',
            'OTEL_METRICS_EXPORTER': 'otlp',
            # Prod-friendly default: propagate parent sampling, otherwise sample at 10%.
            # Customers can override via OTEL_TRACES_SAMPLER + OTEL_TRACES_SAMPLER_ARG.
            'OTEL_TRACES_SAMPLER': 'parentbased_traceidratio',
            'OTEL_TRACES_SAMPLER_ARG': os.getenv('OTEL_TRACES_SAMPLER_ARG', '0.1'),
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
                if _env_truthy("OTEL_BOOTSTRAP_CONNECTIVITY_TEST", default=False):
                    endpoint_reachable = self._test_connectivity(self.endpoint)
                # Only add console fallback when explicitly enabled (or forced by caller)
                if (force_console_fallback or _env_truthy("OTEL_CONSOLE_FALLBACK", default=False)) and not endpoint_reachable:
                    self._configure_console_fallback()
            else:
                logger.warning("OTEL_EXPORTER_OTLP_ENDPOINT not set (no OTLP export will occur unless configured)")
                if force_console_fallback or _env_truthy("OTEL_CONSOLE_FALLBACK", default=False):
                    logger.info("Console fallback enabled; exporting spans to console")
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
            
            # Optional: emit a one-time test span (disabled by default for prod noise reduction)
            if _env_truthy("OTEL_BOOTSTRAP_TEST_SPAN", default=False):
                tracer = trace.get_tracer("bootstrap-test")
                with tracer.start_as_current_span("initialization-test") as span:
                    span.set_attribute("otel.bootstrap.success", True)
                    span.set_attribute("service.name", self.service_name)
                    span.set_attribute("endpoint.reachable", endpoint_reachable)
                    span.set_attribute("exporter.type", os.getenv('OTEL_TRACES_EXPORTER', 'unknown'))
                    logger.info(
                        f"Bootstrap test span created with trace_id: {format(span.get_span_context().trace_id, '032x')}"
                    )

            # Instrument boto3/botocore for AWS SDK auto-tracing
            self._instrument_boto()

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

def traced_function(span_kind=SpanKind.INTERNAL, include_args=False, include_result=False, create_root=True):
    """
    Enhanced tracing decorator with error handling
    
    Args:
        span_kind: OpenTelemetry span kind
        include_args: Whether to include function arguments as span attributes
        include_result: Whether to include return value as span attribute
        create_root: Whether to auto-create root span if none exists
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
            
            # Check if we need to create a root span
            current_span = trace.get_current_span()
            needs_root = create_root and (not current_span or not current_span.is_recording())
            
            def execute_traced_function():
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
            
            # Execute with or without root span
            if needs_root:
                # Create root span for this execution context
                root_tracer = trace.get_tracer("root-context")
                with root_tracer.start_as_current_span(
                    f"root.{func.__name__}", 
                    kind=SpanKind.INTERNAL
                ) as root_span:
                    root_span.set_attribute("root.auto_created", True)
                    root_span.set_attribute("root.function", func.__name__)
                    logger.debug(f"Auto-created root span for {func.__name__}")
                    return execute_traced_function()
            else:
                return execute_traced_function()
                    
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