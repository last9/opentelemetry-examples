output "instance_id" {
  description = "ID of the EC2 instance running OTEL Collector"
  value       = aws_instance.otel_collector.id
}

output "instance_private_ip" {
  description = "Private IP address of the EC2 instance"
  value       = aws_instance.otel_collector.private_ip
}

output "instance_public_ip" {
  description = "Public IP address of the EC2 instance (if available)"
  value       = aws_instance.otel_collector.public_ip
}

output "iam_role_arn" {
  description = "ARN of the IAM role attached to the EC2 instance"
  value       = aws_iam_role.otel_collector.arn
}

output "iam_role_name" {
  description = "Name of the IAM role attached to the EC2 instance"
  value       = aws_iam_role.otel_collector.name
}

output "security_group_id" {
  description = "ID of the security group attached to the EC2 instance"
  value       = aws_security_group.otel_collector.id
}

output "otlp_grpc_endpoint" {
  description = "OTLP gRPC endpoint URL (for application instrumentation)"
  value       = "http://${aws_instance.otel_collector.private_ip}:4317"
}

output "otlp_http_endpoint" {
  description = "OTLP HTTP endpoint URL (for application instrumentation)"
  value       = "http://${aws_instance.otel_collector.private_ip}:4318"
}

output "health_check_endpoint" {
  description = "Health check endpoint URL"
  value       = "http://${aws_instance.otel_collector.private_ip}:13133"
}

output "ssm_session_command" {
  description = "AWS CLI command to start SSM session to the instance"
  value       = "aws ssm start-session --target ${aws_instance.otel_collector.id} --region ${var.aws_region}"
}

output "view_logs_command" {
  description = "Command to view OTEL Collector logs via SSM"
  value       = "aws ssm start-session --target ${aws_instance.otel_collector.id} --region ${var.aws_region} --document-name AWS-StartInteractiveCommand --parameters command='sudo journalctl -u otelcol-contrib -f'"
}
