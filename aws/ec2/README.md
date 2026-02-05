# EC2 OpenTelemetry Collector - Automated Deployment

Automate OpenTelemetry Collector deployment across multiple EC2 instances using AWS Systems Manager.

## Files

### ssm-document-otel-install.yaml
AWS Systems Manager Document for installing OTEL Collector on EC2 instances.

**Features:**
- Auto-detects OS (Debian/Ubuntu vs RHEL/Amazon Linux)
- Installs appropriate package (.deb or .rpm)
- Configures OTEL with Last9 endpoints
- Validates and starts the service

**Usage:**
```bash
# Create SSM document
aws ssm create-document \
  --name "Last9-OTEL-Install" \
  --document-type "Command" \
  --document-format YAML \
  --content file://ssm-document-otel-install.yaml

# Deploy to instances
aws ssm send-command \
  --document-name "Last9-OTEL-Install" \
  --targets "Key=tag:Environment,Values=production" \
  --parameters "LogsURL=YOUR_LAST9_ENDPOINT,AuthValue=Basic xyz"
```

### cloudformation-otel-auto-install.yaml
CloudFormation stack for tag-based auto-installation of OTEL Collector.

**Features:**
- Tag any instance with `Last9-OTEL=Install` → auto-installs
- Perfect for auto-scaling groups
- Stores credentials in Secrets Manager
- Uses EventBridge + SSM Automation

**Usage:**
```bash
# Deploy stack once
aws cloudformation create-stack \
  --stack-name last9-otel-auto-install \
  --template-body file://cloudformation-otel-auto-install.yaml \
  --parameters \
    ParameterKey=Last9LogsURL,ParameterValue=YOUR_LAST9_ENDPOINT \
    ParameterKey=Last9AuthValue,ParameterValue="Basic xyz" \
  --capabilities CAPABILITY_NAMED_IAM

# Then tag instances to auto-install
aws ec2 create-tags \
  --resources i-xxxxx \
  --tags Key=Last9-OTEL,Value=Install
```

## Documentation

Full documentation: [EC2 Automated Deployment Guide](https://github.com/last9/product-integrations/blob/master/otel-collector-ec2-automated.md)

## Prerequisites

1. EC2 instances with IAM role including `AmazonSSMManagedInstanceCore` policy
2. SSM Agent running on instances (pre-installed on most AWS AMIs)
3. Last9 OTLP endpoint and authorization credentials
