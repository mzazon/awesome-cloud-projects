# AWS Transfer Family Web Apps - Terraform Outputs
# This file defines all outputs from the Simple File Sharing infrastructure

# =============================================================================
# S3 Storage Outputs
# =============================================================================

output "s3_bucket_name" {
  description = "Name of the S3 bucket used for file storage"
  value       = aws_s3_bucket.file_sharing.bucket
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket used for file storage"
  value       = aws_s3_bucket.file_sharing.arn
}

output "s3_bucket_domain_name" {
  description = "Domain name of the S3 bucket"
  value       = aws_s3_bucket.file_sharing.bucket_domain_name
}

output "s3_bucket_regional_domain_name" {
  description = "Regional domain name of the S3 bucket"
  value       = aws_s3_bucket.file_sharing.bucket_regional_domain_name
}

output "s3_bucket_website_endpoint" {
  description = "Website endpoint of the S3 bucket"
  value       = aws_s3_bucket.file_sharing.website_endpoint
}

# =============================================================================
# IAM Identity Center Outputs
# =============================================================================

output "identity_center_arn" {
  description = "ARN of the IAM Identity Center instance"
  value       = local.identity_center_arn
}

output "identity_store_id" {
  description = "Identity Store ID from IAM Identity Center"
  value       = local.identity_store_id
}

output "demo_user_ids" {
  description = "Map of demo user names to their Identity Store user IDs"
  value = {
    for user_key, user in aws_identitystore_user.demo_users : user_key => user.user_id
  }
  sensitive = false
}

output "demo_group_ids" {
  description = "Map of demo group names to their Identity Store group IDs"
  value = {
    for group_key, group in aws_identitystore_group.demo_groups : group_key => group.group_id
  }
  sensitive = false
}

# =============================================================================
# S3 Access Grants Outputs
# =============================================================================

output "access_grants_instance_arn" {
  description = "ARN of the S3 Access Grants instance"
  value       = aws_s3control_access_grants_instance.main.access_grants_instance_arn
}

output "access_grants_instance_id" {
  description = "ID of the S3 Access Grants instance"
  value       = aws_s3control_access_grants_instance.main.access_grants_instance_id
}

output "access_grants_location_id" {
  description = "ID of the S3 Access Grants location"
  value       = aws_s3control_access_grants_location.file_sharing.access_grants_location_id
}

output "access_grants_location_arn" {
  description = "ARN of the S3 Access Grants location"
  value       = aws_s3control_access_grants_location.file_sharing.access_grants_location_arn
}

output "user_access_grant_ids" {
  description = "Map of user access grant names to their IDs"
  value = {
    for grant_key, grant in aws_s3control_access_grant.user_grants : grant_key => grant.access_grant_id
  }
  sensitive = false
}

output "group_access_grant_ids" {
  description = "Map of group access grant names to their IDs"
  value = {
    for grant_key, grant in aws_s3control_access_grant.group_grants : grant_key => grant.access_grant_id
  }
  sensitive = false
}

# =============================================================================
# IAM Role Outputs
# =============================================================================

output "access_grants_location_role_arn" {
  description = "ARN of the IAM role used by S3 Access Grants location"
  value       = aws_iam_role.access_grants_location.arn
}

output "transfer_web_app_role_arn" {
  description = "ARN of the IAM role for Transfer Family Web App integration"
  value       = aws_iam_role.transfer_web_app.arn
}

# =============================================================================
# CloudWatch Logging Outputs
# =============================================================================

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for file sharing activities"
  value       = var.enable_cloudwatch_logging ? aws_cloudwatch_log_group.file_sharing[0].name : null
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group for file sharing activities"
  value       = var.enable_cloudwatch_logging ? aws_cloudwatch_log_group.file_sharing[0].arn : null
}

# =============================================================================
# CloudTrail Outputs
# =============================================================================

output "cloudtrail_arn" {
  description = "ARN of the CloudTrail for auditing file sharing activities"
  value       = var.enable_cloudtrail ? aws_cloudtrail.file_sharing[0].arn : null
}

