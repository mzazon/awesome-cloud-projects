# Output values for the text processing infrastructure
# These outputs provide important information about the created resources

# S3 Bucket Information
output "s3_bucket_name" {
  description = "Name of the S3 bucket created for text processing"
  value       = aws_s3_bucket.text_processing.bucket
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket"
  value       = aws_s3_bucket.text_processing.arn
}

output "s3_bucket_domain_name" {
  description = "S3 bucket domain name for direct access"
  value       = aws_s3_bucket.text_processing.bucket_domain_name
}

output "s3_bucket_region" {
  description = "AWS region where the S3 bucket is located"
  value       = aws_s3_bucket.text_processing.region
}

# CloudShell Access Information
output "cloudshell_access_command" {
  description = "Command to set environment variables in CloudShell"
  value = <<-EOT
    # Run these commands in AWS CloudShell to configure your environment:
    export BUCKET_NAME="${aws_s3_bucket.text_processing.bucket}"
    export AWS_REGION="${data.aws_region.current.name}"
    export AWS_ACCOUNT_ID="${data.aws_caller_identity.current.account_id}"
    
    # Verify bucket access
    aws s3 ls s3://$BUCKET_NAME/
  EOT
}

# Sample Data Information
output "sample_data_location" {
  description = "S3 location of the sample data file (if created)"
  value       = var.create_sample_data ? "s3://${aws_s3_bucket.text_processing.bucket}/input/sample_sales_data.csv" : "No sample data created"
}

# Folder Structure
output "bucket_folder_structure" {
  description = "Created folder structure in the S3 bucket"
  value       = var.folder_structure
}

# IAM Policy Information
output "iam_policy_name" {
  description = "Name of the IAM policy for CloudShell S3 access"
  value       = aws_iam_policy.cloudshell_s3_access.name
}

output "iam_policy_arn" {
  description = "ARN of the IAM policy for CloudShell S3 access"
  value       = aws_iam_policy.cloudshell_s3_access.arn
}

# CloudShell Role Information (if created)
output "cloudshell_role_arn" {
  description = "ARN of the CloudShell role (if created)"
  value       = length(var.allowed_principals) > 0 ? aws_iam_role.cloudshell_text_processing[0].arn : "No role created"
}

output "cloudshell_role_name" {
  description = "Name of the CloudShell role (if created)"
  value       = length(var.allowed_principals) > 0 ? aws_iam_role.cloudshell_text_processing[0].name : "No role created"
}

# Notification Configuration
output "sns_topic_arn" {
  description = "ARN of the SNS topic for S3 notifications (if created)"
  value       = var.notification_email != "" ? aws_sns_topic.s3_notifications[0].arn : "No SNS topic created"
}

output "notification_email" {
  description = "Email address configured for notifications"
  value       = var.notification_email != "" ? var.notification_email : "No email configured"
  sensitive   = true
}

# CloudTrail Information (if enabled)
output "cloudtrail_name" {
  description = "Name of the CloudTrail (if enabled)"
  value       = var.enable_cloudtrail_logging ? aws_cloudtrail.s3_api_logging[0].name : "CloudTrail not enabled"
}

output "cloudtrail_logs_bucket" {
  description = "S3 bucket for CloudTrail logs (if enabled)"
  value       = var.enable_cloudtrail_logging ? aws_s3_bucket.cloudtrail_logs[0].bucket : "CloudTrail not enabled"
}

# CloudWatch Log Group
output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for enhanced monitoring"
  value       = aws_cloudwatch_log_group.text_processing_logs.name
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.text_processing_logs.arn
}

# Resource Tags
output "resource_tags" {
  description = "Common tags applied to all resources"
  value = {
    Project     = "TextProcessingDemo"
    Environment = var.environment
    ManagedBy   = "Terraform"
    Recipe      = "simple-text-processing-cloudshell-s3"
  }
}

# Security Configuration
output "bucket_encryption_enabled" {
  description = "Whether S3 bucket encryption is enabled"
  value       = var.enable_encryption
}

output "bucket_versioning_enabled" {
  description = "Whether S3 bucket versioning is enabled"
  value       = var.enable_versioning
}

output "bucket_public_access_blocked" {
  description = "Confirmation that public access is blocked on the S3 bucket"
  value       = "All public access blocked for security"
}

# Usage Instructions
output "getting_started_instructions" {
  description = "Instructions for getting started with text processing"
  value = <<-EOT
    1. Open AWS CloudShell in the AWS Console
    2. Set environment variables using the cloudshell_access_command output
    3. Download sample data: aws s3 cp s3://${aws_s3_bucket.text_processing.bucket}/input/sample_sales_data.csv .
    4. Process the data using Linux tools (awk, grep, sort, etc.)
    5. Upload results: aws s3 cp processed_file.csv s3://${aws_s3_bucket.text_processing.bucket}/output/
    
    Example processing command:
    awk -F',' 'NR>1 {sales[$2]+=$4} END {for (region in sales) print region ": $" sales[region]}' sample_sales_data.csv
  EOT
}

# Cost Optimization Information
output "cost_optimization_notes" {
  description = "Information about cost optimization features"
  value = <<-EOT
    Cost optimization features enabled:
    - Lifecycle policy: Objects transition to IA after ${var.lifecycle_transition_days} days
    - Lifecycle policy: Objects transition to Glacier after 90 days
    - Incomplete multipart uploads deleted after 7 days
    - Versioning: ${var.enable_versioning ? "Enabled with cleanup of old versions after 90 days" : "Disabled"}
    ${var.lifecycle_expiration_days > 0 ? "- Objects expire after ${var.lifecycle_expiration_days} days" : "- No expiration policy set"}
  EOT
}