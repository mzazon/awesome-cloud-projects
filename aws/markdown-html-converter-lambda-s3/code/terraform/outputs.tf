# Output values for the Markdown to HTML Converter infrastructure
# These outputs provide important information about the created resources

# ============================================================================
# S3 BUCKET OUTPUTS
# ============================================================================

output "input_bucket_name" {
  description = "Name of the S3 bucket for input Markdown files"
  value       = aws_s3_bucket.input_bucket.bucket
}

output "input_bucket_arn" {
  description = "ARN of the S3 bucket for input Markdown files"
  value       = aws_s3_bucket.input_bucket.arn
}

output "input_bucket_domain_name" {
  description = "Domain name of the input S3 bucket"
  value       = aws_s3_bucket.input_bucket.bucket_domain_name
}

output "output_bucket_name" {
  description = "Name of the S3 bucket for output HTML files"
  value       = aws_s3_bucket.output_bucket.bucket
}

output "output_bucket_arn" {
  description = "ARN of the S3 bucket for output HTML files"
  value       = aws_s3_bucket.output_bucket.arn
}

output "output_bucket_domain_name" {
  description = "Domain name of the output S3 bucket"
  value       = aws_s3_bucket.output_bucket.bucket_domain_name
}

# ============================================================================
# LAMBDA FUNCTION OUTPUTS
# ============================================================================

output "lambda_function_name" {
  description = "Name of the Lambda function"
  value       = aws_lambda_function.markdown_converter.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function"
  value       = aws_lambda_function.markdown_converter.arn
}

output "lambda_function_invoke_arn" {
  description = "Invoke ARN of the Lambda function"
  value       = aws_lambda_function.markdown_converter.invoke_arn
}

output "lambda_function_version" {
  description = "Latest published version of the Lambda function"
  value       = aws_lambda_function.markdown_converter.version
}

output "lambda_function_runtime" {
  description = "Runtime environment of the Lambda function"
  value       = aws_lambda_function.markdown_converter.runtime
}

output "lambda_function_timeout" {
  description = "Timeout setting of the Lambda function (seconds)"
  value       = aws_lambda_function.markdown_converter.timeout
}

output "lambda_function_memory_size" {
  description = "Memory allocation of the Lambda function (MB)"
  value       = aws_lambda_function.markdown_converter.memory_size
}

# ============================================================================
# IAM ROLE OUTPUTS
# ============================================================================

output "lambda_execution_role_name" {
  description = "Name of the Lambda execution IAM role"
  value       = aws_iam_role.lambda_execution_role.name
}

output "lambda_execution_role_arn" {
  description = "ARN of the Lambda execution IAM role"
  value       = aws_iam_role.lambda_execution_role.arn
}

# ============================================================================
# CLOUDWATCH LOGS OUTPUTS
# ============================================================================

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for Lambda function"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group for Lambda function"
  value       = aws_cloudwatch_log_group.lambda_logs.arn
}

output "cloudwatch_log_retention_days" {
  description = "Log retention period in days"
  value       = aws_cloudwatch_log_group.lambda_logs.retention_in_days
}

# ============================================================================
# MONITORING OUTPUTS
# ============================================================================

output "lambda_error_alarm_name" {
  description = "Name of the CloudWatch alarm for Lambda errors"
  value       = aws_cloudwatch_metric_alarm.lambda_error_alarm.alarm_name
}

output "lambda_duration_alarm_name" {
  description = "Name of the CloudWatch alarm for Lambda duration"
  value       = aws_cloudwatch_metric_alarm.lambda_duration_alarm.alarm_name
}

# ============================================================================
# CONFIGURATION OUTPUTS
# ============================================================================

output "supported_markdown_extensions" {
  description = "List of supported Markdown file extensions"
  value       = var.markdown_file_extensions
}

output "s3_bucket_versioning_enabled" {
  description = "Whether S3 bucket versioning is enabled"
  value       = var.s3_bucket_versioning
}

