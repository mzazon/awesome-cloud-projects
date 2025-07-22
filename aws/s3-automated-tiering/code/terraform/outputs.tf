# Output Values for S3 Intelligent Tiering Infrastructure
# These outputs provide important information about the created resources

# Basic bucket information
output "bucket_name" {
  description = "Name of the S3 bucket with Intelligent Tiering enabled"
  value       = aws_s3_bucket.main.id
}

output "bucket_arn" {
  description = "ARN of the S3 bucket"
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
  description = "Route 53 Hosted Zone ID for the S3 bucket"
  value       = aws_s3_bucket.main.hosted_zone_id
}

# Access logs bucket information (if enabled)
output "access_logs_bucket_name" {
  description = "Name of the access logs bucket (if access logging is enabled)"
  value       = var.enable_access_logging ? aws_s3_bucket.access_logs[0].id : null
}

output "access_logs_bucket_arn" {
  description = "ARN of the access logs bucket (if access logging is enabled)"
  value       = var.enable_access_logging ? aws_s3_bucket.access_logs[0].arn : null
}

# Configuration details
output "intelligent_tiering_configuration_name" {
  description = "Name of the Intelligent Tiering configuration"
  value       = aws_s3_bucket_intelligent_tiering_configuration.main.name
}

output "intelligent_tiering_status" {
  description = "Status of the Intelligent Tiering configuration"
  value       = aws_s3_bucket_intelligent_tiering_configuration.main.status
}

output "intelligent_tiering_archive_days" {
  description = "Number of days before objects move to Archive Access tier"
  value       = var.intelligent_tiering_archive_days
}

output "intelligent_tiering_deep_archive_days" {
  description = "Number of days before objects move to Deep Archive Access tier"
  value       = var.intelligent_tiering_deep_archive_days
}

# Versioning and security configuration
output "versioning_status" {
  description = "Versioning status of the S3 bucket"
  value       = aws_s3_bucket_versioning.main.versioning_configuration[0].status
}

output "mfa_delete_enabled" {
  description = "Whether MFA delete is enabled for the bucket"
  value       = aws_s3_bucket_versioning.main.versioning_configuration[0].mfa_delete == "Enabled"
}

output "encryption_enabled" {
  description = "Whether server-side encryption is enabled"
  value       = true
}

output "public_access_blocked" {
  description = "Whether public access is blocked for the bucket"
  value       = aws_s3_bucket_public_access_block.main.block_public_acls
}

# Object Lock configuration (if enabled)
output "object_lock_enabled" {
  description = "Whether Object Lock is enabled for the bucket"
  value       = var.enable_object_lock
}

output "object_lock_mode" {
  description = "Object Lock mode (if enabled)"
  value       = var.enable_object_lock ? var.object_lock_mode : null
}

output "object_lock_retention_years" {
  description = "Default Object Lock retention period in years (if enabled)"
  value       = var.enable_object_lock ? var.object_lock_retention_years : null
}

# CloudWatch monitoring
output "cloudwatch_dashboard_name" {
  description = "Name of the CloudWatch dashboard (if enabled)"
  value       = var.enable_cloudwatch_dashboard ? aws_cloudwatch_dashboard.storage_optimization[0].dashboard_name : null
}

output "cloudwatch_dashboard_url" {
  description = "URL to access the CloudWatch dashboard (if enabled)"
  value = var.enable_cloudwatch_dashboard ? "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.storage_optimization[0].dashboard_name}" : null
}

# Sample objects for demonstration
output "sample_objects" {
  description = "List of sample objects created for demonstration"
  value = {
    frequent_data = aws_s3_object.sample_frequent.key
    archive_data  = aws_s3_object.sample_archive.key
    large_sample  = aws_s3_object.sample_large.key
  }
}

# Cost optimization information
output "cost_optimization_features" {
  description = "Summary of enabled cost optimization features"
  value = {
    intelligent_tiering_enabled = true
    lifecycle_policies_enabled  = true
    versioning_enabled          = var.enable_versioning
    access_logging_enabled      = var.enable_access_logging
    cloudwatch_monitoring       = var.enable_cloudwatch_dashboard
    object_lock_enabled         = var.enable_object_lock
  }
}

# Lifecycle policy configuration
output "lifecycle_policy_rules" {
  description = "Summary of lifecycle policy configuration"
  value = {
    transition_to_intelligent_tiering_days = var.lifecycle_transition_to_intelligent_tiering_days
    abort_incomplete_multipart_days        = var.lifecycle_abort_incomplete_multipart_days
    noncurrent_version_ia_transition_days  = var.noncurrent_version_transition_ia_days
    noncurrent_version_glacier_transition_days = var.noncurrent_version_transition_glacier_days
    noncurrent_version_expiration_days     = var.noncurrent_version_expiration_days
  }
}

# CLI commands for validation and testing
output "validation_commands" {
  description = "AWS CLI commands to validate the configuration"
  value = {
    check_intelligent_tiering = "aws s3api get-bucket-intelligent-tiering-configuration --bucket ${aws_s3_bucket.main.id} --id EntireBucketConfig"
    check_lifecycle_policy    = "aws s3api get-bucket-lifecycle-configuration --bucket ${aws_s3_bucket.main.id}"
    check_versioning         = "aws s3api get-bucket-versioning --bucket ${aws_s3_bucket.main.id}"
    list_objects             = "aws s3 ls s3://${aws_s3_bucket.main.id} --recursive"
    check_metrics            = "aws s3api get-bucket-metrics-configuration --bucket ${aws_s3_bucket.main.id} --id EntireBucket"
  }
}

# Cleanup commands
output "cleanup_commands" {
  description = "Commands to clean up resources manually if needed"
  value = {
    delete_objects = "aws s3 rm s3://${aws_s3_bucket.main.id} --recursive"
    delete_versions = "aws s3api delete-objects --bucket ${aws_s3_bucket.main.id} --delete \"$(aws s3api list-object-versions --bucket ${aws_s3_bucket.main.id} --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}')\""
    terraform_destroy = "terraform destroy"
  }
}

# Resource identifiers for integration
output "resource_identifiers" {
  description = "Resource identifiers for integration with other systems"
  value = {
    bucket_name    = aws_s3_bucket.main.id
    bucket_arn     = aws_s3_bucket.main.arn
    aws_region     = var.aws_region
    aws_account_id = data.aws_caller_identity.current.account_id
    random_suffix  = random_id.bucket_suffix.hex
  }
}

# Tags applied to resources
output "applied_tags" {
  description = "Tags applied to the S3 bucket and related resources"
  value       = local.common_tags
}