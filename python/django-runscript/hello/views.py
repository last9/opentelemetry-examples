"""
Django views for ECS deployment with AWS SQS integration
All AWS SDK calls are automatically traced to Last9
"""
from django.http import JsonResponse
from django.views.decorators.http import require_http_methods
import boto3
import os
import json
import logging

logger = logging.getLogger(__name__)


@require_http_methods(["GET"])
def health(request):
    """
    Health check endpoint for ECS/ALB health checks
    """
    return JsonResponse({
        'status': 'healthy',
        'service': os.getenv('OTEL_SERVICE_NAME', 'django-app')
    })


@require_http_methods(["POST"])
def send_sqs_message(request):
    """
    Example endpoint: Send message to SQS

    AWS credentials come from IAM task role automatically!
    SQS metadata (queue URL, region, message ID) automatically captured in traces!
    Traces sent to Last9 automatically!

    Usage:
        POST /api/send-message
        Body: {"message": "test data"}
    """
    try:
        # Get request data
        try:
            data = json.loads(request.body)
            message_body = data.get('message', 'default message')
        except json.JSONDecodeError:
            return JsonResponse({'error': 'Invalid JSON'}, status=400)

        # Create SQS client - uses IAM role, no credentials needed!
        region = os.getenv('AWS_REGION', 'us-east-1')
        sqs = boto3.client('sqs', region_name=region)

        # Get queue URL from environment
        queue_url = os.getenv('SQS_QUEUE_URL')
        if not queue_url:
            # Fallback: get by queue name
            queue_name = os.getenv('SQS_QUEUE_NAME')
            if not queue_name:
                return JsonResponse({
                    'error': 'SQS_QUEUE_URL or SQS_QUEUE_NAME not configured'
                }, status=500)

            # Resolve queue URL by name
            response = sqs.get_queue_url(QueueName=queue_name)
            queue_url = response['QueueUrl']

        # Send message - automatically traced with all metadata!
        # Trace will include: queue URL, region, message ID, etc.
        response = sqs.send_message(
            QueueUrl=queue_url,
            MessageBody=json.dumps({
                'message': message_body,
                'source': 'django-ecs-app'
            })
        )

        logger.info(f"Sent SQS message: {response['MessageId']}")

        return JsonResponse({
            'status': 'success',
            'message_id': response['MessageId'],
            'queue_url': queue_url
        })

    except Exception as e:
        logger.error(f"Failed to send SQS message: {e}", exc_info=True)
        return JsonResponse({
            'error': str(e)
        }, status=500)


@require_http_methods(["GET"])
def get_queue_info(request):
    """
    Example endpoint: Get SQS queue information

    This demonstrates how AWS SDK calls are automatically traced
    without any special configuration!
    """
    try:
        region = os.getenv('AWS_REGION', 'us-east-1')
        sqs = boto3.client('sqs', region_name=region)

        # Get queue URL
        queue_url = os.getenv('SQS_QUEUE_URL')
        if not queue_url:
            queue_name = os.getenv('SQS_QUEUE_NAME')
            if not queue_name:
                return JsonResponse({
                    'error': 'SQS_QUEUE_URL or SQS_QUEUE_NAME not configured'
                }, status=500)

            response = sqs.get_queue_url(QueueName=queue_name)
            queue_url = response['QueueUrl']

        # Get queue attributes - automatically traced!
        attributes = sqs.get_queue_attributes(
            QueueUrl=queue_url,
            AttributeNames=['All']
        )

        return JsonResponse({
            'queue_url': queue_url,
            'attributes': attributes.get('Attributes', {})
        })

    except Exception as e:
        logger.error(f"Failed to get queue info: {e}", exc_info=True)
        return JsonResponse({
            'error': str(e)
        }, status=500)
