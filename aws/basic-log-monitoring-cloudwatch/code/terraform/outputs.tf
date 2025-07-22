# Output values for Basic Log Monitoring Infrastructure

# ====================================================================
# CloudWatch Log Group Outputs
# ====================================================================

output "log_group_name" {
  description = "Name of the CloudWatch Log Group"
  value       = aws_cloudwatch_log_group.application_logs.name
}

output "log_group_arn" {
  description = "ARN of the CloudWatch Log Group"
  value       = aws_cloudwatch_log_group.application_logs.arn
}

output "log_group_retention_days" {
  description = "Log retention period in days"
  value       = aws_cloudwatch_log_group.application_logs.retention_in_days
}

# ====================================================================
# SNS Topic Outputs
# ====================================================================

output "sns_topic_name" {
  description = "Name of the SNS topic for alert notifications"
  value       = aws_sns_topic.log_monitoring_alerts.name
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for alert notifications"
  value       = aws_sns_topic.log_monitoring_alerts.arn
}

output "email_subscription_arn" {
  description = "ARN of the email subscription to SNS topic"
  value       = aws_sns_topic_subscription.email_notification.arn
}

# ====================================================================
# Lambda Function Outputs
# ====================================================================

output "lambda_function_name" {
  description = "Name of the Lambda log processor function"
  value       = aws_lambda_function.log_processor.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda log processor function"
  value       = aws_lambda_function.log_processor.arn
}

output "lambda_function_invoke_arn" {
  description = "Invoke ARN of the Lambda log processor function"
  value       = aws_lambda_function.log_processor.invoke_arn
}

output "lambda_role_arn" {
  description = "ARN of the IAM role for Lambda function"
  value       = aws_iam_role.lambda_log_processor_role.arn
}

output "lambda_log_group_name" {
  description = "Name of the CloudWatch Log Group for Lambda function"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

# ====================================================================
# CloudWatch Monitoring Outputs
# ====================================================================

output "metric_filter_name" {
  description = "Name of the CloudWatch Logs metric filter"
  value       = aws_cloudwatch_log_metric_filter.error_count_filter.name
}

output "metric_name" {
  description = "Name of the custom CloudWatch metric"
  value       = local.metric_name
}

output "metric_namespace" {
  description = "Namespace of the custom CloudWatch metric"
  value       = local.metric_namespace
}

output "alarm_name" {
  description = "Name of the CloudWatch alarm"
  value       = aws_cloudwatch_metric_alarm.application_errors.alarm_name
}

output "alarm_arn" {
  description = "ARN of the CloudWatch alarm"
  value       = aws_cloudwatch_metric_alarm.application_errors.arn
}

output "alarm_threshold" {
  description = "Error threshold that triggers the alarm"
  value       = aws_cloudwatch_metric_alarm.application_errors.threshold
}

output "dashboard_url" {
  description = "URL to the CloudWatch dashboard"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.log_monitoring_dashboard.dashboard_name}"
}

# ====================================================================
# Testing and Validation Outputs
# ====================================================================

output "test_log_command" {
  description = "AWS CLI command to send test log events"
  value = "aws logs put-log-events --log-group-name ${aws_cloudwatch_log_group.application_logs.name} --log-stream-name test-stream-$(date +%Y%m%d%H%M%S) --log-events timestamp=$(date +%s000),message='ERROR: Test error message for alarm validation'"
}

output "create_log_stream_command" {
  description = "AWS CLI command to create a log stream"
  value = "aws logs create-log-stream --log-group-name ${aws_cloudwatch_log_group.application_logs.name} --log-stream-name test-stream-$(date +%Y%m%d%H%M%S)"
}

output "check_alarm_state_command" {
  description = "AWS CLI command to check alarm state"
  value = "aws cloudwatch describe-alarms --alarm-names ${aws_cloudwatch_metric_alarm.application_errors.alarm_name}"
}

output "view_lambda_logs_command" {
  description = "AWS CLI command to view Lambda function logs"
  value = "aws logs tail ${aws_cloudwatch_log_group.lambda_logs.name} --follow"
}

# ====================================================================
# Configuration Summary
# ====================================================================

output "monitoring_configuration" {
  description = "Summary of the monitoring configuration"
  value = {
    environment           = var.environment
    log_group            = aws_cloudwatch_log_group.application_logs.name
    sns_topic            = aws_sns_topic.log_monitoring_alerts.name
    lambda_function      = aws_lambda_function.log_processor.function_name
    alarm_name           = aws_cloudwatch_metric_alarm.application_errors.alarm_name
    error_threshold      = var.error_threshold
    evaluation_periods   = var.alarm_evaluation_periods
    period_seconds       = var.alarm_period_seconds
    notification_email   = var.notification_email
    dashboard_name       = aws_cloudwatch_dashboard.log_monitoring_dashboard.dashboard_name
  }
}

# ====================================================================
# Resource ARNs for Integration
# ====================================================================

output "resource_arns" {
  description = "ARNs of all created resources for integration purposes"
  value = {
    log_group       = aws_cloudwatch_log_group.application_logs.arn
    sns_topic       = aws_sns_topic.log_monitoring_alerts.arn
    lambda_function = aws_lambda_function.log_processor.arn
    lambda_role     = aws_iam_role.lambda_log_processor_role.arn
    alarm          = aws_cloudwatch_metric_alarm.application_errors.arn
  }
}

# ====================================================================
# Next Steps Information
# ====================================================================

output "next_steps" {
  description = "Instructions for next steps after deployment"
  value = <<-EOT
1. Confirm the email subscription by checking your email inbox
2. Test the monitoring by running: ${aws_cloudwatch_dashboard.log_monitoring_dashboard.dashboard_name}
3. View the CloudWatch dashboard at: https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.log_monitoring_dashboard.dashboard_name}
4. Monitor Lambda function logs for processing details
5. Configure your applications to send logs to: ${aws_cloudwatch_log_group.application_logs.name}
EOT
}