# ==============================================================================
# Outputs for Automated Business Task Scheduling
# ==============================================================================

# Resource Identifiers
output "s3_bucket_name" {
  description = "Name of the S3 bucket for storing reports and processed data"
  value       = aws_s3_bucket.reports.bucket
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket for storing reports and processed data"
  value       = aws_s3_bucket.reports.arn
}

output "sns_topic_name" {
  description = "Name of the SNS topic for notifications"
  value       = aws_sns_topic.notifications.name
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for notifications"
  value       = aws_sns_topic.notifications.arn
}

output "lambda_function_name" {
  description = "Name of the Lambda function processing business tasks"
  value       = aws_lambda_function.business_task_processor.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function processing business tasks"
  value       = aws_lambda_function.business_task_processor.arn
}

output "schedule_group_name" {
  description = "Name of the EventBridge Scheduler schedule group"
  value       = aws_scheduler_schedule_group.business_automation.name
}

output "schedule_group_arn" {
  description = "ARN of the EventBridge Scheduler schedule group"
  value       = aws_scheduler_schedule_group.business_automation.arn
}

# IAM Role Information
output "lambda_execution_role_arn" {
  description = "ARN of the Lambda execution IAM role"
  value       = aws_iam_role.lambda_execution.arn
}

output "scheduler_execution_role_arn" {
  description = "ARN of the EventBridge Scheduler execution IAM role"
  value       = aws_iam_role.scheduler_execution.arn
}

# Schedule Information
output "daily_report_schedule_arn" {
  description = "ARN of the daily report schedule"
  value       = aws_scheduler_schedule.daily_reports.arn
}

output "daily_report_schedule_name" {
  description = "Name of the daily report schedule"
  value       = aws_scheduler_schedule.daily_reports.name
}

output "hourly_processing_schedule_arn" {
  description = "ARN of the hourly data processing schedule (if enabled)"
  value       = var.enable_hourly_processing ? aws_scheduler_schedule.hourly_processing[0].arn : null
}

output "hourly_processing_schedule_name" {
  description = "Name of the hourly data processing schedule (if enabled)"
  value       = var.enable_hourly_processing ? aws_scheduler_schedule.hourly_processing[0].name : null
}

output "weekly_notification_schedule_arn" {
  description = "ARN of the weekly notification schedule (if enabled)"
  value       = var.enable_weekly_notifications ? aws_scheduler_schedule.weekly_notifications[0].arn : null
}

output "weekly_notification_schedule_name" {
  description = "Name of the weekly notification schedule (if enabled)"
  value       = var.enable_weekly_notifications ? aws_scheduler_schedule.weekly_notifications[0].name : null
}

# Monitoring Information
output "lambda_log_group_name" {
  description = "Name of the CloudWatch log group for Lambda function"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

output "lambda_log_group_arn" {
  description = "ARN of the CloudWatch log group for Lambda function"
  value       = aws_cloudwatch_log_group.lambda_logs.arn
}

output "lambda_error_alarm_arn" {
  description = "ARN of the Lambda error CloudWatch alarm (if monitoring enabled)"
  value       = var.enable_monitoring ? aws_cloudwatch_metric_alarm.lambda_errors[0].arn : null
}

output "lambda_duration_alarm_arn" {
  description = "ARN of the Lambda duration CloudWatch alarm (if monitoring enabled)"
  value       = var.enable_monitoring ? aws_cloudwatch_metric_alarm.lambda_duration[0].arn : null
}

# Configuration Information
output "schedules_enabled" {
  description = "Whether EventBridge schedules are currently enabled"
  value       = var.schedules_enabled
}

output "timezone" {
  description = "Timezone used for schedule expressions"
  value       = var.timezone
}

output "environment" {
  description = "Environment name for this deployment"
  value       = var.environment
}

# Endpoint Information
output "s3_bucket_website_endpoint" {
  description = "S3 bucket website endpoint (for accessing reports via URL)"
  value       = aws_s3_bucket.reports.bucket_domain_name
}

output "s3_bucket_regional_domain_name" {
  description = "S3 bucket regional domain name"
  value       = aws_s3_bucket.reports.bucket_regional_domain_name
}

# Email Subscription Information
output "email_subscription_arn" {
  description = "ARN of the email subscription (if email provided)"
  value       = var.notification_email != "" ? aws_sns_topic_subscription.email[0].arn : null
}

output "email_subscription_pending" {
  description = "Whether email subscription confirmation is pending"
  value       = var.notification_email != "" ? "Email confirmation required - check your inbox" : "No email subscription configured"
}

# AWS Account and Region Information
output "aws_account_id" {
  description = "AWS Account ID where resources were created"
  value       = data.aws_caller_identity.current.account_id
}

output "aws_region" {
  description = "AWS Region where resources were created"
  value       = data.aws_region.current.name
}

# Cost and Resource Information
output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown for key services (USD)"
  value = {
    lambda_executions = "~$0.20 per 1M executions + $0.0000166667 per GB-second"
    eventbridge_scheduler = "~$1.00 per million schedule invocations"
    s3_storage = "~$0.023 per GB for Standard storage"
    sns_notifications = "~$0.50 per million notifications"
    cloudwatch_logs = "~$0.50 per GB ingested"
    note = "Actual costs depend on usage patterns and data volumes"
  }
}

# Deployment Summary
output "deployment_summary" {
  description = "Summary of deployed resources and their purposes"
  value = {
    s3_bucket = "Stores generated business reports and processed data"
    lambda_function = "Processes automated business tasks (reports, data processing, notifications)"
    sns_topic = "Sends notifications about task completion and failures"
    schedule_group = "Organizes related business automation schedules"
    daily_schedule = "Generates business reports daily at ${var.daily_report_schedule}"
    hourly_schedule = var.enable_hourly_processing ? "Processes data hourly at ${var.hourly_processing_schedule}" : "Disabled"
    weekly_schedule = var.enable_weekly_notifications ? "Sends status notifications weekly at ${var.weekly_notification_schedule}" : "Disabled"
    monitoring = var.enable_monitoring ? "CloudWatch alarms monitor Lambda errors and duration" : "Monitoring disabled"
  }
}

# Security Information
output "security_configuration" {
  description = "Security features enabled in this deployment"
  value = {
    s3_encryption = "AES-256 server-side encryption enabled"
    s3_public_access = "All public access blocked"
    s3_versioning = "Enabled for data protection"
    sns_encryption = "AWS managed KMS encryption enabled"
    iam_roles = "Least privilege principle applied"
    lambda_tracing = "AWS X-Ray tracing enabled"
    vpc_deployment = "Not configured (public subnet deployment)"
  }
}

# Next Steps
output "next_steps" {
  description = "Recommended next steps after deployment"
  value = {
    email_confirmation = var.notification_email != "" ? "Confirm email subscription in your inbox" : "Configure notification email in variables.tf"
    test_lambda = "Test Lambda function with: aws lambda invoke --function-name ${aws_lambda_function.business_task_processor.function_name} --payload '{\"task_type\":\"report\"}' response.json"
    view_schedules = "View schedules with: aws scheduler list-schedules --group-name ${aws_scheduler_schedule_group.business_automation.name}"
    monitor_logs = "Monitor execution logs in CloudWatch: /aws/lambda/${aws_lambda_function.business_task_processor.function_name}"
    check_s3 = "Check generated reports in S3: aws s3 ls s3://${aws_s3_bucket.reports.bucket}/reports/"
  }
}