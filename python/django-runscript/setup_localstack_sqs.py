#!/usr/bin/env python3
"""
LocalStack SQS Setup Script
Creates a test SQS queue and sends sample messages for testing the Django runscript
"""

import boto3
import json
import time
import sys
from botocore.exceptions import ClientError

# LocalStack configuration
LOCALSTACK_ENDPOINT = "http://localhost:4566"
REGION = "us-east-1"
QUEUE_NAME = "django-test-queue"

def create_sqs_client():
    """Create SQS client configured for LocalStack"""
    return boto3.client(
        'sqs',
        endpoint_url=LOCALSTACK_ENDPOINT,
        region_name=REGION,
        aws_access_key_id='test',  # LocalStack dummy credentials
        aws_secret_access_key='test'
    )

def create_queue(sqs_client, queue_name):
    """Create SQS queue"""
    try:
        response = sqs_client.create_queue(
            QueueName=queue_name,
            Attributes={
                'DelaySeconds': '0',
                'MaxReceiveCount': '3',
                'MessageRetentionPeriod': '86400',  # 1 day
                'VisibilityTimeoutSeconds': '300'   # 5 minutes
            }
        )
        queue_url = response['QueueUrl']
        print(f"✓ Queue created: {queue_url}")
        return queue_url
    except ClientError as e:
        if e.response['Error']['Code'] == 'QueueAlreadyExists':
            # Get existing queue URL
            response = sqs_client.get_queue_url(QueueName=queue_name)
            queue_url = response['QueueUrl']
            print(f"✓ Queue already exists: {queue_url}")
            return queue_url
        else:
            print(f"✗ Error creating queue: {e}")
            return None

def send_test_messages(sqs_client, queue_url, count=5):
    """Send test messages to the queue"""
    print(f"Sending {count} test messages...")
    
    messages = [
        {"type": "user_signup", "user_id": 123, "email": "test@example.com"},
        {"type": "order_placed", "order_id": 456, "amount": 99.99},
        {"type": "payment_processed", "payment_id": 789, "status": "success"},
        {"type": "notification_sent", "message_id": 101, "channel": "email"},
        {"type": "data_sync", "table": "users", "records_updated": 25}
    ]
    
    for i in range(count):
        message = messages[i % len(messages)]
        message["timestamp"] = time.time()
        message["message_id"] = f"msg-{i+1:03d}"
        
        try:
            response = sqs_client.send_message(
                QueueUrl=queue_url,
                MessageBody=json.dumps(message),
                MessageAttributes={
                    'MessageType': {
                        'StringValue': message['type'],
                        'DataType': 'String'
                    },
                    'Source': {
                        'StringValue': 'test-setup',
                        'DataType': 'String'
                    }
                }
            )
            print(f"  ✓ Message {i+1} sent: {message['type']} (ID: {response['MessageId']})")
        except ClientError as e:
            print(f"  ✗ Error sending message {i+1}: {e}")

def check_queue_status(sqs_client, queue_url):
    """Check queue attributes and message count"""
    try:
        response = sqs_client.get_queue_attributes(
            QueueUrl=queue_url,
            AttributeNames=['ApproximateNumberOfMessages', 'ApproximateNumberOfMessagesNotVisible']
        )
        
        attrs = response['Attributes']
        visible = attrs.get('ApproximateNumberOfMessages', '0')
        in_flight = attrs.get('ApproximateNumberOfMessagesNotVisible', '0')
        
        print(f"Queue Status:")
        print(f"  - Visible messages: {visible}")
        print(f"  - In-flight messages: {in_flight}")
        print(f"  - Total messages: {int(visible) + int(in_flight)}")
        
    except ClientError as e:
        print(f"✗ Error checking queue status: {e}")

def main():
    print("🚀 Setting up LocalStack SQS for Django runscript testing...")
    print(f"LocalStack endpoint: {LOCALSTACK_ENDPOINT}")
    
    # Wait for LocalStack to be ready
    print("Waiting for LocalStack to be ready...")
    sqs_client = create_sqs_client()
    
    max_retries = 10
    for attempt in range(max_retries):
        try:
            sqs_client.list_queues()
            print("✓ LocalStack SQS is ready!")
            break
        except Exception as e:
            if attempt < max_retries - 1:
                print(f"  Attempt {attempt + 1}/{max_retries} failed, retrying in 2 seconds...")
                time.sleep(2)
            else:
                print(f"✗ LocalStack not ready after {max_retries} attempts: {e}")
                print("Please make sure LocalStack is running with: docker-compose -f docker-compose.localstack.yml up")
                sys.exit(1)
    
    # Create queue
    queue_url = create_queue(sqs_client, QUEUE_NAME)
    if not queue_url:
        sys.exit(1)
    
    # Send test messages
    send_test_messages(sqs_client, queue_url)
    
    # Check final status
    check_queue_status(sqs_client, queue_url)
    
    print("\n🎉 LocalStack SQS setup complete!")
    print("\nEnvironment variables for testing:")
    print(f"export AWS_ENDPOINT_URL={LOCALSTACK_ENDPOINT}")
    print(f"export SQS_QUEUE_URL={queue_url}")
    print(f"export AWS_REGION={REGION}")
    print("export AWS_ACCESS_KEY_ID=test")
    print("export AWS_SECRET_ACCESS_KEY=test")
    
    print("\nTo run the Django SQS processor:")
    print("opentelemetry-instrument python manage.py runscript sqs_processor")

if __name__ == "__main__":
    main()