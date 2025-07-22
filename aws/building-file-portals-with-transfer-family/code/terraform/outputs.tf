# ==========================================================================
# TERRAFORM OUTPUTS - AWS Transfer Family Web App File Portal
# ==========================================================================
# This file defines all output values that provide essential information
# about the deployed infrastructure, including access URLs, resource IDs,
# and configuration details needed for verification and integration.

# ==========================================================================
# WEB APP ACCESS INFORMATION
# ==========================================================================

output "web_app_access_url" {
  description = "URL to access the Transfer Family Web App portal"
  value       = "https://${aws_transfer_web_app.main.access_endpoint}"
  sensitive   = false
}

output "web_app_id" {
  description = "ID of the Transfer Family Web App"
  value       = aws_transfer_web_app.main.web_app_id
  sensitive   = false
}

output "web_app_access_endpoint" {
  description = "Access endpoint domain name for the web app"
  value       = aws_transfer_web_app.main.access_endpoint
  sensitive   = false
}

output "web_app_arn" {
  description = "ARN of the Transfer Family Web App"
  value       = aws_transfer_web_app.main.arn
  sensitive   = false
}

output "web_app_units" {
  description = "Number of web app units configured"
  value       = aws_transfer_web_app.main.web_app_units
  sensitive   = false
}

# ==========================================================================
# S3 BUCKET INFORMATION
# ==========================================================================

output "s3_bucket_name" {
  description = "Name of the S3 bucket used for file storage"
  value       = aws_s3_bucket.file_portal.bucket
  sensitive   = false
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket used for file storage"
  value       = aws_s3_bucket.file_portal.arn
  sensitive   = false
}

output "s3_bucket_domain_name" {
  description = "Domain name of the S3 bucket"
  value       = aws_s3_bucket.file_portal.bucket_domain_name
  sensitive   = false
}

output "s3_bucket_regional_domain_name" {
  description = "Regional domain name of the S3 bucket"
  value       = aws_s3_bucket.file_portal.bucket_regional_domain_name
  sensitive   = false
}

output "s3_bucket_region" {
  description = "AWS region where the S3 bucket is located"
  value       = aws_s3_bucket.file_portal.region
  sensitive   = false
}

# ==========================================================================
# IAM IDENTITY CENTER INFORMATION
# ==========================================================================

output "identity_center_instance_arn" {
  description = "ARN of the IAM Identity Center instance"
  value       = local.identity_center_instance_arn
  sensitive   = false
}

output "identity_center_identity_store_id" {
  description = "Identity Store ID of the IAM Identity Center instance"
  value       = local.identity_center_identity_store_id
  sensitive   = false
}

output "test_user_id" {
  description = "User ID of the created test user (if created)"
  value       = var.create_identity_center_user ? aws_identitystore_user.portal_user[0].user_id : null
  sensitive   = false
}

output "test_user_name" {
  description = "Username of the created test user (if created)"
  value       = var.create_identity_center_user ? aws_identitystore_user.portal_user[0].user_name : null
  sensitive   = false
}

# ==========================================================================
# S3 ACCESS GRANTS INFORMATION
# ==========================================================================

output "access_grants_instance_arn" {
  description = "ARN of the S3 Access Grants instance"
  value       = aws_s3control_access_grants_instance.main.access_grants_instance_arn
  sensitive   = false
}

output "access_grants_instance_id" {
  description = "ID of the S3 Access Grants instance"
  value       = aws_s3control_access_grants_instance.main.access_grants_instance_id
  sensitive   = false
}

output "access_grants_location_id" {
  description = "ID of the S3 Access Grants location"
  value       = aws_s3control_access_grants_location.main.access_grants_location_id
  sensitive   = false
}

output "access_grants_location_scope" {
  description = "Scope of the S3 Access Grants location"
  value       = aws_s3control_access_grants_location.main.location_scope
  sensitive   = false
}

output "access_grant_id" {
  description = "ID of the access grant for the test user (if created)"
  value       = var.create_identity_center_user ? aws_s3control_access_grant.portal_user[0].access_grant_id : null
  sensitive   = false
}

# ==========================================================================
# IAM ROLES INFORMATION
# ==========================================================================

output "transfer_family_role_arn" {
  description = "ARN of the IAM role used by Transfer Family Web App"
  value       = aws_iam_role.transfer_family_web_app.arn
  sensitive   = false
}

output "transfer_family_role_name" {
  description = "Name of the IAM role used by Transfer Family Web App"
  value       = aws_iam_role.transfer_family_web_app.name
  sensitive   = false
}

output "s3_access_grants_role_arn" {
  description = "ARN of the IAM role used by S3 Access Grants location"
  value       = aws_iam_role.s3_access_grants_location.arn
  sensitive   = false
}

output "s3_access_grants_role_name" {
  description = "Name of the IAM role used by S3 Access Grants location"
  value       = aws_iam_role.s3_access_grants_location.name
  sensitive   = false
}

# ==========================================================================
# MONITORING AND LOGGING INFORMATION
# ==========================================================================

