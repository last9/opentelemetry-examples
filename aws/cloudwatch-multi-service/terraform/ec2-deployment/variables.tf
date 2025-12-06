variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-east-1"
}

variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
  default     = "last9-otel"
}

variable "vpc_id" {
  description = "VPC ID where EC2 instance will be created. Leave empty to use default VPC"
  type        = string
  default     = ""
}

variable "subnet_id" {
  description = "Subnet ID where EC2 instance will be created. Leave empty to use first available subnet"
  type        = string
  default     = ""
}

variable "instance_type" {
  description = "EC2 instance type for OTEL Collector"
  type        = string
  default     = "t3.small"

  validation {
    condition     = can(regex("^t3\\.", var.instance_type)) || can(regex("^t4g\\.", var.instance_type))
    error_message = "Instance type must be t3 or t4g family for cost efficiency"
  }
}

variable "root_volume_size" {
  description = "Size of root volume in GB"
  type        = number
  default     = 20
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to send telemetry to OTEL Collector"
  type        = list(string)
  default     = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]  # Private subnets
}

variable "enable_ssh_access" {
  description = "Enable SSH access to EC2 instance"
  type        = bool
  default     = false
}

variable "ssh_cidr_blocks" {
  description = "CIDR blocks allowed for SSH access"
  type        = list(string)
  default     = []
}

# Last9 Configuration
variable "last9_otlp_endpoint" {
  description = "Last9 OTLP endpoint URL (e.g., https://otlp.last9.io:443)"
  type        = string
  sensitive   = true
}

variable "last9_auth_header" {
  description = "Last9 authentication header (Basic <base64-encoded-credentials>)"
  type        = string
  sensitive   = true
}

# OTEL Collector Configuration
variable "otel_collector_version" {
  description = "OpenTelemetry Collector Contrib version"
  type        = string
  default     = "0.118.0"
}

variable "otel_service_name" {
  description = "Service name for OTEL Collector"
  type        = string
  default     = "aws-cloudwatch-collector"
}

variable "otel_resource_attributes" {
  description = "Additional resource attributes for OTEL Collector"
  type        = string
  default     = "deployment.environment=production,team=platform"
}

# CloudWatch Configuration
variable "cloudwatch_log_group_prefix" {
  description = "Prefix for CloudWatch log group autodiscovery (e.g., /aws/)"
  type        = string
  default     = "/aws/"
}

variable "cloudwatch_log_group_names" {
  description = "List of specific CloudWatch log group names to collect"
  type        = list(string)
  default = [
    "/aws/connect/aha_prod",
    "/aws/lambda/aha_prod_auth_handler",
    "/aws/lambda/aha_prod_data_processor",
    "/aws/lex/aha_prod_main_bot",
    "/aws/apigateway/aha_prod_api"
  ]
}

# Monitoring Configuration
variable "enable_cloudwatch_alarms" {
  description = "Enable CloudWatch alarms for EC2 instance"
  type        = bool
  default     = true
}

variable "alarm_sns_topic_arn" {
  description = "SNS topic ARN for CloudWatch alarms"
  type        = string
  default     = ""
}

# Tags
variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    ManagedBy   = "Terraform"
    Purpose     = "Last9-OTEL-Collector"
    Environment = "production"
  }
}
