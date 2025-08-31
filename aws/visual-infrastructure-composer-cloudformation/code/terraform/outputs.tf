# =============================================================================
# Output Values for Visual Infrastructure Composer Demo
# =============================================================================
# This file defines outputs that provide useful information about the created
# resources, allowing users to access and interact with the deployed infrastructure.

# =============================================================================
# Core Infrastructure Outputs
# =============================================================================

output "bucket_name" {
  description = "The name of the S3 bucket created for static website hosting"
  value       = aws_s3_bucket.website.bucket
}

output "bucket_arn" {
  description = "The ARN of the S3 bucket created for static website hosting"
  value       = aws_s3_bucket.website.arn
}

output "bucket_id" {
  description = "The ID of the S3 bucket (same as bucket name)"
  value       = aws_s3_bucket.website.id
}

output "bucket_domain_name" {
  description = "The domain name of the S3 bucket"
  value       = aws_s3_bucket.website.bucket_domain_name
}

output "bucket_regional_domain_name" {
  description = "The regional domain name of the S3 bucket"
  value       = aws_s3_bucket.website.bucket_regional_domain_name
}

# =============================================================================
# Website Configuration Outputs
# =============================================================================

output "website_url" {
  description = "The URL of the static website hosted on S3"
  value       = local.website_url
}

output "website_domain" {
  description = "The website domain for the S3 static website"
  value       = aws_s3_bucket_website_configuration.website.website_domain
}

output "website_endpoint" {
  description = "The website endpoint for the S3 static website"
  value       = aws_s3_bucket_website_configuration.website.website_endpoint
}

output "index_document" {
  description = "The index document configured for the website"
  value       = var.index_document
}

output "error_document" {
  description = "The error document configured for the website"
  value       = var.error_document
}

# =============================================================================
# Security and Access Outputs
# =============================================================================

output "bucket_policy" {
  description = "The bucket policy JSON document applied to the S3 bucket"
  value       = aws_s3_bucket_policy.website.policy
  sensitive   = true
}

output "public_access_block_configuration" {
  description = "The public access block configuration for the S3 bucket"
  value = {
    block_public_acls       = aws_s3_bucket_public_access_block.website.block_public_acls
    block_public_policy     = aws_s3_bucket_public_access_block.website.block_public_policy
    ignore_public_acls      = aws_s3_bucket_public_access_block.website.ignore_public_acls
    restrict_public_buckets = aws_s3_bucket_public_access_block.website.restrict_public_buckets
  }
}

# =============================================================================
# Monitoring and Alerting Outputs
# =============================================================================

output "cloudwatch_alarms" {
  description = "Information about created CloudWatch alarms (if monitoring is enabled)"
  value = var.enable_monitoring ? {
    bucket_size_alarm_name = aws_cloudwatch_metric_alarm.bucket_size[0].alarm_name
    bucket_size_alarm_arn  = aws_cloudwatch_metric_alarm.bucket_size[0].arn
    object_count_alarm_name = aws_cloudwatch_metric_alarm.object_count[0].alarm_name
    object_count_alarm_arn  = aws_cloudwatch_metric_alarm.object_count[0].arn
  } : null
}

# =============================================================================
# Content and File Outputs
# =============================================================================

output "uploaded_files" {
  description = "Information about uploaded sample content files"
  value = var.upload_sample_content ? {
    index_file = {
      key          = aws_s3_object.index[0].key
      etag         = aws_s3_object.index[0].etag
      content_type = aws_s3_object.index[0].content_type
      size         = aws_s3_object.index[0].source_hash
    }
    error_file = {
      key          = aws_s3_object.error[0].key
      etag         = aws_s3_object.error[0].etag
      content_type = aws_s3_object.error[0].content_type
      size         = aws_s3_object.error[0].source_hash
    }
  } : null
}

# =============================================================================
# Infrastructure Metadata Outputs
# =============================================================================

output "region" {
  description = "The AWS region where the infrastructure was deployed"
  value       = data.aws_region.current.name
}

output "account_id" {
  description = "The AWS account ID where the infrastructure was deployed"
  value       = data.aws_caller_identity.current.account_id
}

output "random_suffix" {
  description = "The random suffix used for resource naming"
  value       = random_string.suffix.result
}

output "environment" {
  description = "The environment name used for resource tagging"
  value       = var.environment
}

output "tags" {
  description = "The common tags applied to all resources"
  value       = local.common_tags
}

# =============================================================================
# Terraform State Outputs
# =============================================================================

output "terraform_workspace" {
  description = "The Terraform workspace used for this deployment"
  value       = terraform.workspace
}

# =============================================================================
# CLI Commands for Testing
# =============================================================================

output "test_commands" {
  description = "Useful CLI commands for testing and interacting with the deployed infrastructure"
  value = {
    # Command to test website accessibility
    curl_test_index = "curl -I ${local.website_url}"
    curl_test_404   = "curl -I ${local.website_url}/nonexistent"
    
    # Command to list bucket contents
    s3_list_objects = "aws s3 ls s3://${aws_s3_bucket.website.bucket}/"
    
    # Command to get bucket website configuration
    s3_get_website_config = "aws s3api get-bucket-website --bucket ${aws_s3_bucket.website.bucket}"
    
    # Command to sync local content to bucket
    s3_sync_content = "aws s3 sync ./website-content s3://${aws_s3_bucket.website.bucket}/ --delete"
    
    # Command to check bucket policy
    s3_get_bucket_policy = "aws s3api get-bucket-policy --bucket ${aws_s3_bucket.website.bucket}"
  }
}

# =============================================================================
# Quick Start Guide Output
# =============================================================================

output "quick_start_guide" {
  description = "Quick start guide for using the deployed infrastructure"
  value = {
    website_url = local.website_url
    steps = [
      "1. Visit the website URL: ${local.website_url}",
      "2. Upload your own content: aws s3 cp index.html s3://${aws_s3_bucket.website.bucket}/",
      "3. Test 404 page: ${local.website_url}/nonexistent",
      "4. Monitor in CloudWatch (if enabled): AWS Console > CloudWatch > Alarms",
      "5. Clean up: terraform destroy"
    ]
    notes = [
      "- The website serves content from the S3 bucket",
      "- Public read access is enabled via bucket policy",
      "- All resources are tagged with environment: ${var.environment}",
      "- Use 'terraform destroy' to remove all resources when done"
    ]
  }
}

# =============================================================================
# Security Considerations Output
# =============================================================================

output "security_notes" {
  description = "Important security considerations for the deployed infrastructure"
  value = {
    public_access = "The S3 bucket allows public read access for website content"
    encryption    = "Server-side encryption (AES256) is enabled for the bucket"
    versioning    = var.enable_versioning ? "Versioning is enabled" : "Versioning is disabled"
    monitoring    = var.enable_monitoring ? "CloudWatch monitoring is enabled" : "CloudWatch monitoring is disabled"
    recommendations = [
      "Consider enabling CloudFront for better performance and HTTPS",
      "Implement proper logging and monitoring for production use",
      "Use CloudFormation or Terraform state locking for team environments",
      "Regularly review and rotate any credentials used for deployment"
    ]
  }
}