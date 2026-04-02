"""
ECS EventBridge → Last9 OTLP logs forwarder.

Standalone copy of the Lambda handler for local testing and reference.
The same code is inlined in cloudformation.yaml under ZipFile.

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
from datetime import datetime, timezone

ENDPOINT = os.environ['LAST9_OTLP_ENDPOINT']
AUTH = os.environ['LAST9_AUTH']


def handler(event, context):
    detail = event.get('detail', {})
    task_arn = detail.get('taskArn', '')
    cluster = detail.get('clusterArn', '').split('/')[-1]
    service = detail.get('group', '').replace('service:', '')

    task_id = task_arn.split('/')[-1] if task_arn else ''

    containers = detail.get('containers', [])
    exit_codes = {
        c['name']: str(c.get('exitCode', ''))
        for c in containers
        if 'exitCode' in c
    }
    primary_exit = next(
        (v for v in exit_codes.values() if v and v != '0'),
        next(iter(exit_codes.values()), '')
    )
    is_error = primary_exit not in ('', '0')

    stopped_at_str = detail.get('stoppedAt', '')
    try:
        dt = datetime.fromisoformat(stopped_at_str.replace('Z', '+00:00'))
        timestamp_ns = str(int(dt.timestamp() * 1e9))
    except Exception:
        timestamp_ns = str(int(time.time() * 1e9))

    payload = {
        'resourceLogs': [{
            'resource': {
                'attributes': [
                    kv('aws.ecs.task.arn', task_arn),
                    kv('aws.ecs.task.id', task_id),
                    kv('aws.ecs.cluster.name', cluster),
                    kv('service.name', service),
                ]
            },
            'scopeLogs': [{
                'scope': {
                    'name': 'ecs-eventbridge-forwarder',
                    'version': '0.1.0',
                },
                'logRecords': [{
                    'timeUnixNano': timestamp_ns,
                    'observedTimeUnixNano': str(int(time.time() * 1e9)),
                    'severityNumber': 17 if is_error else 9,
                    'severityText': 'ERROR' if is_error else 'INFO',
                    'body': {'stringValue': json.dumps(detail)},
                    'attributes': [
                        kv('event.name', 'ecs.task.stopped'),
                        kv('aws.ecs.task.stop_code', detail.get('stopCode', '')),
                        kv('aws.ecs.task.stopped_reason', detail.get('stoppedReason', '')),
                        kv('container.exit_codes', json.dumps(exit_codes)),
                        kv('container.exit_code', primary_exit),
                    ]
                }]
            }]
        }]
    }

    data = json.dumps(payload).encode()
    req = urllib.request.Request(
        ENDPOINT,
        data=data,
        headers={
            'Content-Type': 'application/json',
            'Authorization': f'Basic {AUTH}',
        }
    )
    try:
        with urllib.request.urlopen(req, timeout=8) as r:
            print(json.dumps({
                'status': r.status,
                'task_id': task_id,
                'cluster': cluster,
                'stop_code': detail.get('stopCode'),
                'exit_code': primary_exit,
            }))
            return r.status
    except urllib.error.HTTPError as e:
        body = e.read().decode()
        print(json.dumps({'error': e.code, 'task_id': task_id, 'body': body}))
        raise


def kv(key, val):
    return {'key': key, 'value': {'stringValue': str(val)}}


# ── Local test ────────────────────────────────────────────────────────────────

SAMPLE_EVENT = {
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
            {
                'name': 'app',
                'lastStatus': 'STOPPED',
                'exitCode': 137,
                'reason': 'OOMKilled',
            },
            {
                'name': 'otel-collector',
                'lastStatus': 'STOPPED',
                'exitCode': 0,
            },
        ],
    }
}

if __name__ == '__main__':
    handler(SAMPLE_EVENT, None)