output "cloudtrail_home_region" {
  description = "Home region of the CloudTrail"
  value       = var.enable_cloudtrail ? aws_cloudtrail.file_sharing[0].home_region : null
}

# =============================================================================
# Resource Naming Outputs
# =============================================================================

output "resource_name_suffix" {
  description = "Random suffix used for unique resource naming"
  value       = random_id.suffix.hex
}

output "common_tags" {
  description = "Common tags applied to all resources"
  value       = local.common_tags
}

# =============================================================================
# Configuration Summary Outputs
# =============================================================================

output "deployment_summary" {
  description = "Summary of the deployed Simple File Sharing infrastructure"
  value = {
    environment                    = var.environment
    region                        = data.aws_region.current.name
    bucket_name                   = aws_s3_bucket.file_sharing.bucket
    versioning_enabled            = var.enable_s3_versioning
    encryption_enabled            = var.enable_bucket_encryption
    lifecycle_rules_enabled       = var.lifecycle_rules_enabled
    intelligent_tiering_enabled   = var.enable_intelligent_tiering
    cloudwatch_logging_enabled    = var.enable_cloudwatch_logging
    cloudtrail_enabled           = var.enable_cloudtrail
    demo_users_count             = length(var.demo_users)
    demo_groups_count            = length(var.demo_groups)
    user_access_grants_count     = length(var.user_access_grants)
    group_access_grants_count    = length(var.group_access_grants)
  }
}

# =============================================================================
# Next Steps Output
# =============================================================================

output "manual_configuration_required" {
  description = "Manual configuration steps required after Terraform deployment"
  value = {
    message = "Transfer Family Web App must be created manually until Terraform support is available"
    cli_commands = [
      "aws transfer create-web-app --identity-provider-details '{\"IdentityCenterConfig\":{\"InstanceArn\":\"${local.identity_center_arn}\",\"Role\":\"${aws_iam_role.transfer_web_app.arn}\"}}'",
      "aws transfer create-web-app-assignment --web-app-id <WEB_APP_ID> --grantee '{\"Type\":\"USER\",\"Identifier\":\"${join("\",\"", [for user in aws_identitystore_user.demo_users : user.user_id])}\"}'",
      "Configure CORS policy for S3 bucket: ${aws_s3_bucket.file_sharing.bucket}",
    ]
    documentation = [
      "https://docs.aws.amazon.com/transfer/latest/userguide/web-app.html",
      "https://docs.aws.amazon.com/transfer/latest/userguide/web-app-tutorial.html",
      "https://docs.aws.amazon.com/AmazonS3/latest/userguide/access-grants.html"
    ]
  }
}

# =============================================================================
# Cost Estimation Output
# =============================================================================

output "estimated_monthly_costs" {
  description = "Estimated monthly costs for the deployed resources (USD)"
  value = {
    s3_storage_standard_gb    = "~$0.023 per GB/month"
    s3_requests_per_1000      = "~$0.0004 per 1,000 requests"
    access_grants_instance    = "No additional cost"
    identity_center_users     = "Free for first 50 users"
    cloudwatch_logs_gb        = "~$0.50 per GB ingested"
    cloudtrail_events         = "First 250,000 management events/month free"
    transfer_web_app_units    = "~$0.30 per web app unit per month"
    data_transfer_gb          = "~$0.09 per GB out to internet"
    note                      = "Actual costs depend on usage patterns and data volume"
  }
}

# =============================================================================
# Security and Compliance Outputs
# =============================================================================

output "security_features_enabled" {
  description = "Security features enabled in the deployment"
  value = {
    s3_bucket_encryption          = var.enable_bucket_encryption
    s3_public_access_blocked      = var.enable_bucket_public_access_block
    s3_versioning_enabled         = var.enable_s3_versioning
    iam_identity_center_sso       = true
    s3_access_grants_enabled      = true
    cloudtrail_audit_logging      = var.enable_cloudtrail
    cloudwatch_monitoring         = var.enable_cloudwatch_logging
    data_classification           = var.data_classification
  }
}