output "s3_bucket_encryption_enabled" {
  description = "Whether S3 bucket encryption is enabled"
  value       = var.s3_bucket_encryption
}

output "lambda_tracing_enabled" {
  description = "Whether X-Ray tracing is enabled for Lambda function"
  value       = var.enable_lambda_tracing
}

# ============================================================================
# USAGE INSTRUCTIONS OUTPUTS
# ============================================================================

output "upload_command_example" {
  description = "Example AWS CLI command to upload a markdown file"
  value       = "aws s3 cp your-file.md s3://${aws_s3_bucket.input_bucket.bucket}/"
}

output "download_command_example" {
  description = "Example AWS CLI command to download converted HTML file"
  value       = "aws s3 cp s3://${aws_s3_bucket.output_bucket.bucket}/your-file.html ./"
}

output "list_input_files_command" {
  description = "AWS CLI command to list files in input bucket"
  value       = "aws s3 ls s3://${aws_s3_bucket.input_bucket.bucket}/"
}

output "list_output_files_command" {
  description = "AWS CLI command to list files in output bucket"
  value       = "aws s3 ls s3://${aws_s3_bucket.output_bucket.bucket}/"
}

output "view_logs_command" {
  description = "AWS CLI command to view Lambda function logs"
  value       = "aws logs tail ${aws_cloudwatch_log_group.lambda_logs.name} --follow"
}

# ============================================================================
# RESOURCE INFORMATION OUTPUTS
# ============================================================================

output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "aws_account_id" {
  description = "AWS account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

output "project_name" {
  description = "Project name used for resource naming"
  value       = var.project_name
}

output "environment" {
  description = "Environment name"
  value       = var.environment
}

# ============================================================================
# CONSOLE URLS (FOR CONVENIENCE)
# ============================================================================

output "lambda_console_url" {
  description = "AWS Console URL for the Lambda function"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/lambda/home?region=${data.aws_region.current.name}#/functions/${aws_lambda_function.markdown_converter.function_name}"
}

output "input_bucket_console_url" {
  description = "AWS Console URL for the input S3 bucket"
  value       = "https://s3.console.aws.amazon.com/s3/buckets/${aws_s3_bucket.input_bucket.bucket}?region=${data.aws_region.current.name}"
}

output "output_bucket_console_url" {
  description = "AWS Console URL for the output S3 bucket"
  value       = "https://s3.console.aws.amazon.com/s3/buckets/${aws_s3_bucket.output_bucket.bucket}?region=${data.aws_region.current.name}"
}

output "cloudwatch_logs_console_url" {
  description = "AWS Console URL for CloudWatch logs"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#logsV2:log-groups/log-group/${replace(aws_cloudwatch_log_group.lambda_logs.name, "/", "$252F")}"
}

# ============================================================================
# COST ESTIMATION OUTPUTS
# ============================================================================

output "estimated_monthly_costs" {
  description = "Estimated monthly costs breakdown (based on usage assumptions)"
  value = {
    lambda_requests_1000   = "$0.20"
    lambda_compute_gb_sec  = "$0.0000166667 per GB-second"
    s3_standard_storage_gb = "$0.023 per GB"
    cloudwatch_logs_gb     = "$0.50 per GB"
    data_transfer_gb       = "$0.09 per GB (after 1GB free)"
    note                   = "Actual costs depend on usage patterns. Many services have free tiers."
  }
}

output "deployment_summary" {
  description = "Summary of deployed resources"
  value = {
    input_bucket      = aws_s3_bucket.input_bucket.bucket
    output_bucket     = aws_s3_bucket.output_bucket.bucket
    lambda_function   = aws_lambda_function.markdown_converter.function_name
    lambda_runtime    = aws_lambda_function.markdown_converter.runtime
    log_group         = aws_cloudwatch_log_group.lambda_logs.name
    iam_role          = aws_iam_role.lambda_execution_role.name
    supported_formats = var.markdown_file_extensions
    region           = data.aws_region.current.name
  }
}