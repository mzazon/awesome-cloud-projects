# Output values for AWS Transfer Family and Step Functions file processing infrastructure
# These outputs provide important information for verification and integration

# =============================================================================
# S3 BUCKET OUTPUTS
# =============================================================================

output "landing_bucket_name" {
  description = "Name of the S3 bucket for incoming files via SFTP"
  value       = aws_s3_bucket.landing.bucket
}

output "landing_bucket_arn" {
  description = "ARN of the landing S3 bucket"
  value       = aws_s3_bucket.landing.arn
}

output "processed_bucket_name" {
  description = "Name of the S3 bucket for processed files"
  value       = aws_s3_bucket.processed.bucket
}

output "processed_bucket_arn" {
  description = "ARN of the processed S3 bucket"
  value       = aws_s3_bucket.processed.arn
}

output "archive_bucket_name" {
  description = "Name of the S3 bucket for archived files"
  value       = aws_s3_bucket.archive.bucket
}

output "archive_bucket_arn" {
  description = "ARN of the archive S3 bucket"
  value       = aws_s3_bucket.archive.arn
}

# =============================================================================
# AWS TRANSFER FAMILY OUTPUTS
# =============================================================================

output "sftp_server_id" {
  description = "ID of the AWS Transfer Family SFTP server"
  value       = aws_transfer_server.sftp.id
}

output "sftp_server_arn" {
  description = "ARN of the AWS Transfer Family SFTP server"
  value       = aws_transfer_server.sftp.arn
}

output "sftp_endpoint" {
  description = "SFTP server endpoint hostname for client connections"
  value       = aws_transfer_server.sftp.endpoint
}

output "sftp_username" {
  description = "Username for SFTP authentication"
  value       = aws_transfer_user.business_partner.user_name
}

output "sftp_home_directory" {
  description = "Home directory path for SFTP user"
  value       = aws_transfer_user.business_partner.home_directory
}

# =============================================================================
# LAMBDA FUNCTION OUTPUTS
# =============================================================================

output "validator_function_name" {
  description = "Name of the file validator Lambda function"
  value       = aws_lambda_function.validator.function_name
}

output "validator_function_arn" {
  description = "ARN of the file validator Lambda function"
  value       = aws_lambda_function.validator.arn
}

output "processor_function_name" {
  description = "Name of the data processor Lambda function"
  value       = aws_lambda_function.processor.function_name
}

output "processor_function_arn" {
  description = "ARN of the data processor Lambda function"
  value       = aws_lambda_function.processor.arn
}

output "router_function_name" {
  description = "Name of the file router Lambda function"
  value       = aws_lambda_function.router.function_name
}

output "router_function_arn" {
  description = "ARN of the file router Lambda function"
  value       = aws_lambda_function.router.arn
}

# =============================================================================
# STEP FUNCTIONS OUTPUTS
# =============================================================================

output "step_functions_state_machine_name" {
  description = "Name of the Step Functions state machine"
  value       = aws_sfn_state_machine.file_processing.name
}

output "step_functions_state_machine_arn" {
  description = "ARN of the Step Functions state machine"
  value       = aws_sfn_state_machine.file_processing.arn
}

output "step_functions_execution_role_arn" {
  description = "ARN of the Step Functions execution role"
  value       = aws_iam_role.stepfunctions_role.arn
}

# =============================================================================
# MONITORING OUTPUTS
# =============================================================================

output "sns_topic_arn" {
  description = "ARN of the SNS topic for alerts and notifications"
  value       = aws_sns_topic.alerts.arn
}

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for Step Functions"
  value       = aws_cloudwatch_log_group.stepfunctions.name
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group for Step Functions"
  value       = aws_cloudwatch_log_group.stepfunctions.arn
}

# =============================================================================
# EVENTBRIDGE OUTPUTS
# =============================================================================

output "eventbridge_rule_name" {
  description = "Name of the EventBridge rule for S3 file events"
  value       = aws_cloudwatch_event_rule.s3_file_upload.name
}

output "eventbridge_rule_arn" {
  description = "ARN of the EventBridge rule for S3 file events"
  value       = aws_cloudwatch_event_rule.s3_file_upload.arn
}

# =============================================================================
# IAM ROLE OUTPUTS
# =============================================================================

output "lambda_execution_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_role.arn
}

output "transfer_service_role_arn" {
  description = "ARN of the Transfer Family service role"
  value       = aws_iam_role.transfer_role.arn
}

output "eventbridge_execution_role_arn" {
  description = "ARN of the EventBridge execution role"
  value       = aws_iam_role.eventbridge_role.arn
}

# =============================================================================
# SECURITY OUTPUTS
# =============================================================================

output "kms_key_id" {
  description = "ID of the KMS key used for encryption (if encryption enabled)"
  value       = var.enable_encryption ? aws_kms_key.file_processing[0].key_id : null
}

output "kms_key_arn" {
  description = "ARN of the KMS key used for encryption (if encryption enabled)"
  value       = var.enable_encryption ? aws_kms_key.file_processing[0].arn : null
}

output "kms_alias_name" {
  description = "Alias name of the KMS key (if encryption enabled)"
  value       = var.enable_encryption ? aws_kms_alias.file_processing[0].name : null
}

# =============================================================================
# CONNECTIVITY AND TESTING OUTPUTS
# =============================================================================

output "sftp_connection_string" {
  description = "SFTP connection string for testing (without password/key)"
  value       = "sftp://${var.sftp_username}@${aws_transfer_server.sftp.endpoint}"
}

output "aws_cli_test_upload_command" {
  description = "AWS CLI command to test file upload to landing bucket"
  value       = "aws s3 cp <local-file> s3://${aws_s3_bucket.landing.bucket}/"
}

output "step_functions_console_url" {
  description = "URL to view Step Functions state machine in AWS Console"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/states/home?region=${data.aws_region.current.name}#/statemachines/view/${aws_sfn_state_machine.file_processing.arn}"
}

# =============================================================================
# COST OPTIMIZATION OUTPUTS
# =============================================================================

output "resource_tags" {
  description = "Common tags applied to all resources for cost tracking"
  value = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

output "s3_lifecycle_policy_enabled" {
  description = "Whether S3 lifecycle policies are enabled for cost optimization"
  value       = true
}

# =============================================================================
# CONFIGURATION SUMMARY
# =============================================================================

output "deployment_summary" {
  description = "Summary of the deployed infrastructure"
  value = {
    project_name                = var.project_name
    environment                = var.environment
    region                     = data.aws_region.current.name
    account_id                 = data.aws_caller_identity.current.account_id
    sftp_endpoint              = aws_transfer_server.sftp.endpoint
    landing_bucket             = aws_s3_bucket.landing.bucket
    processed_bucket           = aws_s3_bucket.processed.bucket
    archive_bucket             = aws_s3_bucket.archive.bucket
    state_machine_name         = aws_sfn_state_machine.file_processing.name
    encryption_enabled         = var.enable_encryption
    xray_tracing_enabled       = var.enable_xray_tracing
    s3_versioning_enabled      = var.enable_s3_versioning
    notification_email_configured = var.notification_email != ""
  }
}