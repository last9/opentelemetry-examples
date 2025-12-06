terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Data sources for existing resources
data "aws_vpc" "selected" {
  id = var.vpc_id != "" ? var.vpc_id : null

  default = var.vpc_id == "" ? true : false
}

data "aws_subnets" "selected" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.selected.id]
  }
}

data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# IAM role for EC2 instance
resource "aws_iam_role" "otel_collector" {
  name = "${var.name_prefix}-otel-collector-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-otel-collector-role"
  })
}

# IAM policy for CloudWatch Logs access
resource "aws_iam_role_policy" "cloudwatch_logs" {
  name = "${var.name_prefix}-cloudwatch-logs-policy"
  role = aws_iam_role.otel_collector.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CloudWatchLogsAccess"
        Effect = "Allow"
        Action = [
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams",
          "logs:FilterLogEvents",
          "logs:GetLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

# Attach SSM policy for remote management (optional but recommended)
resource "aws_iam_role_policy_attachment" "ssm_policy" {
  role       = aws_iam_role.otel_collector.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# IAM instance profile
resource "aws_iam_instance_profile" "otel_collector" {
  name = "${var.name_prefix}-otel-collector-profile"
  role = aws_iam_role.otel_collector.name

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-otel-collector-profile"
  })
}

# Security group for OTEL Collector
resource "aws_security_group" "otel_collector" {
  name        = "${var.name_prefix}-otel-collector-sg"
  description = "Security group for OpenTelemetry Collector EC2 instance"
  vpc_id      = data.aws_vpc.selected.id

  # OTLP gRPC receiver (for application instrumentation)
  ingress {
    description = "OTLP gRPC"
    from_port   = 4317
    to_port     = 4317
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  # OTLP HTTP receiver (for application instrumentation)
  ingress {
    description = "OTLP HTTP"
    from_port   = 4318
    to_port     = 4318
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  # Health check endpoint
  ingress {
    description = "Health Check"
    from_port   = 13133
    to_port     = 13133
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  # SSH access (optional, for debugging)
  dynamic "ingress" {
    for_each = var.enable_ssh_access ? [1] : []
    content {
      description = "SSH"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = var.ssh_cidr_blocks
    }
  }

  # Allow all outbound traffic (required for Last9 OTLP endpoint)
  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-otel-collector-sg"
  })
}

# User data script for OTEL Collector installation
locals {
  user_data = templatefile("${path.module}/user-data.sh.tpl", {
    otel_version         = var.otel_collector_version
    last9_otlp_endpoint  = var.last9_otlp_endpoint
    last9_auth_header    = var.last9_auth_header
    aws_region           = var.aws_region
    service_name         = var.otel_service_name
    resource_attributes  = var.otel_resource_attributes
    log_group_prefix     = var.cloudwatch_log_group_prefix
    log_group_names      = jsonencode(var.cloudwatch_log_group_names)
  })
}

# EC2 instance for OTEL Collector
resource "aws_instance" "otel_collector" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id != "" ? var.subnet_id : data.aws_subnets.selected.ids[0]
  vpc_security_group_ids = [aws_security_group.otel_collector.id]
  iam_instance_profile   = aws_iam_instance_profile.otel_collector.name

  user_data = local.user_data

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size
    encrypted             = true
    delete_on_termination = true
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"  # IMDSv2
    http_put_response_hop_limit = 1
  }

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-otel-collector"
  })

  lifecycle {
    ignore_changes = [ami]
  }
}

# CloudWatch alarm for instance status checks
resource "aws_cloudwatch_metric_alarm" "instance_status_check" {
  count = var.enable_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${var.name_prefix}-otel-collector-status-check"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "StatusCheckFailed"
  namespace           = "AWS/EC2"
  period              = "60"
  statistic           = "Average"
  threshold           = "0"
  alarm_description   = "This alarm monitors EC2 instance status checks"
  alarm_actions       = var.alarm_sns_topic_arn != "" ? [var.alarm_sns_topic_arn] : []

  dimensions = {
    InstanceId = aws_instance.otel_collector.id
  }

  tags = var.tags
}

# CloudWatch alarm for CPU utilization
resource "aws_cloudwatch_metric_alarm" "cpu_utilization" {
  count = var.enable_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${var.name_prefix}-otel-collector-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This alarm monitors EC2 CPU utilization"
  alarm_actions       = var.alarm_sns_topic_arn != "" ? [var.alarm_sns_topic_arn] : []

  dimensions = {
    InstanceId = aws_instance.otel_collector.id
  }

  tags = var.tags
}
