# VPC Lattice Outputs
output "service_network_id" {
  description = "ID of the VPC Lattice service network"
  value       = aws_vpclattice_service_network.main.id
}

output "service_network_arn" {
  description = "ARN of the VPC Lattice service network"
  value       = aws_vpclattice_service_network.main.arn
}

output "service_network_name" {
  description = "Name of the VPC Lattice service network"
  value       = aws_vpclattice_service_network.main.name
}

# EventBridge Outputs
output "event_bus_name" {
  description = "Name of the custom EventBridge bus"
  value       = aws_cloudwatch_event_bus.service_lifecycle.name
}

output "event_bus_arn" {
  description = "ARN of the custom EventBridge bus"
  value       = aws_cloudwatch_event_bus.service_lifecycle.arn
}

# Lambda Function Outputs
output "health_monitor_function_name" {
  description = "Name of the health monitor Lambda function"
  value       = aws_lambda_function.health_monitor.function_name
}

output "health_monitor_function_arn" {
  description = "ARN of the health monitor Lambda function"
  value       = aws_lambda_function.health_monitor.arn
}

output "auto_scaler_function_name" {
  description = "Name of the auto scaler Lambda function"
  value       = aws_lambda_function.auto_scaler.function_name
}

output "auto_scaler_function_arn" {
  description = "ARN of the auto scaler Lambda function"
  value       = aws_lambda_function.auto_scaler.arn
}

# IAM Role Outputs
output "lambda_role_name" {
  description = "Name of the Lambda execution role"
  value       = aws_iam_role.lambda_role.name
}

output "lambda_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_role.arn
}

# CloudWatch Outputs
output "vpc_lattice_log_group_name" {
  description = "Name of the VPC Lattice CloudWatch log group"
  value       = aws_cloudwatch_log_group.vpc_lattice_logs.name
}

output "vpc_lattice_log_group_arn" {
  description = "ARN of the VPC Lattice CloudWatch log group"
  value       = aws_cloudwatch_log_group.vpc_lattice_logs.arn
}

output "health_monitor_log_group_name" {
  description = "Name of the health monitor Lambda CloudWatch log group"
  value       = aws_cloudwatch_log_group.health_monitor_logs.name
}

output "auto_scaler_log_group_name" {
  description = "Name of the auto scaler Lambda CloudWatch log group"
  value       = aws_cloudwatch_log_group.auto_scaler_logs.name
}

# EventBridge Rules Outputs
output "health_monitoring_rule_name" {
  description = "Name of the health monitoring EventBridge rule"
  value       = aws_cloudwatch_event_rule.health_monitoring.name
}

output "health_monitoring_rule_arn" {
  description = "ARN of the health monitoring EventBridge rule"
  value       = aws_cloudwatch_event_rule.health_monitoring.arn
}

output "scheduled_health_check_rule_name" {
  description = "Name of the scheduled health check CloudWatch Events rule"
  value       = aws_cloudwatch_event_rule.scheduled_health_check.name
}

output "scheduled_health_check_rule_arn" {
  description = "ARN of the scheduled health check CloudWatch Events rule"
  value       = aws_cloudwatch_event_rule.scheduled_health_check.arn
}

# CloudWatch Dashboard Output
output "dashboard_url" {
  description = "URL to the CloudWatch dashboard (if enabled)"
  value = var.enable_dashboard ? "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.service_lifecycle[0].dashboard_name}" : null
}

# Configuration Outputs
output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = local.random_suffix
}

output "project_name" {
  description = "Project name used for resource naming"
  value       = var.project_name
}

output "environment" {
  description = "Environment name"
  value       = var.environment
}

# Quick Start Information
output "quick_start_commands" {
  description = "Commands to get started with the deployed infrastructure"
  value = {
    "check_service_network" = "aws vpc-lattice get-service-network --service-network-identifier ${aws_vpclattice_service_network.main.id}"
    "list_event_rules"      = "aws events list-rules --event-bus-name ${aws_cloudwatch_event_bus.service_lifecycle.name}"
    "test_health_monitor"   = "aws lambda invoke --function-name ${aws_lambda_function.health_monitor.function_name} --payload '{}' /tmp/response.json && cat /tmp/response.json"
    "view_logs"            = "aws logs filter-log-events --log-group-name ${aws_cloudwatch_log_group.health_monitor_logs.name} --start-time $(date -d '5 minutes ago' +%s)000"
  }
}