output "transfer_family_log_group_name" {
  description = "Name of the CloudWatch Log Group for Transfer Family"
  value       = aws_cloudwatch_log_group.transfer_family.name
  sensitive   = false
}

output "transfer_family_log_group_arn" {
  description = "ARN of the CloudWatch Log Group for Transfer Family"
  value       = aws_cloudwatch_log_group.transfer_family.arn
  sensitive   = false
}

output "s3_access_log_group_name" {
  description = "Name of the CloudWatch Log Group for S3 access logs"
  value       = aws_cloudwatch_log_group.s3_access.name
  sensitive   = false
}

output "s3_access_log_group_arn" {
  description = "ARN of the CloudWatch Log Group for S3 access logs"
  value       = aws_cloudwatch_log_group.s3_access.arn
  sensitive   = false
}

output "failed_logins_alarm_arn" {
  description = "ARN of the CloudWatch alarm for failed login attempts"
  value       = aws_cloudwatch_metric_alarm.failed_logins.arn
  sensitive   = false
}

# ==========================================================================
# BACKUP INFORMATION (if enabled)
# ==========================================================================

output "backup_vault_name" {
  description = "Name of the AWS Backup vault (if backup is enabled)"
  value       = var.enable_backup ? aws_backup_vault.file_portal[0].name : null
  sensitive   = false
}

output "backup_vault_arn" {
  description = "ARN of the AWS Backup vault (if backup is enabled)"
  value       = var.enable_backup ? aws_backup_vault.file_portal[0].arn : null
  sensitive   = false
}

output "backup_plan_id" {
  description = "ID of the AWS Backup plan (if backup is enabled)"
  value       = var.enable_backup ? aws_backup_plan.file_portal[0].id : null
  sensitive   = false
}

output "backup_plan_arn" {
  description = "ARN of the AWS Backup plan (if backup is enabled)"
  value       = var.enable_backup ? aws_backup_plan.file_portal[0].arn : null
  sensitive   = false
}

# ==========================================================================
# SECURITY CONFIGURATION INFORMATION
# ==========================================================================

output "s3_encryption_enabled" {
  description = "Whether S3 server-side encryption is enabled"
  value       = var.enable_encryption
  sensitive   = false
}

output "s3_versioning_enabled" {
  description = "Whether S3 versioning is enabled"
  value       = var.enable_s3_versioning
  sensitive   = false
}

output "s3_public_access_blocked" {
  description = "Whether S3 public access is blocked"
  value       = var.enable_public_access_block
  sensitive   = false
}

output "cors_configuration" {
  description = "CORS configuration details for the S3 bucket"
  value = {
    allowed_origins = ["https://${aws_transfer_web_app.main.access_endpoint}"]
    allowed_methods = var.cors_allowed_methods
    max_age_seconds = var.cors_max_age_seconds
  }
  sensitive = false
}

# ==========================================================================
# RESOURCE TAGS INFORMATION
# ==========================================================================

output "common_tags" {
  description = "Common tags applied to all resources"
  value       = local.common_tags
  sensitive   = false
}

output "environment" {
  description = "Environment name for the deployment"
  value       = var.environment
  sensitive   = false
}

output "project_name" {
  description = "Project name for the deployment"
  value       = var.project_name
  sensitive   = false
}

# ==========================================================================
# DEPLOYMENT INFORMATION
# ==========================================================================

output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
  sensitive   = false
}

output "aws_account_id" {
  description = "AWS account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
  sensitive   = false
}

output "random_suffix" {
  description = "Random suffix used for unique resource naming"
  value       = random_id.suffix.hex
  sensitive   = false
}

# ==========================================================================
# VALIDATION COMMANDS
# ==========================================================================

output "validation_commands" {
  description = "Commands to validate the deployment"
  value = {
    check_web_app_status = "aws transfer describe-web-app --web-app-id ${aws_transfer_web_app.main.web_app_id}"
    check_s3_bucket = "aws s3 ls s3://${aws_s3_bucket.file_portal.bucket}"
    check_access_grants = "aws s3control list-access-grants --account-id ${data.aws_caller_identity.current.account_id}"
    check_identity_center_user = var.create_identity_center_user ? "aws identitystore describe-user --identity-store-id ${local.identity_center_identity_store_id} --user-id ${aws_identitystore_user.portal_user[0].user_id}" : "N/A - User creation disabled"
    test_web_app_access = "Open ${aws_transfer_web_app.main.access_endpoint} in a web browser"
  }
  sensitive = false
}

# ==========================================================================
# CLEANUP COMMANDS
# ==========================================================================

output "cleanup_commands" {
  description = "Commands to clean up resources (for manual cleanup if needed)"
  value = {
    empty_s3_bucket = "aws s3 rm s3://${aws_s3_bucket.file_portal.bucket} --recursive"
    delete_web_app = "aws transfer delete-web-app --web-app-id ${aws_transfer_web_app.main.web_app_id}"
    delete_access_grants = "aws s3control delete-access-grants-instance --account-id ${data.aws_caller_identity.current.account_id}"
    terraform_destroy = "terraform destroy -auto-approve"
  }
  sensitive = false
}