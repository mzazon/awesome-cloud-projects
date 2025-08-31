# Output values for the Simple File Backup Notifications infrastructure
# These outputs provide important information for verification and integration

# S3 Bucket Information
output "s3_bucket_name" {
  description = "Name of the S3 bucket created for backup file storage"
  value       = aws_s3_bucket.backup_bucket.bucket
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket created for backup file storage"
  value       = aws_s3_bucket.backup_bucket.arn
}

output "s3_bucket_domain_name" {
  description = "Domain name of the S3 bucket"
  value       = aws_s3_bucket.backup_bucket.bucket_domain_name
}

output "s3_bucket_region" {
  description = "AWS region where the S3 bucket was created"
  value       = aws_s3_bucket.backup_bucket.region
}

output "s3_bucket_hosted_zone_id" {
  description = "Route 53 Hosted Zone ID for the S3 bucket region"
  value       = aws_s3_bucket.backup_bucket.hosted_zone_id
}

# SNS Topic Information
output "sns_topic_name" {
  description = "Name of the SNS topic for backup notifications"
  value       = aws_sns_topic.backup_notifications.name
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for backup notifications"
  value       = aws_sns_topic.backup_notifications.arn
}

output "sns_topic_display_name" {
  description = "Display name of the SNS topic"
  value       = aws_sns_topic.backup_notifications.display_name
}

# Email Subscription Information
output "email_subscriptions" {
  description = "List of email addresses subscribed to backup notifications"
  value       = var.email_addresses
}

output "sns_subscription_arns" {
  description = "ARNs of the SNS email subscriptions (empty until confirmed)"
  value       = aws_sns_topic_subscription.email_notifications[*].arn
}

# Configuration Status
output "s3_versioning_enabled" {
  description = "Whether S3 bucket versioning is enabled"
  value       = var.enable_s3_versioning
}

output "s3_encryption_enabled" {
  description = "Whether S3 bucket encryption is enabled"
  value       = var.enable_s3_encryption
}

output "s3_encryption_algorithm" {
  description = "Server-side encryption algorithm used for S3 bucket"
  value       = var.enable_s3_encryption ? var.s3_encryption_algorithm : "None"
}

output "notification_event_types" {
  description = "List of S3 event types that trigger notifications"
  value       = var.notification_event_types
}

# Optional CloudTrail Information
output "cloudtrail_enabled" {
  description = "Whether CloudTrail logging is enabled for the S3 bucket"
  value       = var.enable_cloudtrail_logging
}

output "cloudtrail_name" {
  description = "Name of the CloudTrail (if enabled)"
  value       = var.enable_cloudtrail_logging ? aws_cloudtrail.s3_access_trail[0].name : null
}

output "cloudtrail_arn" {
  description = "ARN of the CloudTrail (if enabled)"
  value       = var.enable_cloudtrail_logging ? aws_cloudtrail.s3_access_trail[0].arn : null
}

output "cloudtrail_logs_bucket" {
  description = "Name of the CloudTrail logs bucket (if enabled)"
  value       = var.enable_cloudtrail_logging ? aws_s3_bucket.cloudtrail_logs[0].bucket : null
}

# AWS Account and Region Information
output "aws_account_id" {
  description = "AWS Account ID where resources were created"
  value       = data.aws_caller_identity.current.account_id
}

output "aws_region" {
  description = "AWS region where resources were created"
  value       = data.aws_region.current.name
}

# Usage Instructions
output "upload_command_example" {
  description = "Example AWS CLI command to upload a test file to the bucket"
  value       = "aws s3 cp test-backup.txt s3://${aws_s3_bucket.backup_bucket.bucket}/"
}

output "list_objects_command" {
  description = "AWS CLI command to list objects in the backup bucket"
  value       = "aws s3 ls s3://${aws_s3_bucket.backup_bucket.bucket}/ --recursive"
}

# Verification Commands
output "sns_topic_attributes_command" {
  description = "AWS CLI command to view SNS topic attributes"
  value       = "aws sns get-topic-attributes --topic-arn ${aws_sns_topic.backup_notifications.arn}"
}

output "s3_notification_config_command" {
  description = "AWS CLI command to view S3 bucket notification configuration"
  value       = "aws s3api get-bucket-notification-configuration --bucket ${aws_s3_bucket.backup_bucket.bucket}"
}

# Resource Tags
output "resource_tags" {
  description = "Common tags applied to all resources"
  value       = local.common_tags
}

# Lifecycle Configuration
output "lifecycle_expiration_days" {
  description = "Number of days after which backup files will be automatically deleted (0 = disabled)"
  value       = var.s3_lifecycle_expiration_days
}

# Filter Configuration
output "object_prefix_filter" {
  description = "Prefix filter for S3 notifications (empty = all objects)"
  value       = var.s3_object_prefix_filter != "" ? var.s3_object_prefix_filter : "None (all objects)"
}

output "object_suffix_filter" {
  description = "Suffix filter for S3 notifications (empty = all objects)"
  value       = var.s3_object_suffix_filter != "" ? var.s3_object_suffix_filter : "None (all objects)"
}

# Cost Estimation Information
output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown for the solution"
  value = {
    s3_storage_gb          = "~$0.023 per GB stored"
    s3_requests            = "~$0.0004 per 1,000 PUT requests"
    sns_requests           = "~$0.50 per 1 million requests"
    sns_email_delivery     = "~$0.000 per email (up to 1,000 free per month)"
    cloudtrail_events      = var.enable_cloudtrail_logging ? "~$2.00 per 100,000 events" : "Not enabled"
    total_typical_monthly  = "~$0.01-$0.50 for typical backup scenarios"
  }
}