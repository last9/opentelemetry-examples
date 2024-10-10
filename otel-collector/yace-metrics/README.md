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
          - ".*"  # Include all metrics

  attributes:
    actions:
      - key: scraper
        value: "yace"
        action: insert

exporters:
  otlp/last9:
    endpoint: "Use Metrics TSDB endpoint from Integration page"
    headers:
      "Authorization": "Use Base64 component of username/password as Auth header details"
    timeout: 30s
    retry_on_failure:
      enabled: true
      initial_interval: 5s
      max_interval: 30s
      max_elapsed_time: 300s

  debug:
    verbosity: detailed

service:
  pipelines:
    metrics:
      receivers: [prometheus]
      processors: [filter, attributes]
      exporters: [logging, otlp/last9]
```

### YACE Configuration

Create a file named `yace_config.yml` with the following content:

```yaml
apiVersion: v1alpha1
discovery:
  exportedTagsOnMetrics:
    # EC2/EBS
    AWS/EC2:
      - instance-id
      - Name
    AWS/ApplicationELB:
      - LoadBalancer
      - TargetGroup
    AWS/NetworkELB:
      - LoadBalancer
      - TargetGroup

  jobs:
    - type: AWS/EC2
      regions:
        - ap-south-1  # Adjust this to your specific region
      period: 300
      length: 300
      metrics:
        - name: CPUUtilization
          statistics: [Average, Maximum, Minimum]
        - name: DiskReadOps
          statistics: [Sum]
        - name: DiskWriteOps
          statistics: [Sum]
        - name: DiskReadBytes
          statistics: [Sum]
        - name: DiskWriteBytes
          statistics: [Sum]
        - name: NetworkIn
          statistics: [Sum]
        - name: NetworkOut
          statistics: [Sum]
        - name: StatusCheckFailed
          statistics: [Sum]
        # Add more EC2 metrics as needed

    - type: AWS/ELB  # Classic Load Balancer
      regions:
        - ap-south-1  # Adjust this to your specific region
      period: 300
      length: 300
      metrics:
        - name: RequestCount
          statistics: [Sum]
        - name: HealthyHostCount
          statistics: [Average]
        - name: UnHealthyHostCount
          statistics: [Average]
        - name: Latency
          statistics: [Average]
        - name: HTTPCode_Backend_2XX
          statistics: [Sum]
        - name: HTTPCode_Backend_4XX
          statistics: [Sum]
        - name: HTTPCode_Backend_5XX
          statistics: [Sum]
        # Add more ELB metrics as needed

    - type: AWS/ApplicationELB  # Application Load Balancer
      regions:
        - ap-south-1  # Adjust this to your specific region
      period: 300
      length: 300
      metrics:
        - name: RequestCount
          statistics: [Sum]
        - name: TargetResponseTime
          statistics: [Average]
        - name: HealthyHostCount
          statistics: [Average]
        - name: UnHealthyHostCount
          statistics: [Average]
        - name: HTTPCode_Target_2XX_Count
          statistics: [Sum]
        - name: HTTPCode_Target_4XX_Count
          statistics: [Sum]
        - name: HTTPCode_Target_5XX_Count
          statistics: [Sum]
        # Add more ALB metrics as needed

    - type: AWS/NetworkELB  # Network Load Balancer
      regions:
        - ap-south-1  # Adjust this to your specific region
      period: 300
      length: 300
      metrics:
        - name: ActiveFlowCount
          statistics: [Average]
        - name: ConsumedLCUs
          statistics: [Sum]
        - name: HealthyHostCount
          statistics: [Average]
        - name: UnHealthyHostCount
          statistics: [Average]
        - name: ProcessedBytes
          statistics: [Sum]
        # Add more NLB metrics as needed
```

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

This will push the metrics from YACE config to be sent to Levitate. To see the data in action, visit the [Grafana Dashboard](https://app.last9.io/).

## Troubleshooting

If you have any questions or issues, please contact us on Discord or via Email.
