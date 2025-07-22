# Outputs for S3 Presigned URLs File Sharing Solution
# This file defines all output values that will be displayed after deployment

# Primary S3 bucket information
output "file_sharing_bucket_name" {
  description = "Name of the main S3 bucket for file sharing"
  value       = aws_s3_bucket.file_sharing.bucket
}

output "file_sharing_bucket_arn" {
  description = "ARN of the main S3 bucket for file sharing"
  value       = aws_s3_bucket.file_sharing.arn
}

output "file_sharing_bucket_region" {
  description = "AWS region where the S3 bucket is located"
  value       = aws_s3_bucket.file_sharing.region
}

output "file_sharing_bucket_domain_name" {
  description = "Bucket domain name for direct access (not recommended for private buckets)"
  value       = aws_s3_bucket.file_sharing.bucket_domain_name
}

# Access logging bucket information (if enabled)
output "access_logs_bucket_name" {
  description = "Name of the S3 access logs bucket (if access logging is enabled)"
  value       = var.enable_access_logging ? aws_s3_bucket.access_logs[0].bucket : null
}

output "access_logs_bucket_arn" {
  description = "ARN of the S3 access logs bucket (if access logging is enabled)"
  value       = var.enable_access_logging ? aws_s3_bucket.access_logs[0].arn : null
}

# IAM role information for presigned URL generation
output "presigned_url_generator_role_arn" {
  description = "ARN of the IAM role for generating presigned URLs"
  value       = aws_iam_role.presigned_url_generator.arn
}

output "presigned_url_generator_role_name" {
  description = "Name of the IAM role for generating presigned URLs"
  value       = aws_iam_role.presigned_url_generator.name
}

# CloudTrail information (if enabled)
output "cloudtrail_name" {
  description = "Name of the CloudTrail for S3 access logging (if enabled)"
  value       = var.enable_cloudtrail_logging ? aws_cloudtrail.s3_access[0].name : null
}

output "cloudtrail_arn" {
  description = "ARN of the CloudTrail for S3 access logging (if enabled)"
  value       = var.enable_cloudtrail_logging ? aws_cloudtrail.s3_access[0].arn : null
}

# CloudWatch Log Group information (if enabled)
output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch Log Group for S3 access logs (if enabled)"
  value       = var.enable_cloudtrail_logging ? aws_cloudwatch_log_group.s3_access_logs[0].name : null
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch Log Group for S3 access logs (if enabled)"
  value       = var.enable_cloudtrail_logging ? aws_cloudwatch_log_group.s3_access_logs[0].arn : null
}

# SNS topic information (if notifications are enabled)
output "sns_topic_arn" {
  description = "ARN of the SNS topic for file sharing alerts (if email notifications are enabled)"
  value       = var.notification_email != "" ? aws_sns_topic.file_sharing_alerts[0].arn : null
}

output "sns_topic_name" {
  description = "Name of the SNS topic for file sharing alerts (if email notifications are enabled)"
  value       = var.notification_email != "" ? aws_sns_topic.file_sharing_alerts[0].name : null
}

# Configuration information
output "bucket_versioning_status" {
  description = "Versioning status of the main S3 bucket"
  value       = var.enable_versioning ? "Enabled" : "Suspended"
}

output "bucket_encryption_status" {
  description = "Encryption status of the main S3 bucket"
  value       = var.enable_encryption ? "Enabled" : "Disabled"
}

output "access_logging_status" {
  description = "Access logging status for the main S3 bucket"
  value       = var.enable_access_logging ? "Enabled" : "Disabled"
}

output "cloudtrail_logging_status" {
  description = "CloudTrail logging status for S3 API calls"
  value       = var.enable_cloudtrail_logging ? "Enabled" : "Disabled"
}

# Default configuration values
output "default_presigned_url_expiry_hours" {
  description = "Default expiration time for presigned URLs in hours"
  value       = var.default_presigned_url_expiry
}

output "cors_allowed_origins" {
  description = "List of allowed origins for CORS configuration"
  value       = var.cors_allowed_origins
}

output "cors_allowed_methods" {
  description = "List of allowed HTTP methods for CORS"
  value       = var.cors_allowed_methods
}

