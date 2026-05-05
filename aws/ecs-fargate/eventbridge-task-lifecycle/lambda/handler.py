"""
ECS EventBridge → Last9 OTLP logs forwarder.

Standalone copy of the Lambda handler for local testing and reference.
The canonical version is inlined in cloudformation.yaml under ZipFile.
Keep both in sync when making changes.

Handles all ECS lifecycle event types:
  - ECS Task State Change (full lifecycle)
  - ECS Service Action (deployments, scaling)
  - ECS Deployment State Change (deployment outcomes)

Local test:
    export LAST9_OTLP_ENDPOINT=https://otlp.last9.io/v1/logs
    export LAST9_AUTH=<base64-credentials>
    python handler.py
"""

import json
import os
import time
import urllib.error
import urllib.request
from datetime import datetime

ENDPOINT = os.environ['LAST9_OTLP_ENDPOINT']
AUTH = os.environ['LAST9_AUTH']

# Map EventBridge detail-type to a short event name for Last9 attributes.
EVENT_NAMES = {
    'ECS Task State Change': 'ecs.task.state_change',
    'ECS Service Action': 'ecs.service.action',
    'ECS Deployment State Change': 'ecs.deployment.state_change',
}


def handler(event, context):
    detail = event.get('detail', {})
    detail_type = event.get('detail-type', '')
    event_name = EVENT_NAMES.get(detail_type, detail_type.lower().replace(' ', '.'))

    # Extract common ECS fields (safe defaults for events that lack them).
    task_arn = detail.get('taskArn', '')
    cluster = detail.get('clusterArn', '').split('/')[-1]
    service = detail.get('group', '').replace('service:', '')
    task_id = task_arn.split('/')[-1] if task_arn else ''
    status = detail.get('lastStatus', detail.get('eventName', ''))

    # Exit codes (only present on task state change with stopped containers).
    containers = detail.get('containers', [])
    exit_codes = {
        c['name']: str(c.get('exitCode', ''))
        for c in containers if 'exitCode' in c
    }
    primary_exit = next(
        (v for v in exit_codes.values() if v and v != '0'),
        next(iter(exit_codes.values()), '')
    )

    # Severity: ERROR for non-zero exit codes or failed deployments.
    is_error = (
        primary_exit not in ('', '0')
        or detail.get('eventName', '') in ('SERVICE_TASK_START_IMPAIRED',
                                           'SERVICE_DEPLOYMENT_FAILED')
        or status == 'FAILED'
    )

    # Timestamp: use stoppedAt, updatedAt, or now.
    ts_str = detail.get('stoppedAt', detail.get('updatedAt', ''))
    try:
        dt = datetime.fromisoformat(ts_str.replace('Z', '+00:00'))
        timestamp_ns = str(int(dt.timestamp() * 1e9))
    except Exception:
        timestamp_ns = str(int(time.time() * 1e9))

    # Build OTLP attributes — only include non-empty values.
    attrs = [kv('event.name', event_name)]
    if status:
        attrs.append(kv('aws.ecs.status', status))
    if detail.get('stopCode'):
        attrs.append(kv('aws.ecs.task.stop_code', detail['stopCode']))
    if detail.get('stoppedReason'):
        attrs.append(kv('aws.ecs.task.stopped_reason', detail['stoppedReason']))
    if exit_codes:
        attrs.append(kv('container.exit_codes', json.dumps(exit_codes)))
        attrs.append(kv('container.exit_code', primary_exit))
    if detail.get('eventName'):
        attrs.append(kv('aws.ecs.event_name', detail['eventName']))
    if detail.get('deploymentId'):
        attrs.append(kv('aws.ecs.deployment_id', detail['deploymentId']))

    payload = {
        'resourceLogs': [{
            'resource': {
                'attributes': [
                    kv('aws.ecs.task.arn', task_arn),
                    kv('aws.ecs.task.id', task_id),
                    kv('aws.ecs.cluster.name', cluster),
                    kv('service.name', service or 'ecs-lifecycle'),
                ]
            },
            'scopeLogs': [{
                'scope': {'name': 'ecs-eventbridge-forwarder', 'version': '0.2.0'},
                'logRecords': [{
                    'timeUnixNano': timestamp_ns,
                    'observedTimeUnixNano': str(int(time.time() * 1e9)),
                    'severityNumber': 17 if is_error else 9,
                    'severityText': 'ERROR' if is_error else 'INFO',
                    'body': {'stringValue': json.dumps(detail)},
                    'attributes': attrs,
                }]
            }]
        }]
    }

    data = json.dumps(payload).encode()
    req = urllib.request.Request(
        ENDPOINT, data=data,
        headers={'Content-Type': 'application/json', 'Authorization': f'Basic {AUTH}'},
    )
    try:
        with urllib.request.urlopen(req, timeout=8) as r:
            print(json.dumps({
                'status': r.status, 'event_name': event_name,
                'task_id': task_id, 'cluster': cluster, 'ecs_status': status,
            }))
            return r.status
    except urllib.error.HTTPError as e:
        body = e.read().decode()
        print(json.dumps({'error': e.code, 'event_name': event_name, 'body': body}))
        raise


def kv(key, val):
    return {'key': key, 'value': {'stringValue': str(val)}}


# ── Sample events for local testing ────────────────────────────────────────

SAMPLE_TASK_STOP_EVENT = {
    'source': 'aws.ecs',
    'detail-type': 'ECS Task State Change',
    'detail': {
        'taskArn': 'arn:aws:ecs:us-east-1:123456789012:task/prod-cluster/abc123def456',
        'clusterArn': 'arn:aws:ecs:us-east-1:123456789012:cluster/prod-cluster',
        'lastStatus': 'STOPPED',
        'desiredStatus': 'STOPPED',
        'group': 'service:my-api',
        'stopCode': 'EssentialContainerExited',
        'stoppedReason': 'Essential container in task exited',
        'stoppedAt': '2025-01-15T10:30:00Z',
        'containers': [
            {'name': 'app', 'lastStatus': 'STOPPED', 'exitCode': 137, 'reason': 'OOMKilled'},
            {'name': 'otel-collector', 'lastStatus': 'STOPPED', 'exitCode': 0},
        ],
    }
}

SAMPLE_SERVICE_ACTION_EVENT = {
    'source': 'aws.ecs',
    'detail-type': 'ECS Service Action',
    'detail': {
        'eventType': 'INFO',
        'eventName': 'SERVICE_STEADY_STATE',
        'clusterArn': 'arn:aws:ecs:us-east-1:123456789012:cluster/prod-cluster',
        'createdAt': '2025-01-15T10:35:00Z',
    }
}

SAMPLE_DEPLOYMENT_EVENT = {
    'source': 'aws.ecs',
    'detail-type': 'ECS Deployment State Change',
    'detail': {
        'eventType': 'INFO',
        'eventName': 'SERVICE_DEPLOYMENT_COMPLETED',
        'deploymentId': 'ecs-svc/1234567890123456789',
        'clusterArn': 'arn:aws:ecs:us-east-1:123456789012:cluster/prod-cluster',
        'updatedAt': '2025-01-15T10:40:00Z',
        'reason': 'ECS deployment ecs-svc/1234567890123456789 completed.',
    }
}

if __name__ == '__main__':
    print('--- Task Stop Event ---')
    handler(SAMPLE_TASK_STOP_EVENT, None)
    print('\n--- Service Action Event ---')
    handler(SAMPLE_SERVICE_ACTION_EVENT, None)
    print('\n--- Deployment Event ---')
    handler(SAMPLE_DEPLOYMENT_EVENT, None)
