# Installing YACE Exporter to Scrape AWS Cloudwatch Metrics for AWS EC2 Instances

This guide explains how to use Levitate's OpenTelemetry metrics endpoint to ingest metrics from AWS Cloudwatch using the OpenTelemetry Collector.

## Prerequisites

1. Install OpenTelemetry Collector
2. Create an AWS IAM user
3. Add the required IAM role to the user
4. Create access keys
5. Create an EC2 instance
6. Enable managed monitoring for your EC2 instance

## Installation Steps

### 1. Install OpenTelemetry Collector

Tested on Ubuntu 22.04 (LTS):

```bash
sudo apt-get update
sudo apt-get -y install wget systemctl
wget https://github.com/open-telemetry/opentelemetry-collector-releases/releases/download/v0.110.0/otelcol-contrib_0.110.0_linux_amd64.deb
sudo dpkg -i otelcol-contrib_0.110.0_linux_amd64.deb
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

Edit the configuration file at `/etc/otelcol-contrib/config.yaml`:

```yaml
receivers:
  prometheus:
    config:
      scrape_configs:
        - job_name: 'yace'
          scrape_interval: 10s
          static_configs:
            - targets: ['localhost:5000']

processors:
  filter:
    metrics:
      include:
        match_type: regexp
        metric_names:
          - "aws_ec2_.*"
          - "yace_.*"

  metricstransform:
    transforms:
      - include: aws_ec2_cpuutilization_average
        action: update
        new_name: aws.ec2.cpu.utilization
      - include: aws_ec2_network_in_sum
        action: update
        new_name: aws.ec2.network.in.bytes
      - include: aws_ec2_network_out_sum
        action: update
        new_name: aws.ec2.network.out.bytes
      # Add more transformations as needed

  attributes:
    actions:
      - key: metric_type
        value: "aws_ec2"
        action: insert
      - key: cloud.provider
        value: "aws"
        action: insert
      - key: cloud.platform
        value: "ec2"
        action: insert

exporters:
  prometheusremotewrite:
    endpoint: "Use Metrics TSDB endpoint from Integration page"
    headers:
      "Authorization": "Use Base64 component of username/password as Auth header details"
    timeout: 30s
    retry_on_failure:
      enabled: true
      initial_interval: 5s
      max_interval: 30s
      max_elapsed_time: 300s

  logging:
    loglevel: debug

service:
  pipelines:
    metrics:
      receivers: [prometheus]
      processors: [filter, metricstransform, attributes]
      exporters: [logging, prometheusremotewrite]
```

### YACE Configuration for EC2

Create a file named `ec2config.yml` with the following content:

```yaml
apiVersion: v1alpha1
discovery:
  jobs:
    - type: AWS/EC2
      regions:
        - ap-south-1
      period: 300
      length: 300
      metrics:
        - name: CPUUtilization
          statistics: [Average]
        - name: NetworkIn
          statistics: [Average, Sum]
        - name: NetworkOut
          statistics: [Average, Sum]
        - name: NetworkPacketsIn
          statistics: [Sum]
        - name: NetworkPacketsOut
          statistics: [Sum]
        - name: DiskReadBytes
          statistics: [Sum]
        - name: DiskWriteBytes
          statistics: [Sum]
        - name: DiskReadOps
          statistics: [Sum]
        - name: DiskWriteOps
          statistics: [Sum]
        - name: StatusCheckFailed
          statistics: [Sum]
        - name: StatusCheckFailed_Instance
          statistics: [Sum]
        - name: StatusCheckFailed_System
          statistics: [Sum]
```

For more YACE configuration options, see the [YACE documentation](https://github.com/nerdswords/yet-another-cloudwatch-exporter).

## Running the Services

1. Run YACE using Docker:

```bash
sudo docker run --rm \
  -v $PWD/ec2config.yml:/tmp/config.yml \
  -e AWS_ACCESS_KEY_ID="ACCESS_KEY_ID" \
  -e AWS_SECRET_ACCESS_KEY="SECRET_ACCESS_KEY" \
  -e AWS_DEFAULT_REGION=ap-south-1 \
  -p 5000:5000 \
  --name yace \
  ghcr.io/nerdswords/yet-another-cloudwatch-exporter:v0.61.2
```

2. Verify metrics are being collected:

```bash
curl https://localhost:5000/metrics
```

3. Run the OpenTelemetry Collector:

```bash
otelcol-contrib --config /etc/otelcol-contrib/config.yaml
```

## Verifying Metrics

1. Go to the Last9(Levitate) dashboard
2. Explore the Managed Grafana dashboard with the cluster selected from the integrations page
3. Check if the metrics are being populated
4. Query the metrics to see the output

## Troubleshooting

If you have any questions or issues, please contact us on Discord or via Email.