# Lifecycle configuration information
output "lifecycle_rules_config" {
  description = "Configuration of S3 lifecycle rules"
  value = {
    documents_transition_enabled = var.lifecycle_rules.enable_documents_transition
    documents_ia_days           = var.lifecycle_rules.documents_ia_days
    documents_glacier_days      = var.lifecycle_rules.documents_glacier_days
    uploads_cleanup_enabled     = var.lifecycle_rules.enable_uploads_cleanup
    uploads_expiry_days         = var.lifecycle_rules.uploads_expiry_days
  }
}

# AWS CLI commands for common operations
output "aws_cli_commands" {
  description = "Useful AWS CLI commands for working with the file sharing bucket"
  value = {
    generate_download_presigned_url = "aws s3 presign s3://${aws_s3_bucket.file_sharing.bucket}/path/to/file --expires-in ${var.default_presigned_url_expiry * 3600}"
    generate_upload_presigned_url   = "aws s3 presign s3://${aws_s3_bucket.file_sharing.bucket}/path/to/file --expires-in ${var.default_presigned_url_expiry * 3600} --http-method PUT"
    list_bucket_contents           = "aws s3 ls s3://${aws_s3_bucket.file_sharing.bucket}/ --recursive"
    upload_file_to_documents       = "aws s3 cp /local/file/path s3://${aws_s3_bucket.file_sharing.bucket}/documents/"
    download_file_from_bucket      = "aws s3 cp s3://${aws_s3_bucket.file_sharing.bucket}/path/to/file /local/download/path"
  }
}

# Security and compliance information
output "security_features" {
  description = "Summary of security features enabled"
  value = {
    public_access_blocked     = "Yes - All public access is blocked"
    encryption_at_rest       = var.enable_encryption ? "Yes - AES256 server-side encryption" : "No"
    versioning              = var.enable_versioning ? "Yes - Object versioning enabled" : "No"
    access_logging          = var.enable_access_logging ? "Yes - S3 access logs enabled" : "No"
    api_logging             = var.enable_cloudtrail_logging ? "Yes - CloudTrail API logging enabled" : "No"
    cors_configured         = "Yes - CORS configured for web access"
    lifecycle_management    = "Yes - Automated lifecycle rules configured"
    iam_role_created        = "Yes - Dedicated IAM role for presigned URL generation"
  }
}

# Cost optimization information
output "cost_optimization_features" {
  description = "Summary of cost optimization features"
  value = {
    storage_class_transitions = var.lifecycle_rules.enable_documents_transition ? "Yes - Auto-transition to IA and Glacier" : "No"
    upload_cleanup           = var.lifecycle_rules.enable_uploads_cleanup ? "Yes - Auto-cleanup of uploads folder" : "No"
    multipart_upload_cleanup = "Yes - Incomplete multipart uploads cleaned up after 1 day"
    versioning_transitions   = var.enable_versioning ? "Yes - Old versions transition to cheaper storage" : "No"
  }
}

# Monitoring and alerting information
output "monitoring_features" {
  description = "Summary of monitoring and alerting features"
  value = {
    cloudwatch_metrics     = "Yes - Standard S3 CloudWatch metrics available"
    cloudtrail_logging     = var.enable_cloudtrail_logging ? "Yes - S3 API calls logged to CloudTrail" : "No"
    access_logging         = var.enable_access_logging ? "Yes - S3 access logs to separate bucket" : "No"
    email_notifications    = var.notification_email != "" ? "Yes - Email alerts configured" : "No"
    metric_alarms          = var.notification_email != "" ? "Yes - CloudWatch alarms for unusual activity" : "No"
  }
}

# Quick start guide
output "quick_start_guide" {
  description = "Quick start guide for using the file sharing solution"
  value = {
    step_1 = "Upload files to s3://${aws_s3_bucket.file_sharing.bucket}/documents/ using the AWS CLI or console"
    step_2 = "Generate presigned download URLs using: aws s3 presign s3://${aws_s3_bucket.file_sharing.bucket}/documents/filename --expires-in 3600"
    step_3 = "Share the generated URL with recipients (valid for ${var.default_presigned_url_expiry} hours by default)"
    step_4 = "For uploads, generate presigned PUT URLs using: aws s3 presign s3://${aws_s3_bucket.file_sharing.bucket}/uploads/filename --expires-in 1800 --http-method PUT"
    step_5 = "Monitor access through ${var.enable_access_logging ? "S3 access logs and " : ""}${var.enable_cloudtrail_logging ? "CloudTrail logs" : "CloudWatch metrics"}"
  }
}