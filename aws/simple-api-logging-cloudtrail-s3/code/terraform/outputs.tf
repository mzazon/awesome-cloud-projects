# Output Values for CloudTrail API Logging Infrastructure
# These outputs provide essential information about the created resources
# for verification, integration with other systems, and operational monitoring

# CloudTrail Information
output "cloudtrail_arn" {
  description = "ARN of the CloudTrail trail for API logging"
  value       = aws_cloudtrail.main.arn
}

output "cloudtrail_name" {
  description = "Name of the CloudTrail trail"
  value       = aws_cloudtrail.main.name
}

output "cloudtrail_home_region" {
  description = "Home region of the CloudTrail trail"
  value       = aws_cloudtrail.main.home_region
}

# S3 Bucket Information
output "s3_bucket_name" {
  description = "Name of the S3 bucket storing CloudTrail logs"
  value       = aws_s3_bucket.cloudtrail_logs.id
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket storing CloudTrail logs"
  value       = aws_s3_bucket.cloudtrail_logs.arn
}

output "s3_bucket_domain_name" {
  description = "Bucket domain name for accessing CloudTrail logs"
  value       = aws_s3_bucket.cloudtrail_logs.bucket_domain_name
}

output "s3_bucket_regional_domain_name" {
  description = "Regional domain name of the S3 bucket"
  value       = aws_s3_bucket.cloudtrail_logs.bucket_regional_domain_name
}

# CloudWatch Logs Information
output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for real-time CloudTrail events"
  value       = aws_cloudwatch_log_group.cloudtrail.name
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.cloudtrail.arn
}

output "cloudwatch_log_retention_days" {
  description = "Number of days CloudWatch logs are retained"
  value       = aws_cloudwatch_log_group.cloudtrail.retention_in_days
}

# IAM Role Information
output "cloudtrail_role_arn" {
  description = "ARN of the IAM role used by CloudTrail for CloudWatch Logs integration"
  value       = aws_iam_role.cloudtrail_logs.arn
}

output "cloudtrail_role_name" {
  description = "Name of the IAM role used by CloudTrail"
  value       = aws_iam_role.cloudtrail_logs.name
}

# SNS Topic Information (when alarms are enabled)
output "sns_topic_arn" {
  description = "ARN of the SNS topic for CloudTrail alarm notifications"
  value       = var.enable_cloudwatch_alarms ? aws_sns_topic.cloudtrail_alerts[0].arn : null
}

output "sns_topic_name" {
  description = "Name of the SNS topic for notifications"
  value       = var.enable_cloudwatch_alarms ? aws_sns_topic.cloudtrail_alerts[0].name : null
}

# CloudWatch Alarm Information (when alarms are enabled)
output "root_account_alarm_name" {
  description = "Name of the CloudWatch alarm monitoring root account usage"
  value       = var.enable_cloudwatch_alarms ? aws_cloudwatch_metric_alarm.root_account_usage[0].alarm_name : null
}

output "root_account_alarm_arn" {
  description = "ARN of the CloudWatch alarm monitoring root account usage"
  value       = var.enable_cloudwatch_alarms ? aws_cloudwatch_metric_alarm.root_account_usage[0].arn : null
}

# Configuration Summary
output "trail_configuration" {
  description = "Summary of CloudTrail configuration settings"
  value = {
    multi_region_trail        = aws_cloudtrail.main.is_multi_region_trail
    global_service_events     = aws_cloudtrail.main.include_global_service_events
    log_file_validation      = aws_cloudtrail.main.enable_log_file_validation
    cloudwatch_logs_enabled  = aws_cloudtrail.main.cloud_watch_logs_group_arn != null
    kms_encryption_enabled   = aws_cloudtrail.main.kms_key_id != null
    s3_key_prefix           = aws_cloudtrail.main.s3_key_prefix
  }
}

# Resource Tags (for tracking and management)
output "resource_tags" {
  description = "Common tags applied to all resources"
  value       = local.common_tags
  sensitive   = false
}

# Deployment Information
output "deployment_info" {
  description = "Information about the deployment for troubleshooting and verification"
  value = {
    aws_account_id    = local.account_id
    aws_region        = local.region
    random_suffix     = local.random_suffix
    terraform_version = ">=1.0"
    aws_provider      = "~>5.0"
  }
}

# Operational Commands
output "verification_commands" {
  description = "AWS CLI commands for verifying the CloudTrail setup"
  value = {
    check_trail_status = "aws cloudtrail get-trail-status --name ${aws_cloudtrail.main.name}"
    list_recent_events = "aws cloudtrail lookup-events --max-items 10"
    check_s3_logs      = "aws s3 ls s3://${aws_s3_bucket.cloudtrail_logs.id}/${var.s3_key_prefix}/AWSLogs/${local.account_id}/CloudTrail/ --recursive"
    check_log_streams  = "aws logs describe-log-streams --log-group-name ${aws_cloudwatch_log_group.cloudtrail.name} --order-by LastEventTime --descending"
  }
}

# Security Information
output "security_features" {
  description = "Summary of security features enabled in the deployment"
  value = {
    s3_encryption_enabled     = var.enable_s3_encryption
    s3_versioning_enabled     = var.enable_s3_versioning
    s3_public_access_blocked  = true
    log_file_validation       = var.enable_log_file_validation
    source_arn_conditions     = true
    least_privilege_iam       = true
    cloudwatch_alarms_enabled = var.enable_cloudwatch_alarms
  }
}