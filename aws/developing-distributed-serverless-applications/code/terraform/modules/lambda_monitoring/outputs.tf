# Outputs for Lambda Monitoring Module

output "error_rate_alarm_arn" {
  description = "ARN of the Lambda error rate alarm"
  value       = aws_cloudwatch_metric_alarm.lambda_error_rate.arn
}

output "duration_alarm_arn" {
  description = "ARN of the Lambda duration alarm"
  value       = aws_cloudwatch_metric_alarm.lambda_duration.arn
}

output "throttles_alarm_arn" {
  description = "ARN of the Lambda throttles alarm"
  value       = aws_cloudwatch_metric_alarm.lambda_throttles.arn
}

output "concurrent_executions_alarm_arn" {
  description = "ARN of the Lambda concurrent executions alarm"
  value       = aws_cloudwatch_metric_alarm.lambda_concurrent_executions.arn
}

output "invocation_anomaly_alarm_arn" {
  description = "ARN of the Lambda invocation anomaly alarm"
  value       = aws_cloudwatch_metric_alarm.lambda_invocation_anomaly.arn
}

output "dashboard_url" {
  description = "URL of the CloudWatch dashboard"
  value       = "https://${var.region}.console.aws.amazon.com/cloudwatch/home?region=${var.region}#dashboards:name=${aws_cloudwatch_dashboard.lambda_dashboard.dashboard_name}"
}

output "dashboard_name" {
  description = "Name of the CloudWatch dashboard"
  value       = aws_cloudwatch_dashboard.lambda_dashboard.dashboard_name
}

output "all_alarm_arns" {
  description = "List of all alarm ARNs created by this module"
  value = [
    aws_cloudwatch_metric_alarm.lambda_error_rate.arn,
    aws_cloudwatch_metric_alarm.lambda_duration.arn,
    aws_cloudwatch_metric_alarm.lambda_throttles.arn,
    aws_cloudwatch_metric_alarm.lambda_concurrent_executions.arn,
    aws_cloudwatch_metric_alarm.lambda_invocation_anomaly.arn
  ]
}