import os
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "mysite.settings")

import boto3
import json
import logging
import time
import datetime
from hello.tracing import traced_function, log_trace_status
from opentelemetry.trace import SpanKind

# Set up logging
logger = logging.getLogger(__name__)

@traced_function(include_args=True)
def get_queue_url(argv):
    """Get SQS queue URL from config or environment"""
    # Default to LocalStack queue URL for testing
    default_queue = 'http://localhost:4566/000000000000/django-test-queue'
    queue_url = os.getenv('SQS_QUEUE_URL', default_queue)
    return queue_url

@traced_function(include_args=True, span_kind=SpanKind.CONSUMER)
def receive_message(queue_url, sqs, account):
    """Receive messages from SQS queue"""
    response = sqs.receive_message(
        QueueUrl=queue_url,
        AttributeNames=["SentTimestamp"],
        MaxNumberOfMessages=10,
        MessageAttributeNames=["All"],
        VisibilityTimeout=300,
        WaitTimeSeconds=0,
    )
    return response

@traced_function(include_args=True, span_kind=SpanKind.INTERNAL)
def process_message(queue_url, sqs, account, response):
    """Process received SQS messages"""
    for message in response["Messages"]:
        receipt_handle = message["ReceiptHandle"]
        try:
            start = datetime.datetime.now()
            decoded_message = json.loads(message["Body"])
            logger.info(f"Processing message: {decoded_message}")
            
            # Add your message processing logic here
            # This is where you'd handle the actual message content
            processing_duration = (datetime.datetime.now() - start).total_seconds()
            logger.info(f"Message processed in {processing_duration:.2f} seconds")
            
        except json.JSONDecodeError as e:
            logger.error(f"Failed to decode message JSON: {e}")
        except Exception as e:
            logger.error(f"Error processing message: {e}")
        finally:
            # Delete message from queue after processing (or after failure)
            try:
                sqs.delete_message(QueueUrl=queue_url, ReceiptHandle=receipt_handle)
                logger.info(f"Message deleted from queue")
            except Exception as delete_error:
                logger.error(f"Failed to delete message: {delete_error}")

@traced_function(span_kind=SpanKind.CONSUMER, include_args=True)
def run(*args):
    """Main entry point for Django runscript"""
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
        sqs = boto3.client('sqs', **sqs_config)
        print("SQS client initialized successfully")
    except Exception as e:
        print(f"Failed to initialize SQS client: {e}")
        print("Please ensure AWS credentials are configured or LocalStack is running")
        return
    
    # Configuration - you can modify these
    argv = {
        'delay': int(os.getenv('SQS_POLLING_DELAY', '5'))  # seconds to wait between polls
    }
    account = os.getenv('AWS_ACCOUNT_ID', 'unknown')
    
    try:
        queue_url = get_queue_url(argv)
        print(f"Processing messages from queue: {queue_url}")
        
        # For testing, we'll run a limited loop instead of infinite
        max_iterations = int(os.getenv('MAX_ITERATIONS', '10'))
        iteration = 0
        
        while iteration < max_iterations:
            iteration += 1
            print(f"Polling iteration {iteration}/{max_iterations}")
            
            try:
                response = receive_message(queue_url, sqs, account)
                if "Messages" not in response:
                    print(f"No messages received, waiting {argv['delay']} seconds...")
                    time.sleep(argv["delay"])
                else:
                    print(f"Received {len(response['Messages'])} messages")
                    process_message(queue_url, sqs, account, response)
                    
            except Exception as e:
                logger.error(f"Error in polling iteration {iteration}: {e}")
                # Continue to next iteration instead of breaking
                time.sleep(argv["delay"])
                
    except KeyboardInterrupt:
        print("SQS processing interrupted by user")
    except Exception as e:
        logger.error(f"Fatal error in SQS processing: {e}")
        raise e
    
    print("SQS processing completed successfully")