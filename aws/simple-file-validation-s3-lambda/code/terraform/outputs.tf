# =============================================================================
# Outputs for Simple File Validation with S3 and Lambda
# =============================================================================

# -----------------------------------------------------------------------------
# S3 Bucket Information
# -----------------------------------------------------------------------------

output "upload_bucket_name" {
  description = "Name of the S3 bucket for file uploads"
  value       = aws_s3_bucket.upload.bucket
}

output "upload_bucket_arn" {
  description = "ARN of the S3 bucket for file uploads"
  value       = aws_s3_bucket.upload.arn
}

output "upload_bucket_domain_name" {
  description = "Domain name of the upload S3 bucket"
  value       = aws_s3_bucket.upload.bucket_domain_name
}

output "valid_files_bucket_name" {
  description = "Name of the S3 bucket for valid files"
  value       = aws_s3_bucket.valid.bucket
}

output "valid_files_bucket_arn" {
  description = "ARN of the S3 bucket for valid files"
  value       = aws_s3_bucket.valid.arn
}

output "quarantine_bucket_name" {
  description = "Name of the S3 bucket for quarantined files"
  value       = aws_s3_bucket.quarantine.bucket
}

output "quarantine_bucket_arn" {
  description = "ARN of the S3 bucket for quarantined files"
  value       = aws_s3_bucket.quarantine.arn
}

# -----------------------------------------------------------------------------
# Lambda Function Information
# -----------------------------------------------------------------------------

output "lambda_function_name" {
  description = "Name of the Lambda function"
  value       = aws_lambda_function.file_validator.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function"
  value       = aws_lambda_function.file_validator.arn
}

output "lambda_function_invoke_arn" {
  description = "Invoke ARN of the Lambda function"
  value       = aws_lambda_function.file_validator.invoke_arn
}

output "lambda_function_version" {
  description = "Version of the Lambda function"
  value       = aws_lambda_function.file_validator.version
}

output "lambda_function_last_modified" {
  description = "Date the Lambda function was last modified"
  value       = aws_lambda_function.file_validator.last_modified
}

# -----------------------------------------------------------------------------
# IAM Role Information
# -----------------------------------------------------------------------------

output "lambda_execution_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_execution.arn
}

output "lambda_execution_role_name" {
  description = "Name of the Lambda execution role"
  value       = aws_iam_role.lambda_execution.name
}

# -----------------------------------------------------------------------------
# CloudWatch Logs Information
# -----------------------------------------------------------------------------

output "lambda_log_group_name" {
  description = "Name of the CloudWatch Log Group for Lambda function"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

output "lambda_log_group_arn" {
  description = "ARN of the CloudWatch Log Group for Lambda function"
  value       = aws_cloudwatch_log_group.lambda_logs.arn
}

# -----------------------------------------------------------------------------
# Configuration Information
# -----------------------------------------------------------------------------

output "allowed_file_extensions" {
  description = "List of allowed file extensions"
  value       = var.allowed_file_extensions
}

output "max_file_size_mb" {
  description = "Maximum allowed file size in MB"
  value       = var.max_file_size_mb
}

output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = var.aws_region
}

# -----------------------------------------------------------------------------
# Testing and Validation Commands
# -----------------------------------------------------------------------------

output "aws_cli_upload_test_command" {
  description = "AWS CLI command to test file upload to the validation system"
  value       = "aws s3 cp <local-file> s3://${aws_s3_bucket.upload.bucket}/"
}

output "aws_cli_list_valid_files_command" {
  description = "AWS CLI command to list files in the valid files bucket"
  value       = "aws s3 ls s3://${aws_s3_bucket.valid.bucket}/ --recursive"
}

output "aws_cli_list_quarantine_files_command" {
  description = "AWS CLI command to list files in the quarantine bucket"
  value       = "aws s3 ls s3://${aws_s3_bucket.quarantine.bucket}/ --recursive"
}

output "aws_cli_view_logs_command" {
  description = "AWS CLI command to view Lambda function logs"
  value       = "aws logs describe-log-streams --log-group-name ${aws_cloudwatch_log_group.lambda_logs.name} --order-by LastEventTime --descending --max-items 1"
}

# -----------------------------------------------------------------------------
# Summary Information
# -----------------------------------------------------------------------------

output "deployment_summary" {
  description = "Summary of deployed resources and their purpose"
  value = {
    upload_bucket     = "S3 bucket (${aws_s3_bucket.upload.bucket}) for initial file uploads"
    valid_bucket      = "S3 bucket (${aws_s3_bucket.valid.bucket}) for validated files"
    quarantine_bucket = "S3 bucket (${aws_s3_bucket.quarantine.bucket}) for invalid files"
    lambda_function   = "Lambda function (${aws_lambda_function.file_validator.function_name}) for file validation"
    log_group         = "CloudWatch log group (${aws_cloudwatch_log_group.lambda_logs.name}) for function logs"
    max_file_size     = "${var.max_file_size_mb} MB maximum file size"
    allowed_types     = join(", ", var.allowed_file_extensions)
  }
}