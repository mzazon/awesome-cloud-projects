# Outputs for Advanced Cross-Account IAM Role Federation
# These outputs provide essential information for managing and using the infrastructure

#------------------------------------------------------------------------------
# SECURITY ACCOUNT OUTPUTS
#------------------------------------------------------------------------------

output "master_cross_account_role_arn" {
  description = "ARN of the master cross-account role in the security account"
  value       = aws_iam_role.master_cross_account.arn
}

output "master_cross_account_role_name" {
  description = "Name of the master cross-account role"
  value       = aws_iam_role.master_cross_account.name
}

output "saml_provider_arn" {
  description = "ARN of the SAML identity provider"
  value       = local.saml_provider_arn
}

output "security_account_id" {
  description = "AWS account ID for the security account"
  value       = data.aws_caller_identity.security.account_id
}

output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_id.suffix.hex
}

#------------------------------------------------------------------------------
# PRODUCTION ACCOUNT OUTPUTS
#------------------------------------------------------------------------------

output "production_cross_account_role_arn" {
  description = "ARN of the production cross-account role"
  value       = aws_iam_role.production_cross_account.arn
}

output "production_cross_account_role_name" {
  description = "Name of the production cross-account role"
  value       = aws_iam_role.production_cross_account.name
}

output "production_external_id" {
  description = "External ID for production account role assumption"
  value       = random_password.production_external_id.result
  sensitive   = true
}

output "production_s3_bucket_name" {
  description = "Name of the S3 bucket in the production account"
  value       = aws_s3_bucket.production_shared_data.bucket
}

output "production_s3_bucket_arn" {
  description = "ARN of the S3 bucket in the production account"
  value       = aws_s3_bucket.production_shared_data.arn
}

#------------------------------------------------------------------------------
# DEVELOPMENT ACCOUNT OUTPUTS
#------------------------------------------------------------------------------

output "development_cross_account_role_arn" {
  description = "ARN of the development cross-account role"
  value       = aws_iam_role.development_cross_account.arn
}

output "development_cross_account_role_name" {
  description = "Name of the development cross-account role"
  value       = aws_iam_role.development_cross_account.name
}

output "development_external_id" {
  description = "External ID for development account role assumption"
  value       = random_password.development_external_id.result
  sensitive   = true
}

output "development_s3_bucket_name" {
  description = "Name of the S3 bucket in the development account"
  value       = aws_s3_bucket.development_shared_data.bucket
}

output "development_s3_bucket_arn" {
  description = "ARN of the S3 bucket in the development account"
  value       = aws_s3_bucket.development_shared_data.arn
}

#------------------------------------------------------------------------------
# CLOUDTRAIL OUTPUTS
#------------------------------------------------------------------------------

output "cloudtrail_name" {
  description = "Name of the CloudTrail for cross-account audit logging"
  value       = var.enable_cloudtrail_logging ? aws_cloudtrail.cross_account_audit[0].name : null
}

output "cloudtrail_arn" {
  description = "ARN of the CloudTrail for cross-account audit logging"
  value       = var.enable_cloudtrail_logging ? aws_cloudtrail.cross_account_audit[0].arn : null
}

output "cloudtrail_s3_bucket_name" {
  description = "Name of the S3 bucket for CloudTrail logs"
  value       = var.enable_cloudtrail_logging ? aws_s3_bucket.cloudtrail_logs[0].bucket : null
}

output "cloudtrail_s3_bucket_arn" {
  description = "ARN of the S3 bucket for CloudTrail logs"
  value       = var.enable_cloudtrail_logging ? aws_s3_bucket.cloudtrail_logs[0].arn : null
}

#------------------------------------------------------------------------------
# LAMBDA VALIDATION OUTPUTS
#------------------------------------------------------------------------------

output "role_validator_lambda_function_name" {
  description = "Name of the Lambda function for role validation"
  value       = var.enable_role_validation ? aws_lambda_function.role_validator[0].function_name : null
}

output "role_validator_lambda_function_arn" {
  description = "ARN of the Lambda function for role validation"
  value       = var.enable_role_validation ? aws_lambda_function.role_validator[0].arn : null
}

output "role_validator_lambda_role_arn" {
  description = "ARN of the IAM role for the role validator Lambda function"
  value       = var.enable_role_validation ? aws_iam_role.role_validator_lambda[0].arn : null
}

#------------------------------------------------------------------------------
# CONFIGURATION OUTPUTS
#------------------------------------------------------------------------------

output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "project_name" {
  description = "Project name used for resource naming and tagging"
  value       = var.project_name
}

