# Output values for secure file sharing with AWS Transfer Family

# =============================================================================
# TRANSFER FAMILY OUTPUTS
# =============================================================================

output "transfer_server_id" {
  description = "ID of the Transfer Family server"
  value       = aws_transfer_server.secure_server.id
}

output "transfer_server_arn" {
  description = "ARN of the Transfer Family server"
  value       = aws_transfer_server.secure_server.arn
}

output "transfer_server_endpoint" {
  description = "Endpoint of the Transfer Family server"
  value       = aws_transfer_server.secure_server.endpoint
}

output "transfer_server_host_key_fingerprint" {
  description = "Host key fingerprint of the Transfer Family server"
  value       = aws_transfer_server.secure_server.host_key_fingerprint
}

output "transfer_test_user_name" {
  description = "Username for the test user"
  value       = aws_transfer_user.test_user.user_name
}

output "transfer_test_user_arn" {
  description = "ARN of the test user"
  value       = aws_transfer_user.test_user.arn
}

# =============================================================================
# S3 BUCKET OUTPUTS
# =============================================================================

output "s3_bucket_name" {
  description = "Name of the S3 bucket for file storage"
  value       = aws_s3_bucket.file_storage.bucket
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

output "s3_bucket_hosted_zone_id" {
  description = "Route 53 Hosted Zone ID of the S3 bucket"
  value       = aws_s3_bucket.file_storage.hosted_zone_id
}

# =============================================================================
# CLOUDTRAIL OUTPUTS
# =============================================================================

output "cloudtrail_name" {
  description = "Name of the CloudTrail trail"
  value       = var.enable_cloudtrail ? aws_cloudtrail.file_sharing_audit[0].name : null
}

output "cloudtrail_arn" {
  description = "ARN of the CloudTrail trail"
  value       = var.enable_cloudtrail ? aws_cloudtrail.file_sharing_audit[0].arn : null
}

output "cloudtrail_home_region" {
  description = "Home region of the CloudTrail trail"
  value       = var.enable_cloudtrail ? aws_cloudtrail.file_sharing_audit[0].home_region : null
}

output "cloudtrail_log_group_name" {
  description = "Name of the CloudWatch log group for CloudTrail"
  value       = var.enable_cloudtrail ? aws_cloudwatch_log_group.cloudtrail[0].name : null
}

output "cloudtrail_log_group_arn" {
  description = "ARN of the CloudWatch log group for CloudTrail"
  value       = var.enable_cloudtrail ? aws_cloudwatch_log_group.cloudtrail[0].arn : null
}

output "cloudtrail_s3_bucket_name" {
  description = "Name of the S3 bucket for CloudTrail logs"
  value       = var.enable_cloudtrail ? aws_s3_bucket.cloudtrail_logs[0].bucket : null
}

# =============================================================================
# KMS OUTPUTS
# =============================================================================

output "kms_s3_key_id" {
  description = "ID of the KMS key used for S3 bucket encryption"
  value       = aws_kms_key.s3_encryption.key_id
}

output "kms_s3_key_arn" {
  description = "ARN of the KMS key used for S3 bucket encryption"
  value       = aws_kms_key.s3_encryption.arn
}

output "kms_s3_key_alias" {
  description = "Alias of the KMS key used for S3 bucket encryption"
  value       = aws_kms_alias.s3_encryption.name
}

output "kms_cloudtrail_key_id" {
  description = "ID of the KMS key used for CloudTrail encryption"
  value       = var.enable_cloudtrail ? aws_kms_key.cloudtrail_encryption[0].key_id : null
}

output "kms_cloudtrail_key_arn" {
  description = "ARN of the KMS key used for CloudTrail encryption"
  value       = var.enable_cloudtrail ? aws_kms_key.cloudtrail_encryption[0].arn : null
}

# =============================================================================
# IAM OUTPUTS
# =============================================================================

output "transfer_server_role_name" {
  description = "Name of the IAM role for Transfer Family server"
  value       = aws_iam_role.transfer_server.name
}

output "transfer_server_role_arn" {
  description = "ARN of the IAM role for Transfer Family server"
  value       = aws_iam_role.transfer_server.arn
}

output "transfer_logging_role_name" {
  description = "Name of the IAM role for Transfer Family logging"
  value       = aws_iam_role.transfer_logging.name
}

output "transfer_logging_role_arn" {
  description = "ARN of the IAM role for Transfer Family logging"
  value       = aws_iam_role.transfer_logging.arn
}

output "cloudtrail_logs_role_name" {
  description = "Name of the IAM role for CloudTrail logs"
  value       = var.enable_cloudtrail ? aws_iam_role.cloudtrail_logs[0].name : null
}

output "cloudtrail_logs_role_arn" {
  description = "ARN of the IAM role for CloudTrail logs"
  value       = var.enable_cloudtrail ? aws_iam_role.cloudtrail_logs[0].arn : null
}

# =============================================================================
# CLOUDWATCH OUTPUTS
# =============================================================================

output "transfer_server_log_group_name" {
  description = "Name of the CloudWatch log group for Transfer Family server"
  value       = aws_cloudwatch_log_group.transfer_server.name
}

output "transfer_server_log_group_arn" {
  description = "ARN of the CloudWatch log group for Transfer Family server"
  value       = aws_cloudwatch_log_group.transfer_server.arn
}

# =============================================================================
# CONNECTION AND ACCESS INFORMATION
# =============================================================================

output "sftp_connection_command" {
  description = "SFTP connection command for the test user"
  value       = "sftp ${var.test_user_name}@${aws_transfer_server.secure_server.endpoint}"
}

output "s3_console_url" {
  description = "URL to access the S3 bucket in AWS Console"
  value       = "https://console.aws.amazon.com/s3/buckets/${aws_s3_bucket.file_storage.bucket}"
}

output "cloudtrail_console_url" {
  description = "URL to access CloudTrail in AWS Console"
  value       = var.enable_cloudtrail ? "https://console.aws.amazon.com/cloudtrail/home?region=${data.aws_region.current.name}#/trails/${aws_cloudtrail.file_sharing_audit[0].name}" : null
}

output "transfer_console_url" {
  description = "URL to access Transfer Family server in AWS Console"
  value       = "https://console.aws.amazon.com/transfer/home?region=${data.aws_region.current.name}#/servers/${aws_transfer_server.secure_server.id}"
}

# =============================================================================
# RESOURCE SUMMARY
# =============================================================================

output "resource_summary" {
  description = "Summary of created resources"
  value = {
    transfer_server_id     = aws_transfer_server.secure_server.id
    s3_bucket_name        = aws_s3_bucket.file_storage.bucket
    test_user_name        = aws_transfer_user.test_user.user_name
    cloudtrail_enabled    = var.enable_cloudtrail
    lifecycle_enabled     = var.s3_lifecycle_enable
    encryption_enabled    = true
    versioning_enabled    = true
    public_access_blocked = true
    region               = data.aws_region.current.name
    account_id           = data.aws_caller_identity.current.account_id
  }
}

# =============================================================================
# VALIDATION COMMANDS
# =============================================================================

output "validation_commands" {
  description = "Commands to validate the deployment"
  value = {
    check_transfer_server = "aws transfer describe-server --server-id ${aws_transfer_server.secure_server.id}"
    check_s3_bucket      = "aws s3 ls s3://${aws_s3_bucket.file_storage.bucket}/"
    check_user           = "aws transfer describe-user --server-id ${aws_transfer_server.secure_server.id} --user-name ${var.test_user_name}"
    check_cloudtrail     = var.enable_cloudtrail ? "aws cloudtrail get-trail-status --name ${aws_cloudtrail.file_sharing_audit[0].name}" : "CloudTrail not enabled"
    test_sftp_connection = "sftp ${var.test_user_name}@${aws_transfer_server.secure_server.endpoint}"
  }
}

# =============================================================================
# SECURITY INFORMATION
# =============================================================================

output "security_features" {
  description = "Enabled security features"
  value = {
    kms_encryption        = "Enabled with customer-managed keys"
    s3_versioning        = "Enabled"
    public_access_block  = "Enabled"
    cloudtrail_logging   = var.enable_cloudtrail ? "Enabled with data events" : "Disabled"
    log_file_validation  = var.enable_cloudtrail ? "Enabled" : "N/A"
    multi_region_trail   = var.enable_cloudtrail ? "Enabled" : "N/A"
    structured_logging   = "Enabled"
    lifecycle_management = var.s3_lifecycle_enable ? "Enabled" : "Disabled"
  }
}