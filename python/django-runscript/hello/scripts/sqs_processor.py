import os
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "mysite.settings")

import boto3
import json
import logging
import time
import datetime
from hello.tracing import traced_function, log_trace_status
from opentelemetry.trace import SpanKind
from opentelemetry import trace, propagate, context

# Set up logging
logger = logging.getLogger(__name__)

# BOTOCORE AUTO-INSTRUMENTATION
# ==============================
# Botocore auto-instrumentation will automatically create spans for:
# - sqs.receive_message() -> Span with operation "SQS.ReceiveMessage"
# - sqs.delete_message() -> Span with operation "SQS.DeleteMessage"
# - sqs.send_message() -> Span with operation "SQS.SendMessage"
# All AWS-specific attributes (queue URL, message IDs, etc.) are automatically captured!
#
# CONTEXT PROPAGATION
# ===================
# For distributed tracing, trace context needs to be extracted from SQS
# message attributes and linked to the current span. This ensures the
# consumer's trace is connected to the producer's trace.

def get_queue_url():
    """Get SQS queue URL from config or environment"""
    # Default to LocalStack queue URL for testing
    default_queue = 'http://localhost:4566/000000000000/django-test-queue'
    queue_url = os.getenv('SQS_QUEUE_URL', default_queue)
    return queue_url

def extract_trace_context_from_message(message):
    """
    Extract OpenTelemetry trace context from SQS message attributes

    This enables distributed tracing by linking the consumer span
    to the producer span that sent the message.
    """
    message_attributes = message.get('MessageAttributes', {})

    # Extract trace context from message attributes
    carrier = {}
    for key, value in message_attributes.items():
        # Look for trace context headers (traceparent, tracestate, etc.)
        if isinstance(value, dict) and 'StringValue' in value:
            carrier[key] = value['StringValue']

    if carrier:
        # Extract context and return it
        ctx = propagate.extract(carrier)
        logger.info(f"Extracted trace context from message attributes: {list(carrier.keys())}")
        return ctx
    else:
        logger.debug("No trace context found in message attributes")
        return None


@traced_function(include_args=False, span_kind=SpanKind.CONSUMER)
def process_message_business_logic(message_body, parent_context=None):
    """
    Process the actual message business logic

    This is manually traced as CONSUMER because it represents the consumption
    and processing of a message from the queue.

    Args:
        message_body: The SQS message body
        parent_context: Optional OpenTelemetry context from producer (for distributed tracing)
    """
    try:
        start = datetime.datetime.now()
        decoded_message = json.loads(message_body)
        logger.info(f"Processing message: {decoded_message}")

        # Get current span to add custom attributes
        current_span = trace.get_current_span()
        if current_span and current_span.is_recording():
            current_span.set_attribute("message.type", decoded_message.get("type", "unknown"))
            if "order_id" in decoded_message:
                current_span.set_attribute("order.id", decoded_message["order_id"])

        # Add your message processing logic here
        # This is where you'd handle the actual message content
        # Example: Update database, call external APIs, transform data, etc.

        processing_duration = (datetime.datetime.now() - start).total_seconds()
        logger.info(f"Message processed in {processing_duration:.2f} seconds")

        return decoded_message

    except json.JSONDecodeError as e:
        logger.error(f"Failed to decode message JSON: {e}")
        raise
    except Exception as e:
        logger.error(f"Error processing message: {e}")
        raise

@traced_function(span_kind=SpanKind.CONSUMER, include_args=False)
def run(*args):
    """
    Main entry point for Django runscript

    This function is manually traced as the entry point (CONSUMER span kind).
    All boto3/SQS operations within are automatically instrumented by botocore,
    so no need to manually create spans for AWS SDK calls!
    """
    # Log trace status for debugging
    status = log_trace_status()
    print(f"OpenTelemetry Status: {status}")

    # Setup AWS SQS client
    # Support both real AWS and LocalStack
    aws_endpoint = os.getenv('AWS_ENDPOINT_URL')  # For LocalStack
    sqs_config = {
        'region_name': os.getenv('AWS_REGION', 'us-east-1')
    }

    # Add LocalStack endpoint if specified
    if aws_endpoint:
        sqs_config['endpoint_url'] = aws_endpoint
        print(f"Using LocalStack endpoint: {aws_endpoint}")

    try:
        # boto3.client() call is automatically traced by botocore instrumentation
        sqs = boto3.client('sqs', **sqs_config)
        print("SQS client initialized successfully")
    except Exception as e:
        print(f"Failed to initialize SQS client: {e}")
        print("Please ensure AWS credentials are configured or LocalStack is running")
        return

    # Configuration - you can modify these
    polling_delay = int(os.getenv('SQS_POLLING_DELAY', '5'))

    try:
        queue_url = get_queue_url()
        print(f"Processing messages from queue: {queue_url}")

        # For testing, we'll run a limited loop instead of infinite
        max_iterations = int(os.getenv('MAX_ITERATIONS', '10'))
        iteration = 0

        while iteration < max_iterations:
            iteration += 1
            print(f"Polling iteration {iteration}/{max_iterations}")

            try:
                # receive_message() is automatically traced by botocore
                # Creates span: "SQS.ReceiveMessage" with all AWS attributes
                response = sqs.receive_message(
                    QueueUrl=queue_url,
                    AttributeNames=["SentTimestamp"],
                    MaxNumberOfMessages=10,
                    MessageAttributeNames=["All"],
                    VisibilityTimeout=300,
                    WaitTimeSeconds=0,
                )

                if "Messages" not in response:
                    print(f"No messages received, waiting {polling_delay} seconds...")
                    time.sleep(polling_delay)
                else:
                    print(f"Received {len(response['Messages'])} messages")

                    # Process each message
                    for message in response["Messages"]:
                        receipt_handle = message["ReceiptHandle"]
                        message_id = message.get("MessageId", "unknown")

                        try:
                            # Extract trace context from message for distributed tracing
                            parent_context = extract_trace_context_from_message(message)

                            if parent_context:
                                # Process with parent context to link traces
                                token = context.attach(parent_context)
                                try:
                                    process_message_business_logic(message["Body"], parent_context)
                                finally:
                                    context.detach(token)
                            else:
                                # Process without parent context (new trace)
                                process_message_business_logic(message["Body"])

                            # delete_message() is automatically traced by botocore
                            # Creates span: "SQS.DeleteMessage" with queue URL, receipt handle
                            sqs.delete_message(
                                QueueUrl=queue_url,
                                ReceiptHandle=receipt_handle
                            )
                            logger.info(f"Message {message_id} deleted from queue")

                        except Exception as process_error:
                            logger.error(f"Failed to process message {message_id}: {process_error}")
                            # Message will remain in queue for retry

            except Exception as e:
                logger.error(f"Error in polling iteration {iteration}: {e}")
                # Continue to next iteration instead of breaking
                time.sleep(polling_delay)

    except KeyboardInterrupt:
        print("SQS processing interrupted by user")
    except Exception as e:
        logger.error(f"Fatal error in SQS processing: {e}")
        raise e

    print("SQS processing completed successfully")