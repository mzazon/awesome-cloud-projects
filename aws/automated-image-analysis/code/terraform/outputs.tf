# Outputs for Amazon Rekognition image analysis infrastructure

# S3 Bucket Information
output "s3_bucket_name" {
  description = "Name of the S3 bucket for storing images"
  value       = aws_s3_bucket.images.bucket
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket for storing images"
  value       = aws_s3_bucket.images.arn
}

output "s3_bucket_domain_name" {
  description = "Domain name of the S3 bucket"
  value       = aws_s3_bucket.images.bucket_domain_name
}

output "s3_bucket_regional_domain_name" {
  description = "Regional domain name of the S3 bucket"
  value       = aws_s3_bucket.images.bucket_regional_domain_name
}

output "s3_bucket_region" {
  description = "Region where the S3 bucket is located"
  value       = aws_s3_bucket.images.region
}

# IAM Role Information
output "rekognition_role_arn" {
  description = "ARN of the IAM role for Rekognition operations"
  value       = aws_iam_role.rekognition_analysis_role.arn
}

output "rekognition_role_name" {
  description = "Name of the IAM role for Rekognition operations"
  value       = aws_iam_role.rekognition_analysis_role.name
}

# IAM Policy Information
output "rekognition_policy_arn" {
  description = "ARN of the IAM policy for Rekognition operations"
  value       = aws_iam_policy.rekognition_policy.arn
}

# KMS Key Information (if encryption is enabled)
output "kms_key_id" {
  description = "ID of the KMS key used for S3 encryption"
  value       = var.enable_s3_encryption ? aws_kms_key.s3_encryption[0].key_id : null
}

output "kms_key_arn" {
  description = "ARN of the KMS key used for S3 encryption"
  value       = var.enable_s3_encryption ? aws_kms_key.s3_encryption[0].arn : null
}

output "kms_key_alias" {
  description = "Alias of the KMS key used for S3 encryption"
  value       = var.enable_s3_encryption ? aws_kms_alias.s3_encryption[0].name : null
}

# CloudTrail Information (if enabled)
output "cloudtrail_arn" {
  description = "ARN of the CloudTrail for API logging"
  value       = var.enable_cloudtrail_logging ? aws_cloudtrail.rekognition_trail[0].arn : null
}

output "cloudtrail_logs_bucket" {
  description = "Name of the S3 bucket for CloudTrail logs"
  value       = var.enable_cloudtrail_logging ? aws_s3_bucket.cloudtrail_logs[0].bucket : null
}

# AWS Account and Region Information
output "aws_account_id" {
  description = "AWS account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

# Resource Configuration Summary
output "resource_summary" {
  description = "Summary of deployed resources and their configuration"
  value = {
    s3_bucket = {
      name                = aws_s3_bucket.images.bucket
      versioning_enabled  = var.s3_versioning_enabled
      encryption_enabled  = var.enable_s3_encryption
      lifecycle_enabled   = var.s3_lifecycle_enabled
      public_access_block = var.enable_s3_public_access_block
    }
    iam_role = {
      name = aws_iam_role.rekognition_analysis_role.name
      arn  = aws_iam_role.rekognition_analysis_role.arn
    }
    security = {
      kms_encryption     = var.enable_s3_encryption
      cloudtrail_logging = var.enable_cloudtrail_logging
    }
    environment = var.environment
    project     = var.project_name
  }
}

# CLI Commands for Testing
output "sample_cli_commands" {
  description = "Sample AWS CLI commands for testing the infrastructure"
  value = {
    upload_image = "aws s3 cp /path/to/image.jpg s3://${aws_s3_bucket.images.bucket}/images/"
    list_images = "aws s3 ls s3://${aws_s3_bucket.images.bucket}/images/"
    detect_labels = "aws rekognition detect-labels --image '{\"S3Object\":{\"Bucket\":\"${aws_s3_bucket.images.bucket}\",\"Name\":\"images/image.jpg\"}}'"
    detect_text = "aws rekognition detect-text --image '{\"S3Object\":{\"Bucket\":\"${aws_s3_bucket.images.bucket}\",\"Name\":\"images/image.jpg\"}}'"
    detect_moderation = "aws rekognition detect-moderation-labels --image '{\"S3Object\":{\"Bucket\":\"${aws_s3_bucket.images.bucket}\",\"Name\":\"images/image.jpg\"}}'"
    assume_role = "aws sts assume-role --role-arn ${aws_iam_role.rekognition_analysis_role.arn} --role-session-name rekognition-session --external-id ${var.project_name}-external-id"
  }
}

# Environment Variables for Scripts
output "environment_variables" {
  description = "Environment variables to set for using this infrastructure"
  value = {
    BUCKET_NAME    = aws_s3_bucket.images.bucket
    AWS_REGION     = data.aws_region.current.name
    AWS_ACCOUNT_ID = data.aws_caller_identity.current.account_id
    IAM_ROLE_ARN   = aws_iam_role.rekognition_analysis_role.arn
    PROJECT_NAME   = var.project_name
    ENVIRONMENT    = var.environment
  }
}

# Cost Optimization Information
output "cost_optimization_tips" {
  description = "Tips for optimizing costs with this infrastructure"
  value = {
    s3_storage_classes = "Images automatically transition to IA after ${var.s3_lifecycle_transition_days} days and Glacier after 90 days"
    rekognition_pricing = "Amazon Rekognition charges $1 per 1,000 images processed"
    free_tier = "Free tier includes 5,000 images per month for first 12 months"
    cleanup_recommendation = "Regularly clean up old images and analysis results to minimize storage costs"
    kms_costs = var.enable_s3_encryption ? "KMS key usage incurs additional charges for encryption/decryption operations" : "KMS encryption is disabled"
  }
}

# Security Configuration Status
output "security_status" {
  description = "Security configuration status of the deployed infrastructure"
  value = {
    s3_encryption = var.enable_s3_encryption ? "Enabled with KMS" : "Disabled"
    s3_public_access_block = var.enable_s3_public_access_block ? "Enabled" : "Disabled"
    iam_least_privilege = "Enabled - IAM policies follow least privilege principle"
    cloudtrail_logging = var.enable_cloudtrail_logging ? "Enabled" : "Disabled"
    s3_versioning = var.s3_versioning_enabled ? "Enabled" : "Disabled"
    lifecycle_management = var.s3_lifecycle_enabled ? "Enabled" : "Disabled"
  }
}