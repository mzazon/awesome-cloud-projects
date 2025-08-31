# Outputs for the resource cleanup automation infrastructure
# These outputs provide important information for verification, monitoring,
# and integration with other systems

# ====================================================================
# Lambda Function Outputs
# ====================================================================

output "lambda_function_name" {
  description = "Name of the Lambda function for resource cleanup"
  value       = aws_lambda_function.resource_cleanup.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function for resource cleanup"
  value       = aws_lambda_function.resource_cleanup.arn
}

output "lambda_function_invoke_arn" {
  description = "Invoke ARN of the Lambda function (for API Gateway integration)"
  value       = aws_lambda_function.resource_cleanup.invoke_arn
}

output "lambda_function_version" {
  description = "Latest published version of the Lambda function"
  value       = aws_lambda_function.resource_cleanup.version
}

output "lambda_log_group_name" {
  description = "CloudWatch log group name for Lambda function logs"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

output "lambda_log_group_arn" {
  description = "CloudWatch log group ARN for Lambda function logs"
  value       = aws_cloudwatch_log_group.lambda_logs.arn
}

# ====================================================================
# SNS Topic Outputs
# ====================================================================

output "sns_topic_name" {
  description = "Name of the SNS topic for cleanup notifications"
  value       = aws_sns_topic.cleanup_alerts.name
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for cleanup notifications"
  value       = aws_sns_topic.cleanup_alerts.arn
}

output "sns_topic_display_name" {
  description = "Display name of the SNS topic"
  value       = aws_sns_topic.cleanup_alerts.display_name
}

# ====================================================================
# IAM Role Outputs
# ====================================================================

output "lambda_execution_role_name" {
  description = "Name of the IAM role for Lambda function execution"
  value       = aws_iam_role.lambda_execution_role.name
}

output "lambda_execution_role_arn" {
  description = "ARN of the IAM role for Lambda function execution"
  value       = aws_iam_role.lambda_execution_role.arn
}

# ====================================================================
# CloudWatch Events Outputs (Conditional)
# ====================================================================

output "cleanup_schedule_rule_name" {
  description = "Name of the CloudWatch Events rule for scheduled cleanup (if enabled)"
  value       = var.enable_scheduled_cleanup ? aws_cloudwatch_event_rule.cleanup_schedule[0].name : null
}

output "cleanup_schedule_rule_arn" {
  description = "ARN of the CloudWatch Events rule for scheduled cleanup (if enabled)"
  value       = var.enable_scheduled_cleanup ? aws_cloudwatch_event_rule.cleanup_schedule[0].arn : null
}

output "cleanup_schedule_expression" {
  description = "Schedule expression for automated cleanup execution"
  value       = var.schedule_expression
}

output "scheduled_cleanup_enabled" {
  description = "Whether scheduled cleanup is enabled"
  value       = var.enable_scheduled_cleanup
}

# ====================================================================
# CloudWatch Alarms Outputs
# ====================================================================

output "lambda_errors_alarm_name" {
  description = "Name of the CloudWatch alarm for Lambda function errors"
  value       = aws_cloudwatch_metric_alarm.lambda_errors.alarm_name
}

output "lambda_errors_alarm_arn" {
  description = "ARN of the CloudWatch alarm for Lambda function errors"
  value       = aws_cloudwatch_metric_alarm.lambda_errors.arn
}

output "lambda_duration_alarm_name" {
  description = "Name of the CloudWatch alarm for Lambda function duration"
  value       = aws_cloudwatch_metric_alarm.lambda_duration.alarm_name
}

output "lambda_duration_alarm_arn" {
  description = "ARN of the CloudWatch alarm for Lambda function duration"
  value       = aws_cloudwatch_metric_alarm.lambda_duration.arn
}

# ====================================================================
# Configuration Outputs
# ====================================================================

output "cleanup_tag_key" {
  description = "Tag key used to identify resources for cleanup"
  value       = var.cleanup_tag_key
}

output "cleanup_tag_values" {
  description = "Tag values that trigger resource cleanup"
  value       = var.cleanup_tag_values
}

output "dry_run_mode" {
  description = "Whether the cleanup function is running in dry run mode"
  value       = var.dry_run_mode
}

output "lambda_timeout_seconds" {
  description = "Lambda function timeout in seconds"
  value       = var.lambda_timeout
}

output "lambda_memory_size_mb" {
  description = "Lambda function memory allocation in MB"
  value       = var.lambda_memory_size
}

# ====================================================================
# Deployment Information
# ====================================================================

output "deployment_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "aws_account_id" {
  description = "AWS account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

output "resource_name_suffix" {
  description = "Random suffix used for resource naming"
  value       = local.name_suffix
}

output "common_tags" {
  description = "Common tags applied to all resources"
  value       = local.common_tags
}

# ====================================================================
# Usage Instructions
# ====================================================================

output "manual_invocation_command" {
  description = "AWS CLI command to manually invoke the cleanup function"
  value       = "aws lambda invoke --function-name ${aws_lambda_function.resource_cleanup.function_name} --payload '{}' response.json && cat response.json"
}

output "cloudwatch_logs_command" {
  description = "AWS CLI command to view recent Lambda function logs"
  value       = "aws logs filter-log-events --log-group-name ${aws_cloudwatch_log_group.lambda_logs.name}"
}

output "test_instance_tag_command" {
  description = "AWS CLI command to tag an instance for cleanup testing"
  value       = "aws ec2 create-tags --resources <INSTANCE-ID> --tags Key=${var.cleanup_tag_key},Value=${var.cleanup_tag_values[0]}"
}

# ====================================================================
# Email Subscription Status
# ====================================================================

output "email_subscription_status" {
  description = "Status of email subscription to SNS topic"
  value = var.notification_email != "" ? {
    email_address = var.notification_email
    subscription_created = true
    confirmation_required = true
    message = "Check your email and confirm the subscription to receive notifications"
  } : {
    email_address = null
    subscription_created = false
    confirmation_required = false
    message = "No email address provided - no email notifications will be sent"
  }
}

# ====================================================================
# Cost Optimization Information
# ====================================================================

output "estimated_monthly_cost" {
  description = "Estimated monthly cost for running this infrastructure"
  value = {
    lambda_requests_1000 = "$0.20"
    lambda_compute_gb_seconds = "$0.0000166667"
    sns_notifications_1000 = "$0.50"
    cloudwatch_logs_gb = "$0.50"
    total_estimated_low_usage = "$1.00-$3.00"
    note = "Actual costs depend on execution frequency and log volume"
  }
}

output "next_steps" {
  description = "Next steps after deployment"
  value = [
    "1. If email notifications are enabled, check your inbox and confirm the SNS subscription",
    "2. Test the function manually using: ${aws_lambda_function.resource_cleanup.function_name}",
    "3. Create test EC2 instances with tag: ${var.cleanup_tag_key}=${var.cleanup_tag_values[0]}",
    "4. Monitor CloudWatch logs: ${aws_cloudwatch_log_group.lambda_logs.name}",
    var.enable_scheduled_cleanup ? "5. Scheduled cleanup is enabled with expression: ${var.schedule_expression}" : "5. Enable scheduled cleanup by setting enable_scheduled_cleanup=true",
    var.dry_run_mode ? "6. Dry run mode is enabled - no instances will be terminated until disabled" : "6. Live mode is enabled - instances will be terminated when cleanup runs"
  ]
}