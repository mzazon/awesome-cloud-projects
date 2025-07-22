# Outputs for S3 Glacier Archiving Infrastructure
# This file defines all the outputs that will be displayed after deployment

# S3 Bucket Information
output "bucket_name" {
  description = "Name of the S3 bucket created for archiving"
  value       = aws_s3_bucket.archive_bucket.id
}

output "bucket_arn" {
  description = "ARN of the S3 bucket"
  value       = aws_s3_bucket.archive_bucket.arn
}

output "bucket_domain_name" {
  description = "Domain name of the S3 bucket"
  value       = aws_s3_bucket.archive_bucket.bucket_domain_name
}

output "bucket_region" {
  description = "Region where the S3 bucket is located"
  value       = aws_s3_bucket.archive_bucket.region
}

# Lifecycle Configuration
output "lifecycle_glacier_transition_days" {
  description = "Number of days before objects transition to Glacier"
  value       = var.lifecycle_glacier_transition_days
}

output "lifecycle_deep_archive_transition_days" {
  description = "Number of days before objects transition to Deep Archive"
  value       = var.lifecycle_deep_archive_transition_days
}

output "archive_prefix" {
  description = "Prefix for objects that will be archived"
  value       = var.archive_prefix
}

# SNS Topic Information
output "sns_topic_name" {
  description = "Name of the SNS topic for notifications"
  value       = aws_sns_topic.archive_notifications.name
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for notifications"
  value       = aws_sns_topic.archive_notifications.arn
}

# IAM Resources
output "iam_role_name" {
  description = "Name of the IAM role for S3 access"
  value       = aws_iam_role.s3_archive_role.name
}

output "iam_role_arn" {
  description = "ARN of the IAM role for S3 access"
  value       = aws_iam_role.s3_archive_role.arn
}

output "iam_instance_profile_name" {
  description = "Name of the IAM instance profile"
  value       = aws_iam_instance_profile.s3_archive_instance_profile.name
}

output "iam_policy_arn" {
  description = "ARN of the IAM policy for S3 archive operations"
  value       = aws_iam_policy.s3_archive_policy.arn
}

# CloudWatch Resources
output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for archive operations"
  value       = aws_cloudwatch_log_group.archive_logs.name
}

output "cloudwatch_alarm_name" {
  description = "Name of the CloudWatch alarm for restore failures"
  value       = aws_cloudwatch_metric_alarm.restore_failures.alarm_name
}

# Sample Data
output "sample_data_key" {
  description = "S3 key of the sample data file"
  value       = aws_s3_object.sample_data.key
}

output "sample_data_url" {
  description = "S3 URL of the sample data file"
  value       = "s3://${aws_s3_bucket.archive_bucket.id}/${aws_s3_object.sample_data.key}"
}

# Useful Commands
output "aws_cli_commands" {
  description = "Useful AWS CLI commands for managing the archive"
  value = {
    list_objects = "aws s3 ls s3://${aws_s3_bucket.archive_bucket.id}/${var.archive_prefix} --recursive"
    
    check_lifecycle = "aws s3api get-bucket-lifecycle-configuration --bucket ${aws_s3_bucket.archive_bucket.id}"
    
    check_object_storage_class = "aws s3api head-object --bucket ${aws_s3_bucket.archive_bucket.id} --key ${var.archive_prefix}sample-data.txt"
    
    restore_object = "aws s3api restore-object --bucket ${aws_s3_bucket.archive_bucket.id} --key ${var.archive_prefix}sample-data.txt --restore-request '{\"Days\": ${var.restore_days}, \"GlacierJobParameters\": {\"Tier\": \"${var.restore_tier}\"}}'"
    
    check_restore_status = "aws s3api head-object --bucket ${aws_s3_bucket.archive_bucket.id} --key ${var.archive_prefix}sample-data.txt --query 'Restore'"
    
    subscribe_to_sns = "aws sns subscribe --topic-arn ${aws_sns_topic.archive_notifications.arn} --protocol email --notification-endpoint YOUR_EMAIL@example.com"
  }
}

# Cost Optimization Information
output "cost_optimization_summary" {
  description = "Summary of cost optimization achieved through this archiving strategy"
  value = {
    glacier_savings = "Approximately 68% cost reduction compared to S3 Standard after ${var.lifecycle_glacier_transition_days} days"
    deep_archive_savings = "Approximately 95% cost reduction compared to S3 Standard after ${var.lifecycle_deep_archive_transition_days} days"
    retrieval_times = {
      glacier_standard = "3-5 hours"
      glacier_expedited = "1-5 minutes"
      glacier_bulk = "5-12 hours"
      deep_archive_standard = "9-12 hours"
      deep_archive_bulk = "up to 48 hours"
    }
  }
}

# Security Configuration
output "security_features" {
  description = "Security features enabled for the archive bucket"
  value = {
    versioning_enabled = var.enable_versioning
    server_side_encryption = var.enable_server_side_encryption
    public_access_blocked = var.enable_public_access_block
    object_lock_enabled = var.enable_object_lock
    mfa_delete_enabled = var.enable_mfa_delete
  }
}

# Monitoring and Alerting
output "monitoring_resources" {
  description = "Monitoring and alerting resources created"
  value = {
    cloudwatch_log_group = aws_cloudwatch_log_group.archive_logs.name
    metric_filter = aws_cloudwatch_metric_filter.glacier_transitions.name
    alarm_name = aws_cloudwatch_metric_alarm.restore_failures.alarm_name
    sns_topic_for_alerts = aws_sns_topic.archive_notifications.name
  }
}

# Next Steps
output "next_steps" {
  description = "Recommended next steps after deployment"
  value = [
    "1. Upload data to the '${var.archive_prefix}' prefix in the bucket",
    "2. Subscribe to SNS notifications using: aws sns subscribe --topic-arn ${aws_sns_topic.archive_notifications.arn} --protocol email --notification-endpoint YOUR_EMAIL",
    "3. Monitor lifecycle transitions in CloudWatch",
    "4. Test restore operations after objects are archived",
    "5. Review and adjust lifecycle policy based on access patterns",
    "6. Set up additional monitoring and alerting as needed"
  ]
}