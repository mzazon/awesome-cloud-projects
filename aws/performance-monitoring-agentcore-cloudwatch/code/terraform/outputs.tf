# Output values for the AgentCore Performance Monitoring infrastructure
# These outputs provide important resource information for integration and verification

# S3 Bucket Outputs
output "s3_bucket_name" {
  description = "Name of the S3 bucket for storing performance reports"
  value       = aws_s3_bucket.monitoring_data.id
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket for storing performance reports"
  value       = aws_s3_bucket.monitoring_data.arn
}

output "s3_bucket_domain_name" {
  description = "Domain name of the S3 bucket"
  value       = aws_s3_bucket.monitoring_data.bucket_domain_name
}

# IAM Role Outputs
output "agentcore_role_arn" {
  description = "ARN of the IAM role for AgentCore observability"
  value       = aws_iam_role.agentcore_monitoring.arn
}

output "agentcore_role_name" {
  description = "Name of the IAM role for AgentCore observability"
  value       = aws_iam_role.agentcore_monitoring.name
}

output "lambda_role_arn" {
  description = "ARN of the IAM role for Lambda performance monitor"
  value       = aws_iam_role.lambda_performance_monitor.arn
}

output "lambda_role_name" {
  description = "Name of the IAM role for Lambda performance monitor"
  value       = aws_iam_role.lambda_performance_monitor.name
}

# Lambda Function Outputs
output "lambda_function_name" {
  description = "Name of the Lambda performance monitoring function"
  value       = aws_lambda_function.performance_monitor.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda performance monitoring function"
  value       = aws_lambda_function.performance_monitor.arn
}

output "lambda_function_invoke_arn" {
  description = "Invoke ARN of the Lambda performance monitoring function"
  value       = aws_lambda_function.performance_monitor.invoke_arn
}

# CloudWatch Log Groups Outputs
output "agentcore_log_group_name" {
  description = "Name of the AgentCore CloudWatch log group"
  value       = aws_cloudwatch_log_group.agentcore.name
}

output "agentcore_log_group_arn" {
  description = "ARN of the AgentCore CloudWatch log group"
  value       = aws_cloudwatch_log_group.agentcore.arn
}

output "lambda_log_group_name" {
  description = "Name of the Lambda CloudWatch log group"
  value       = aws_cloudwatch_log_group.lambda.name
}

output "lambda_log_group_arn" {
  description = "ARN of the Lambda CloudWatch log group"
  value       = aws_cloudwatch_log_group.lambda.arn
}

output "memory_log_group_name" {
  description = "Name of the AgentCore Memory CloudWatch log group"
  value       = aws_cloudwatch_log_group.agentcore_memory.name
}

output "gateway_log_group_name" {
  description = "Name of the AgentCore Gateway CloudWatch log group"
  value       = aws_cloudwatch_log_group.agentcore_gateway.name
}

# CloudWatch Alarms Outputs
output "high_latency_alarm_name" {
  description = "Name of the high latency CloudWatch alarm"
  value       = aws_cloudwatch_metric_alarm.high_latency.alarm_name
}

output "high_latency_alarm_arn" {
  description = "ARN of the high latency CloudWatch alarm"
  value       = aws_cloudwatch_metric_alarm.high_latency.arn
}

output "high_system_errors_alarm_name" {
  description = "Name of the high system errors CloudWatch alarm"
  value       = aws_cloudwatch_metric_alarm.high_system_errors.alarm_name
}

output "high_system_errors_alarm_arn" {
  description = "ARN of the high system errors CloudWatch alarm"
  value       = aws_cloudwatch_metric_alarm.high_system_errors.arn
}

output "high_throttles_alarm_name" {
  description = "Name of the high throttles CloudWatch alarm"
  value       = aws_cloudwatch_metric_alarm.high_throttles.alarm_name
}

output "high_throttles_alarm_arn" {
  description = "ARN of the high throttles CloudWatch alarm"
  value       = aws_cloudwatch_metric_alarm.high_throttles.arn
}

# CloudWatch Dashboard Outputs
output "dashboard_name" {
  description = "Name of the CloudWatch dashboard"
  value       = var.create_dashboard ? aws_cloudwatch_dashboard.agentcore_performance[0].dashboard_name : null
}

output "dashboard_url" {
  description = "URL of the CloudWatch dashboard"
  value = var.create_dashboard ? "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.agentcore_performance[0].dashboard_name}" : null
}

# Metric Filters Outputs
output "response_time_metric_filter_name" {
  description = "Name of the agent response time metric filter"
  value       = aws_cloudwatch_log_metric_filter.agent_response_time.name
}

output "quality_score_metric_filter_name" {
  description = "Name of the conversation quality score metric filter"
  value       = aws_cloudwatch_log_metric_filter.conversation_quality.name
}

output "business_outcome_metric_filter_name" {
  description = "Name of the business outcome success metric filter"
  value       = aws_cloudwatch_log_metric_filter.business_outcome_success.name
}

# Configuration Values
output "agent_name" {
  description = "Name of the agent being monitored"
  value       = local.agent_name
}

output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_string.suffix.result
}

# Monitoring Endpoints
output "monitoring_configuration" {
  description = "Complete monitoring configuration for AgentCore setup"
  value = {
    agent_name           = local.agent_name
    s3_bucket_name      = aws_s3_bucket.monitoring_data.id
    lambda_function_arn = aws_lambda_function.performance_monitor.arn
    log_group_name      = aws_cloudwatch_log_group.agentcore.name
    dashboard_url       = var.create_dashboard ? "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.agentcore_performance[0].dashboard_name}" : null
    alarm_arns = {
      high_latency      = aws_cloudwatch_metric_alarm.high_latency.arn
      high_system_errors = aws_cloudwatch_metric_alarm.high_system_errors.arn
      high_throttles    = aws_cloudwatch_metric_alarm.high_throttles.arn
    }
  }
  sensitive = false
}