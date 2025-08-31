# Outputs for Simple Infrastructure Templates with CloudFormation and S3
# These outputs provide essential information about the created resources
# for integration with other systems, monitoring, and verification

# Primary S3 Bucket Information
output "bucket_name" {
  description = "Name of the created S3 bucket"
  value       = aws_s3_bucket.main.id
}

output "bucket_arn" {
  description = "ARN of the created S3 bucket"
  value       = aws_s3_bucket.main.arn
}

output "bucket_domain_name" {
  description = "Domain name of the S3 bucket"
  value       = aws_s3_bucket.main.bucket_domain_name
}

output "bucket_regional_domain_name" {
  description = "Regional domain name of the S3 bucket"
  value       = aws_s3_bucket.main.bucket_regional_domain_name
}

output "bucket_hosted_zone_id" {
  description = "Route 53 Hosted Zone ID for the S3 bucket's region"
  value       = aws_s3_bucket.main.hosted_zone_id
}

output "bucket_region" {
  description = "AWS region where the S3 bucket was created"
  value       = aws_s3_bucket.main.region
}

# Bucket Configuration Details
output "bucket_versioning_status" {
  description = "Versioning status of the S3 bucket"
  value       = var.enable_versioning ? "Enabled" : "Suspended"
}

output "bucket_encryption_status" {
  description = "Server-side encryption status of the S3 bucket"
  value       = var.enable_encryption ? "Enabled" : "Disabled"
}

output "bucket_encryption_algorithm" {
  description = "Server-side encryption algorithm used by the S3 bucket"
  value       = var.enable_encryption ? var.encryption_algorithm : "None"
}

output "bucket_public_access_blocked" {
  description = "Public access block status for the S3 bucket"
  value = {
    block_public_acls       = var.block_public_access.block_public_acls
    block_public_policy     = var.block_public_access.block_public_policy
    ignore_public_acls      = var.block_public_access.ignore_public_acls
    restrict_public_buckets = var.block_public_access.restrict_public_buckets
  }
}

# Access Logging Information (conditional outputs)
output "access_logging_enabled" {
  description = "Whether access logging is enabled for the S3 bucket"
  value       = var.enable_access_logging
}

output "access_log_bucket_name" {
  description = "Name of the bucket storing access logs (if access logging is enabled)"
  value       = var.enable_access_logging ? local.access_log_bucket_name : null
}

output "access_log_prefix" {
  description = "Prefix used for access log objects"
  value       = var.enable_access_logging ? var.access_log_prefix : null
}

# Lifecycle Policy Information
output "lifecycle_policy_enabled" {
  description = "Whether lifecycle policy is enabled for the S3 bucket"
  value       = var.enable_lifecycle_policy
}

output "lifecycle_transitions" {
  description = "Lifecycle transition configuration for the S3 bucket"
  value = var.enable_lifecycle_policy ? {
    standard_ia_days = var.lifecycle_transition_ia_days
    glacier_days     = var.lifecycle_transition_glacier_days
    expiration_days  = var.lifecycle_expiration_days > 0 ? var.lifecycle_expiration_days : "Never"
  } : null
}

# Object Lock Information
output "object_lock_enabled" {
  description = "Whether Object Lock is enabled for the S3 bucket"
  value       = var.object_lock_enabled
}

output "object_lock_configuration" {
  description = "Object Lock configuration details"
  value = var.object_lock_enabled && var.object_lock_configuration.rule != null ? {
    enabled           = var.object_lock_configuration.object_lock_enabled
    retention_mode    = var.object_lock_configuration.rule.default_retention.mode
    retention_days    = var.object_lock_configuration.rule.default_retention.days
    retention_years   = var.object_lock_configuration.rule.default_retention.years
  } : null
}

# AWS Account and Region Information
output "aws_account_id" {
  description = "AWS Account ID where the resources were created"
  value       = data.aws_caller_identity.current.account_id
}

output "aws_region" {
  description = "AWS Region where the resources were created"
  value       = data.aws_region.current.name
}

# Resource Tags
output "bucket_tags" {
  description = "Tags applied to the S3 bucket"
  value       = aws_s3_bucket.main.tags
}

# Computed Values for Integration
output "bucket_prefix_used" {
  description = "The bucket name prefix that was used"
  value       = var.bucket_name_prefix
}

output "random_suffix" {
  description = "Random suffix appended to bucket name for uniqueness"
  value       = random_string.bucket_suffix.result
}

# Environment Information
output "environment" {
  description = "Environment name used for tagging"
  value       = var.environment
}

# Security Status Summary
output "security_configuration_summary" {
  description = "Summary of security configurations applied to the S3 bucket"
  value = {
    versioning_enabled        = var.enable_versioning
    encryption_enabled        = var.enable_encryption
    encryption_algorithm      = var.enable_encryption ? var.encryption_algorithm : "None"
    bucket_key_enabled        = var.enable_encryption ? var.enable_bucket_key : false
    public_access_blocked     = var.block_public_access.block_public_acls && var.block_public_access.block_public_policy && var.block_public_access.ignore_public_acls && var.block_public_access.restrict_public_buckets
    access_logging_enabled    = var.enable_access_logging
    lifecycle_policy_enabled  = var.enable_lifecycle_policy
    object_lock_enabled       = var.object_lock_enabled
    mfa_delete_enabled        = var.mfa_delete
  }
}

# URLs for AWS Console Access
output "s3_console_url" {
  description = "URL to access the S3 bucket in the AWS Console"
  value       = "https://s3.console.aws.amazon.com/s3/buckets/${aws_s3_bucket.main.id}?region=${data.aws_region.current.name}"
}

# CloudFormation Stack Equivalent Information
# These outputs mirror what would be available from the equivalent CloudFormation stack
output "cloudformation_equivalent_outputs" {
  description = "Outputs that would be equivalent to the CloudFormation template from the recipe"
  value = {
    BucketName = aws_s3_bucket.main.id
    BucketArn  = aws_s3_bucket.main.arn
  }
}

# Validation Helpers
output "validation_commands" {
  description = "AWS CLI commands to validate the bucket configuration (for testing purposes)"
  value = {
    check_bucket_exists    = "aws s3api head-bucket --bucket ${aws_s3_bucket.main.id}"
    get_bucket_location    = "aws s3api get-bucket-location --bucket ${aws_s3_bucket.main.id}"
    get_bucket_encryption  = "aws s3api get-bucket-encryption --bucket ${aws_s3_bucket.main.id}"
    get_bucket_versioning  = "aws s3api get-bucket-versioning --bucket ${aws_s3_bucket.main.id}"
    get_public_access_block = "aws s3api get-public-access-block --bucket ${aws_s3_bucket.main.id}"
    list_bucket_contents   = "aws s3 ls s3://${aws_s3_bucket.main.id}/"
  }
}