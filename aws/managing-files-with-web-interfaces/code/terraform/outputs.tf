# Outputs for AWS Transfer Family Web Apps self-service file management infrastructure

#------------------------------------------------------------------------------
# S3 BUCKET OUTPUTS
#------------------------------------------------------------------------------

output "s3_bucket_name" {
  description = "Name of the S3 bucket for file storage"
  value       = aws_s3_bucket.file_storage.id
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket for file storage"
  value       = aws_s3_bucket.file_storage.arn
}

output "s3_bucket_domain_name" {
  description = "Domain name of the S3 bucket"
  value       = aws_s3_bucket.file_storage.bucket_domain_name
}

output "s3_bucket_regional_domain_name" {
  description = "Regional domain name of the S3 bucket"
  value       = aws_s3_bucket.file_storage.bucket_regional_domain_name
}

#------------------------------------------------------------------------------
# TRANSFER FAMILY WEB APP OUTPUTS
#------------------------------------------------------------------------------

output "webapp_id" {
  description = "ID of the Transfer Family Web App"
  value       = aws_transfer_web_app.main.web_app_id
}

output "webapp_arn" {
  description = "ARN of the Transfer Family Web App"
  value       = aws_transfer_web_app.main.arn
}

output "webapp_endpoint" {
  description = "Endpoint URL of the Transfer Family Web App"
  value       = aws_transfer_web_app.branding_update.web_app_endpoint
}

output "webapp_name" {
  description = "Name of the Transfer Family Web App"
  value       = local.webapp_name
}

#------------------------------------------------------------------------------
# IAM IDENTITY CENTER OUTPUTS
#------------------------------------------------------------------------------

output "identity_center_instance_arn" {
  description = "ARN of the IAM Identity Center instance"
  value       = local.identity_center_instance_arn
  sensitive   = true
}

output "identity_store_id" {
  description = "ID of the IAM Identity Store"
  value       = local.identity_store_id
  sensitive   = true
}

output "test_user_id" {
  description = "ID of the test user in IAM Identity Center"
  value       = var.create_test_user ? aws_identitystore_user.test_user[0].user_id : null
  sensitive   = true
}

output "test_user_name" {
  description = "Username of the test user"
  value       = var.create_test_user ? aws_identitystore_user.test_user[0].user_name : null
}

#------------------------------------------------------------------------------
# S3 ACCESS GRANTS OUTPUTS
#------------------------------------------------------------------------------

output "access_grants_instance_arn" {
  description = "ARN of the S3 Access Grants instance"
  value       = aws_s3control_access_grants_instance.main.arn
}

output "access_grants_instance_id" {
  description = "ID of the S3 Access Grants instance"
  value       = aws_s3control_access_grants_instance.main.access_grants_instance_id
}

output "access_grants_location_id" {
  description = "ID of the S3 Access Grants location"
  value       = aws_s3control_access_grants_location.main.access_grants_location_id
}

output "access_grants_location_scope" {
  description = "Scope of the S3 Access Grants location"
  value       = aws_s3control_access_grants_location.main.location_scope
}

output "test_user_access_grant_id" {
  description = "ID of the access grant for the test user"
  value       = var.create_test_user ? aws_s3control_access_grant.test_user[0].access_grant_id : null
  sensitive   = true
}

#------------------------------------------------------------------------------
# IAM ROLE OUTPUTS
#------------------------------------------------------------------------------

output "s3_access_grants_role_arn" {
  description = "ARN of the S3 Access Grants IAM role"
  value       = aws_iam_role.s3_access_grants.arn
}

output "s3_access_grants_role_name" {
  description = "Name of the S3 Access Grants IAM role"
  value       = aws_iam_role.s3_access_grants.name
}

output "transfer_identity_bearer_role_arn" {
  description = "ARN of the Transfer Family Identity Bearer IAM role"
  value       = aws_iam_role.transfer_identity_bearer.arn
}

output "transfer_identity_bearer_role_name" {
  description = "Name of the Transfer Family Identity Bearer IAM role"
  value       = aws_iam_role.transfer_identity_bearer.name
}

#------------------------------------------------------------------------------
# NETWORKING OUTPUTS
#------------------------------------------------------------------------------

output "vpc_id" {
  description = "ID of the VPC used for the Transfer Family Web App"
  value       = local.vpc_id
}

output "subnet_ids" {
  description = "IDs of the subnets used for the Transfer Family Web App"
  value       = local.subnet_ids
}

#------------------------------------------------------------------------------
# CLOUDTRAIL OUTPUTS (CONDITIONAL)
#------------------------------------------------------------------------------

output "cloudtrail_name" {
  description = "Name of the CloudTrail for S3 API logging"
  value       = var.enable_cloudtrail_logging ? aws_cloudtrail.s3_logging[0].name : null
}

output "cloudtrail_arn" {
  description = "ARN of the CloudTrail for S3 API logging"
  value       = var.enable_cloudtrail_logging ? aws_cloudtrail.s3_logging[0].arn : null
}

output "cloudtrail_s3_bucket_name" {
  description = "Name of the S3 bucket for CloudTrail logs"
  value       = var.enable_cloudtrail_logging ? aws_s3_bucket.cloudtrail_logs[0].id : null
}

#------------------------------------------------------------------------------
# SAMPLE FILES OUTPUTS
#------------------------------------------------------------------------------

output "sample_files_created" {
  description = "Whether sample files were created in the S3 bucket"
  value       = var.create_sample_files
}

output "sample_file_keys" {
  description = "Keys of the sample files created in S3"
  value = var.create_sample_files ? [
    aws_s3_object.sample_readme[0].key,
    aws_s3_object.sample_document[0].key,
    aws_s3_object.sample_shared[0].key
  ] : []
}

#------------------------------------------------------------------------------
# CONFIGURATION SUMMARY
#------------------------------------------------------------------------------

output "deployment_summary" {
  description = "Summary of the deployed infrastructure"
  value = {
    project_name      = var.project_name
    environment       = var.environment
    aws_region        = var.aws_region
    bucket_name       = aws_s3_bucket.file_storage.id
    webapp_endpoint   = aws_transfer_web_app.branding_update.web_app_endpoint
    test_user_created = var.create_test_user
    sample_files      = var.create_sample_files
    cloudtrail_enabled = var.enable_cloudtrail_logging
  }
}

#------------------------------------------------------------------------------
# ACCESS INSTRUCTIONS
#------------------------------------------------------------------------------

output "access_instructions" {
  description = "Instructions for accessing the Transfer Family Web App"
  value = {
    web_app_url = aws_transfer_web_app.branding_update.web_app_endpoint
    test_user   = var.create_test_user ? "testuser" : "No test user created"
    login_info  = "Log in with your IAM Identity Center credentials"
    file_scope  = "Access is granted to files in the 'user-files' prefix"
  }
}