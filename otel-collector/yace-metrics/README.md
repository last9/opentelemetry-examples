# Installing YACE Exporter to Scrape AWS Cloudwatch Metrics

This guide explains how to use Levitate's OpenTelemetry metrics endpoint to ingest metrics from AWS Cloudwatch using YACE Exporter and OpenTelemetry Collector.

## Prerequisites

1. Install OpenTelemetry Collector
2. Create an AWS IAM user
3. Add the required IAM role to the user
4. Create access keys (or use AssumeRole in YACE config)
5. Install Docker
6. Install AWS CLI

## Installation Steps

### 1. Install OpenTelemetry Collector

Tested on Ubuntu 22.04 (LTS):

```bash
sudo apt-get update
sudo apt-get -y install wget systemctl
wget https://github.com/open-telemetry/opentelemetry-collector-releases/releases/download/v0.128.0/otelcol-contrib_0.128.0_linux_amd64.deb
sudo dpkg -i otelcol-contrib_0.128.0_linux_amd64.deb
```

For more installation options, refer to the [official documentation](https://opentelemetry.io/docs/collector/installation/).

### 2. Create AWS IAM User and Role

Create an AWS IAM user and add the following IAM role:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "tag:GetResources",
        "cloudwatch:GetMetricData",
        "cloudwatch:GetMetricStatistics",
        "cloudwatch:ListMetrics",
        "apigateway:GET",
        "aps:ListWorkspaces",
        "autoscaling:DescribeAutoScalingGroups",
        "dms:DescribeReplicationInstances",
        "dms:DescribeReplicationTasks",
        "ec2:DescribeTransitGatewayAttachments",
        "ec2:DescribeSpotFleetRequests",
        "shield:ListProtections",
        "storagegateway:ListGateways",
        "storagegateway:ListTagsForResource",
        "iam:ListAccountAliases"
      ],
      "Effect": "Allow",
      "Resource": "*"
    }
  ]
}
```

### 3. Install Docker

```bash
# Add Docker's official GPG key
sudo apt-get update
sudo apt-get install ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Add the repository to Apt sources
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Verify installation
sudo docker run hello-world
```

For more Docker installation options, see the [official Docker documentation](https://docs.docker.com/engine/install/).

### 4. Install AWS CLI

```bash
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
```

For more AWS CLI installation options, check the [AWS CLI documentation](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html).

## Configuration

### OpenTelemetry Collector Configuration

Edit the configuration file at `/etc/otelcol-contrib/config.yaml` with `otel-config.yaml` file.

### YACE Configuration

Create a file named `yace_config.yml` with the content from `yace_config.yaml`.

For more YACE configuration options, see the [YACE documentation](https://github.com/nerdswords/yet-another-cloudwatch-exporter).

## Running the Services

1. Run YACE using Docker:

```bash
sudo docker run --rm \
  -v $PWD/yace_config.yml:/tmp/config.yml \
  -e AWS_ACCESS_KEY_ID="ACCESS_KEY_ID" \
  -e AWS_SECRET_ACCESS_KEY="SECRET_ACCESS_KEY" \
  -e AWS_DEFAULT_REGION=ap-south-1 \
  -p 5000:5000 \
  --name yace \
  ghcr.io/nerdswords/yet-another-cloudwatch-exporter:v0.61.2
```

2. Verify metrics are being collected:

```bash
curl http://localhost:5000/metrics
```

3. Run the OpenTelemetry Collector:

```bash
otelcol-contrib --config /etc/otelcol-contrib/config.yaml
```

## Verifying Metrics

This will push the metrics from YACE config to be sent to Levitate. To see the data in action, visit the [Last9](https://app.last9.io/).

## Troubleshooting

If you have any questions or issues, please contact us on Discord or via Email.
