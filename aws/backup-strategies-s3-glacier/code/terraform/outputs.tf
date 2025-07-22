# outputs.tf
# Output values for backup strategies with S3 and Glacier

# S3 Bucket Outputs
output "backup_bucket_name" {
  description = "Name of the primary backup S3 bucket"
  value       = aws_s3_bucket.backup_bucket.id
}

output "backup_bucket_arn" {
  description = "ARN of the primary backup S3 bucket"
  value       = aws_s3_bucket.backup_bucket.arn
}

output "backup_bucket_domain_name" {
  description = "Domain name of the primary backup S3 bucket"
  value       = aws_s3_bucket.backup_bucket.bucket_domain_name
}

output "backup_bucket_regional_domain_name" {
  description = "Regional domain name of the primary backup S3 bucket"
  value       = aws_s3_bucket.backup_bucket.bucket_regional_domain_name
}

# Disaster Recovery Bucket Outputs (if enabled)
output "dr_bucket_name" {
  description = "Name of the disaster recovery S3 bucket"
  value       = var.enable_cross_region_replication ? aws_s3_bucket.dr_bucket[0].id : null
}

output "dr_bucket_arn" {
  description = "ARN of the disaster recovery S3 bucket"
  value       = var.enable_cross_region_replication ? aws_s3_bucket.dr_bucket[0].arn : null
}

output "dr_bucket_region" {
  description = "Region of the disaster recovery S3 bucket"
  value       = var.enable_cross_region_replication ? var.dr_region : null
}

# Lambda Function Outputs
output "backup_lambda_function_name" {
  description = "Name of the backup orchestrator Lambda function"
  value       = aws_lambda_function.backup_orchestrator.function_name
}

output "backup_lambda_function_arn" {
  description = "ARN of the backup orchestrator Lambda function"
  value       = aws_lambda_function.backup_orchestrator.arn
}

output "backup_lambda_function_invoke_arn" {
  description = "Invoke ARN of the backup orchestrator Lambda function"
  value       = aws_lambda_function.backup_orchestrator.invoke_arn
}

output "backup_lambda_role_arn" {
  description = "ARN of the backup Lambda execution role"
  value       = aws_iam_role.backup_lambda_role.arn
}

# SNS Topic Outputs
output "backup_notifications_topic_name" {
  description = "Name of the backup notifications SNS topic"
  value       = aws_sns_topic.backup_notifications.name
}

output "backup_notifications_topic_arn" {
  description = "ARN of the backup notifications SNS topic"
  value       = aws_sns_topic.backup_notifications.arn
}

# EventBridge Rules Outputs
output "daily_backup_rule_name" {
  description = "Name of the daily backup EventBridge rule"
  value       = aws_cloudwatch_event_rule.daily_backup.name
}

output "daily_backup_rule_arn" {
  description = "ARN of the daily backup EventBridge rule"
  value       = aws_cloudwatch_event_rule.daily_backup.arn
}

output "weekly_backup_rule_name" {
  description = "Name of the weekly backup EventBridge rule"
  value       = aws_cloudwatch_event_rule.weekly_backup.name
}

output "weekly_backup_rule_arn" {
  description = "ARN of the weekly backup EventBridge rule"
  value       = aws_cloudwatch_event_rule.weekly_backup.arn
}

# CloudWatch Monitoring Outputs
output "backup_failure_alarm_name" {
  description = "Name of the backup failure CloudWatch alarm"
  value       = aws_cloudwatch_metric_alarm.backup_failure_alarm.alarm_name
}

output "backup_duration_alarm_name" {
  description = "Name of the backup duration CloudWatch alarm"
  value       = aws_cloudwatch_metric_alarm.backup_duration_alarm.alarm_name
}

output "backup_dashboard_name" {
  description = "Name of the backup monitoring CloudWatch dashboard"
  value       = aws_cloudwatch_dashboard.backup_dashboard.dashboard_name
}

output "backup_dashboard_url" {
  description = "URL of the backup monitoring CloudWatch dashboard"
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.backup_dashboard.dashboard_name}"
}

# CloudWatch Log Group Outputs
output "backup_lambda_log_group_name" {
  description = "Name of the backup Lambda CloudWatch log group"
  value       = aws_cloudwatch_log_group.backup_lambda_logs.name
}

output "backup_lambda_log_group_arn" {
  description = "ARN of the backup Lambda CloudWatch log group"
  value       = aws_cloudwatch_log_group.backup_lambda_logs.arn
}

# Replication Role Output (if enabled)
output "replication_role_arn" {
  description = "ARN of the S3 cross-region replication role"
  value       = var.enable_cross_region_replication ? aws_iam_role.replication_role[0].arn : null
}

# Configuration Summary Outputs
output "lifecycle_policy_summary" {
  description = "Summary of the S3 lifecycle policy configuration"
  value = {
    standard_to_ia_days      = var.lifecycle_transition_ia_days
    ia_to_glacier_days       = var.lifecycle_transition_glacier_days
    glacier_to_deep_archive_days = var.lifecycle_transition_deep_archive_days
    noncurrent_version_expiration_days = var.noncurrent_version_expiration_days
  }
}

output "backup_schedule_summary" {
  description = "Summary of the backup schedule configuration"
  value = {
    daily_schedule  = var.backup_schedule_daily
    weekly_schedule = var.backup_schedule_weekly
    timezone       = "UTC"
  }
}

output "features_enabled" {
  description = "Summary of enabled features"
  value = {
    cross_region_replication = var.enable_cross_region_replication
    intelligent_tiering     = var.enable_intelligent_tiering
    email_notifications     = var.notification_email != ""
  }
}

# AWS Account and Region Information
output "aws_account_id" {
  description = "AWS Account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

output "primary_region" {
  description = "Primary AWS region for backup infrastructure"
  value       = var.aws_region
}

output "disaster_recovery_region" {
  description = "Disaster recovery AWS region"
  value       = var.dr_region
}

# Resource Naming Information
output "resource_name_suffix" {
  description = "Random suffix used for resource naming"
  value       = local.name_suffix
  sensitive   = false
}

# Quick Access URLs
output "s3_console_url" {
  description = "URL to access the primary backup bucket in AWS S3 console"
  value       = "https://s3.console.aws.amazon.com/s3/buckets/${aws_s3_bucket.backup_bucket.id}?region=${var.aws_region}"
}

output "lambda_console_url" {
  description = "URL to access the backup Lambda function in AWS console"
  value       = "https://${var.aws_region}.console.aws.amazon.com/lambda/home?region=${var.aws_region}#/functions/${aws_lambda_function.backup_orchestrator.function_name}"
}

output "sns_console_url" {
  description = "URL to access the SNS topic in AWS console"
  value       = "https://${var.aws_region}.console.aws.amazon.com/sns/v3/home?region=${var.aws_region}#/topic/${aws_sns_topic.backup_notifications.arn}"
}

# Deployment Instructions
output "next_steps" {
  description = "Next steps to complete the backup setup"
  value = [
    "1. If email notifications are configured, check your email and confirm the SNS subscription",
    "2. Upload test data to the S3 bucket to validate the backup process",
    "3. Monitor the CloudWatch dashboard for backup metrics and status",
    "4. Test the backup function manually using the AWS Lambda console",
    "5. Review and adjust lifecycle policies based on your data access patterns"
  ]
}