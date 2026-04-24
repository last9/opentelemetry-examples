#!/bin/bash
# Creates a demo SQS queue in LocalStack for local testing
awslocal sqs create-queue --queue-name demo-queue