output "environment" {
  description = "Environment name"
  value       = var.environment
}

output "allowed_departments" {
  description = "List of departments allowed to assume cross-account roles"
  value       = var.allowed_departments
}

output "transitive_tag_keys" {
  description = "List of session tag keys that can be passed transitively"
  value       = var.transitive_tag_keys
}

#------------------------------------------------------------------------------
# ROLE ASSUMPTION COMMANDS
#------------------------------------------------------------------------------

output "production_role_assumption_command" {
  description = "AWS CLI command to assume the production cross-account role"
  value = format(
    "aws sts assume-role --role-arn %s --role-session-name 'ProductionSession-%s' --external-id '%s' --duration-seconds %d",
    aws_iam_role.production_cross_account.arn,
    "${formatdate("YYYYMMDD-hhmmss", timestamp())}",
    random_password.production_external_id.result,
    var.max_session_duration_production
  )
  sensitive = true
}

output "development_role_assumption_command" {
  description = "AWS CLI command to assume the development cross-account role"
  value = format(
    "aws sts assume-role --role-arn %s --role-session-name 'DevelopmentSession-%s' --external-id '%s' --duration-seconds %d",
    aws_iam_role.development_cross_account.arn,
    "${formatdate("YYYYMMDD-hhmmss", timestamp())}",
    random_password.development_external_id.result,
    var.max_session_duration_development
  )
  sensitive = true
}

output "session_tagging_example_command" {
  description = "Example AWS CLI command with session tagging for role assumption"
  value = format(
    "aws sts assume-role --role-arn %s --role-session-name 'TaggedSession-%s' --external-id '%s' --tags 'Key=Department,Value=Engineering' 'Key=Project,Value=CrossAccountDemo' 'Key=Environment,Value=Production' --transitive-tag-keys Department,Project,Environment --duration-seconds %d",
    aws_iam_role.production_cross_account.arn,
    "${formatdate("YYYYMMDD-hhmmss", timestamp())}",
    random_password.production_external_id.result,
    var.max_session_duration_production
  )
  sensitive = true
}

#------------------------------------------------------------------------------
# VALIDATION COMMANDS
#------------------------------------------------------------------------------

output "lambda_validation_invoke_command" {
  description = "AWS CLI command to invoke the role validation Lambda function"
  value = var.enable_role_validation ? format(
    "aws lambda invoke --function-name %s --payload '{}' response.json && cat response.json",
    aws_lambda_function.role_validator[0].function_name
  ) : "Role validation is disabled"
}

output "cloudtrail_logs_query_command" {
  description = "AWS CLI command to query CloudTrail logs for role assumptions"
  value = var.enable_cloudtrail_logging ? format(
    "aws logs filter-log-events --log-group-name CloudTrail/%s --start-time $(date -d '1 hour ago' +%%s)000 --filter-pattern '{ $.eventName = \"AssumeRole\" }' --query 'events[0:5].{Time:eventTime,User:userIdentity.type,Action:eventName}' --output table",
    aws_cloudtrail.cross_account_audit[0].name
  ) : "CloudTrail logging is disabled"
}

#------------------------------------------------------------------------------
# SECURITY INFORMATION
#------------------------------------------------------------------------------

output "security_considerations" {
  description = "Important security considerations for this deployment"
  value = {
    external_ids_rotation = "External IDs should be rotated regularly and stored securely in AWS Secrets Manager"
    mfa_requirement = var.enable_mfa_requirement ? "MFA is required for role assumption" : "MFA is not required - consider enabling for enhanced security"
    ip_restrictions = var.enable_ip_restrictions ? "IP address restrictions are enabled for development account" : "IP restrictions are disabled"
    session_tagging = var.enable_session_tagging ? "Session tagging is enabled for enhanced audit trails" : "Session tagging is disabled"
    cloudtrail_monitoring = var.enable_cloudtrail_logging ? "CloudTrail is enabled for comprehensive audit logging" : "CloudTrail is disabled - consider enabling for compliance"
    role_validation = var.enable_role_validation ? "Automated role validation is enabled" : "Automated role validation is disabled"
  }
}

output "compliance_information" {
  description = "Compliance and audit information"
  value = {
    log_retention_days = var.cloudtrail_log_retention_days
    max_session_durations = {
      master_role = var.max_session_duration_master
      production_role = var.max_session_duration_production
      development_role = var.max_session_duration_development
    }
    encrypted_storage = "All S3 buckets are encrypted with AES-256"
    versioning_enabled = "S3 bucket versioning is enabled for all buckets"
    public_access_blocked = "Public access is blocked for all S3 buckets"
  }
}