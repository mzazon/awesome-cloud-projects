# =============================================================================
# S3 Bucket Outputs
# =============================================================================

output "document_bucket_name" {
  description = "Name of the S3 bucket for document storage"
  value       = aws_s3_bucket.documents.bucket
}

output "document_bucket_arn" {
  description = "ARN of the S3 bucket for document storage"
  value       = aws_s3_bucket.documents.arn
}

output "results_bucket_name" {
  description = "Name of the S3 bucket for processing results"
  value       = aws_s3_bucket.results.bucket
}

output "results_bucket_arn" {
  description = "ARN of the S3 bucket for processing results"
  value       = aws_s3_bucket.results.arn
}

# =============================================================================
# DynamoDB Table Outputs
# =============================================================================

output "dynamodb_table_name" {
  description = "Name of the DynamoDB table for job tracking"
  value       = aws_dynamodb_table.processing_jobs.name
}

output "dynamodb_table_arn" {
  description = "ARN of the DynamoDB table for job tracking"
  value       = aws_dynamodb_table.processing_jobs.arn
}

# =============================================================================
# Lambda Function Outputs
# =============================================================================

output "lambda_function_name" {
  description = "Name of the Lambda function that triggers document processing"
  value       = aws_lambda_function.document_trigger.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function that triggers document processing"
  value       = aws_lambda_function.document_trigger.arn
}

output "lambda_function_invoke_arn" {
  description = "Invoke ARN of the Lambda function"
  value       = aws_lambda_function.document_trigger.invoke_arn
}

# =============================================================================
# Step Functions Outputs
# =============================================================================

output "step_functions_state_machine_name" {
  description = "Name of the Step Functions state machine"
  value       = aws_sfn_state_machine.document_processing.name
}

output "step_functions_state_machine_arn" {
  description = "ARN of the Step Functions state machine"
  value       = aws_sfn_state_machine.document_processing.arn
}

output "step_functions_execution_role_arn" {
  description = "ARN of the Step Functions execution role"
  value       = aws_iam_role.step_functions_role.arn
}

# =============================================================================
# SNS Topic Outputs
# =============================================================================

output "sns_topic_name" {
  description = "Name of the SNS topic for notifications"
  value       = aws_sns_topic.notifications.name
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for notifications"
  value       = aws_sns_topic.notifications.arn
}

# =============================================================================
# IAM Role Outputs
# =============================================================================

output "lambda_execution_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_role.arn
}

output "lambda_execution_role_name" {
  description = "Name of the Lambda execution role"
  value       = aws_iam_role.lambda_role.name
}

output "step_functions_execution_role_name" {
  description = "Name of the Step Functions execution role"
  value       = aws_iam_role.step_functions_role.name
}

# =============================================================================
# CloudWatch Logs Outputs
# =============================================================================

output "lambda_log_group_name" {
  description = "Name of the CloudWatch log group for Lambda function"
  value       = var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.lambda_logs[0].name : null
}

output "step_functions_log_group_name" {
  description = "Name of the CloudWatch log group for Step Functions"
  value       = var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.step_functions_logs[0].name : null
}

# =============================================================================
# KMS Key Outputs
# =============================================================================

output "kms_key_id" {
  description = "ID of the KMS key used for encryption"
  value       = var.enable_s3_encryption || var.enable_dynamodb_encryption || var.enable_sns_encryption ? aws_kms_key.document_processing[0].key_id : null
}

output "kms_key_arn" {
  description = "ARN of the KMS key used for encryption"
  value       = var.enable_s3_encryption || var.enable_dynamodb_encryption || var.enable_sns_encryption ? aws_kms_key.document_processing[0].arn : null
}

output "kms_key_alias" {
  description = "Alias of the KMS key used for encryption"
  value       = var.enable_s3_encryption || var.enable_dynamodb_encryption || var.enable_sns_encryption ? aws_kms_alias.document_processing[0].name : null
}

# =============================================================================
# Deployment and Testing Information
# =============================================================================

output "deployment_information" {
  description = "Information about the deployed document processing pipeline"
  value = {
    project_name    = var.project_name
    environment     = var.environment
    aws_region      = local.region
    aws_account_id  = local.account_id
    deployment_date = timestamp()
  }
}

output "testing_instructions" {
  description = "Instructions for testing the document processing pipeline"
  value = {
    upload_command = "aws s3 cp your-document.pdf s3://${aws_s3_bucket.documents.bucket}/"
    monitor_command = "aws stepfunctions list-executions --state-machine-arn ${aws_sfn_state_machine.document_processing.arn} --max-items 5"
    check_results_command = "aws s3 ls s3://${aws_s3_bucket.results.bucket}/ --recursive"
    check_jobs_command = "aws dynamodb scan --table-name ${aws_dynamodb_table.processing_jobs.name} --max-items 5"
  }
}

output "cleanup_instructions" {
  description = "Instructions for cleaning up the deployed resources"
  value = {
    terraform_destroy = "terraform destroy"
    manual_s3_cleanup = "aws s3 rm s3://${aws_s3_bucket.documents.bucket} --recursive && aws s3 rm s3://${aws_s3_bucket.results.bucket} --recursive"
    note = "Run 'terraform destroy' to remove all resources. S3 buckets with content may need manual cleanup first."
  }
}

# =============================================================================
# Cost Optimization Information
# =============================================================================

output "cost_optimization_info" {
  description = "Information about cost optimization features enabled"
  value = {
    intelligent_tiering_enabled = var.enable_intelligent_tiering
    lifecycle_management_enabled = true
    lifecycle_days = var.bucket_lifecycle_days
    dynamodb_billing_mode = var.dynamodb_billing_mode
    log_retention_days = var.log_retention_days
  }
}

# =============================================================================
# Security Information
# =============================================================================

output "security_features" {
  description = "Security features enabled in the deployment"
  value = {
    s3_encryption_enabled = var.enable_s3_encryption
    dynamodb_encryption_enabled = var.enable_dynamodb_encryption
    sns_encryption_enabled = var.enable_sns_encryption
    s3_public_access_blocked = true
    s3_versioning_enabled = var.enable_bucket_versioning
    dynamodb_point_in_time_recovery = true
    kms_key_created = var.enable_s3_encryption || var.enable_dynamodb_encryption || var.enable_sns_encryption
  }
}

# =============================================================================
# Monitoring Information
# =============================================================================

output "monitoring_endpoints" {
  description = "Monitoring and logging endpoints"
  value = {
    cloudwatch_logs_enabled = var.enable_cloudwatch_logs
    step_functions_console_url = "https://console.aws.amazon.com/states/home?region=${local.region}#/statemachines/view/${aws_sfn_state_machine.document_processing.arn}"
    lambda_console_url = "https://console.aws.amazon.com/lambda/home?region=${local.region}#/functions/${aws_lambda_function.document_trigger.function_name}"
    dynamodb_console_url = "https://console.aws.amazon.com/dynamodb/home?region=${local.region}#tables:selected=${aws_dynamodb_table.processing_jobs.name}"
    s3_console_url = "https://s3.console.aws.amazon.com/s3/buckets/${aws_s3_bucket.documents.bucket}"
  }
}

# =============================================================================
# Configuration Summary
# =============================================================================

output "configuration_summary" {
  description = "Summary of the deployment configuration"
  value = {
    supported_file_extensions = var.supported_file_extensions
    max_retry_attempts = var.max_retry_attempts
    retry_interval_seconds = var.retry_interval_seconds
    lambda_timeout_seconds = var.lambda_timeout
    lambda_memory_mb = var.lambda_memory_size
    lambda_runtime = var.lambda_runtime
  }
}