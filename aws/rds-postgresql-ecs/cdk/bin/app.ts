#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { PostgreSQLCollectorStack } from '../lib/postgresql-collector-stack';

const app = new cdk.App();

// Get configuration from context or environment
const environment = app.node.tryGetContext('environment') || process.env.ENVIRONMENT || 'dev';
const vpcId = app.node.tryGetContext('vpcId') || process.env.VPC_ID;
const last9OtlpEndpoint = app.node.tryGetContext('last9OtlpEndpoint') || process.env.LAST9_OTLP_ENDPOINT;
const rdsInstanceId = app.node.tryGetContext('rdsInstanceId') || process.env.RDS_INSTANCE_ID;
const dbCredentialsSecretArn = app.node.tryGetContext('dbCredentialsSecretArn') || process.env.DB_CREDENTIALS_SECRET_ARN;

// Validate required parameters
if (!vpcId) {
  console.error('ERROR: vpcId is required. Provide via context (-c vpcId=vpc-xxx) or VPC_ID env var');
  process.exit(1);
}

if (!last9OtlpEndpoint) {
  console.error('ERROR: last9OtlpEndpoint is required. Provide via context or LAST9_OTLP_ENDPOINT env var');
  process.exit(1);
}

if (!rdsInstanceId) {
  console.error('ERROR: rdsInstanceId is required. Provide via context or RDS_INSTANCE_ID env var');
  process.exit(1);
}

new PostgreSQLCollectorStack(app, `PostgreSQLCollector-${environment}`, {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION || 'us-east-1',
  },
  vpcId,
  environment,
  last9OtlpEndpoint,
  rdsInstanceId,
  dbCredentialsSecretArn,
  description: `PostgreSQL Collector for Last9 Integration - ${environment}`,
  tags: {
    Environment: environment,
    Service: 'postgresql-collector',
    ManagedBy: 'CDK',
  },
});

app.synth();
