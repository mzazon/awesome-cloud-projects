# =============================================================================
# OUTPUTS - JSON to CSV Converter with Lambda and S3
# =============================================================================
# This file defines all the output values from the Terraform configuration.
# These outputs provide important information about the created resources
# for integration with other systems, monitoring, and operational tasks.
# =============================================================================

# =============================================================================
# S3 BUCKET OUTPUTS
# =============================================================================

output "input_bucket_name" {
  description = "Name of the S3 bucket for JSON input files"
  value       = aws_s3_bucket.input.bucket
}

output "input_bucket_arn" {
  description = "ARN of the S3 bucket for JSON input files"
  value       = aws_s3_bucket.input.arn
}

output "input_bucket_domain_name" {
  description = "Domain name of the input S3 bucket"
  value       = aws_s3_bucket.input.bucket_domain_name
}

output "input_bucket_regional_domain_name" {
  description = "Regional domain name of the input S3 bucket"
  value       = aws_s3_bucket.input.bucket_regional_domain_name
}

output "output_bucket_name" {
  description = "Name of the S3 bucket for CSV output files"
  value       = aws_s3_bucket.output.bucket
}

output "output_bucket_arn" {
  description = "ARN of the S3 bucket for CSV output files"
  value       = aws_s3_bucket.output.arn
}

output "output_bucket_domain_name" {
  description = "Domain name of the output S3 bucket"
  value       = aws_s3_bucket.output.bucket_domain_name
}

output "output_bucket_regional_domain_name" {
  description = "Regional domain name of the output S3 bucket"
  value       = aws_s3_bucket.output.bucket_regional_domain_name
}

# =============================================================================
# LAMBDA FUNCTION OUTPUTS
# =============================================================================

output "lambda_function_name" {
  description = "Name of the Lambda function"
  value       = aws_lambda_function.converter.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function"
  value       = aws_lambda_function.converter.arn
}

output "lambda_function_qualified_arn" {
  description = "Qualified ARN of the Lambda function (with version)"
  value       = aws_lambda_function.converter.qualified_arn
}

output "lambda_function_version" {
  description = "Latest published version of the Lambda function"
  value       = aws_lambda_function.converter.version
}

output "lambda_function_last_modified" {
  description = "Date the Lambda function was last modified"
  value       = aws_lambda_function.converter.last_modified
}

output "lambda_function_source_code_hash" {
  description = "Base64-encoded representation of raw SHA-256 sum of the zip file"
  value       = aws_lambda_function.converter.source_code_hash
}

output "lambda_function_source_code_size" {
  description = "Size in bytes of the function .zip file"
  value       = aws_lambda_function.converter.source_code_size
}

# =============================================================================
# IAM ROLE OUTPUTS
# =============================================================================

output "lambda_role_name" {
  description = "Name of the IAM role for the Lambda function"
  value       = aws_iam_role.lambda.name
}

output "lambda_role_arn" {
  description = "ARN of the IAM role for the Lambda function"
  value       = aws_iam_role.lambda.arn
}

output "lambda_role_unique_id" {
  description = "Unique ID of the IAM role for the Lambda function"
  value       = aws_iam_role.lambda.unique_id
}

# =============================================================================
# CLOUDWATCH OUTPUTS
# =============================================================================

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for Lambda function"
  value       = aws_cloudwatch_log_group.lambda.name
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group for Lambda function"
  value       = aws_cloudwatch_log_group.lambda.arn
}

output "cloudwatch_log_group_retention_in_days" {
  description = "Log retention period in days"
  value       = aws_cloudwatch_log_group.lambda.retention_in_days
}

# =============================================================================
# MONITORING OUTPUTS
# =============================================================================

output "lambda_errors_alarm_name" {
  description = "Name of the CloudWatch alarm for Lambda errors"
  value       = var.enable_monitoring ? aws_cloudwatch_metric_alarm.lambda_errors[0].alarm_name : null
}

output "lambda_errors_alarm_arn" {
  description = "ARN of the CloudWatch alarm for Lambda errors"
  value       = var.enable_monitoring ? aws_cloudwatch_metric_alarm.lambda_errors[0].arn : null
}

output "lambda_duration_alarm_name" {
  description = "Name of the CloudWatch alarm for Lambda duration"
  value       = var.enable_monitoring ? aws_cloudwatch_metric_alarm.lambda_duration[0].alarm_name : null
}

output "lambda_duration_alarm_arn" {
  description = "ARN of the CloudWatch alarm for Lambda duration"
  value       = var.enable_monitoring ? aws_cloudwatch_metric_alarm.lambda_duration[0].arn : null
}

# =============================================================================
# RANDOM IDENTIFIER OUTPUTS
# =============================================================================

output "resource_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_id.suffix.hex
}

# =============================================================================
# OPERATIONAL OUTPUTS
# =============================================================================

output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "aws_account_id" {
  description = "AWS account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

# =============================================================================
# INTEGRATION OUTPUTS
# =============================================================================

output "upload_command_example" {
  description = "Example AWS CLI command to upload a JSON file for processing"
  value       = "aws s3 cp your-file.json s3://${aws_s3_bucket.input.bucket}/"
}

output "download_command_example" {
  description = "Example AWS CLI command to download a converted CSV file"
  value       = "aws s3 cp s3://${aws_s3_bucket.output.bucket}/your-file.csv ./"
}

output "list_input_files_command" {
  description = "AWS CLI command to list files in the input bucket"
  value       = "aws s3 ls s3://${aws_s3_bucket.input.bucket}/"
}

output "list_output_files_command" {
  description = "AWS CLI command to list files in the output bucket"
  value       = "aws s3 ls s3://${aws_s3_bucket.output.bucket}/"
}

output "view_logs_command" {
  description = "AWS CLI command to view Lambda function logs"
  value       = "aws logs tail ${aws_cloudwatch_log_group.lambda.name} --follow"
}

# =============================================================================
# TESTING OUTPUTS
# =============================================================================

output "test_json_example" {
  description = "Example JSON content for testing the converter"
  value = jsonencode([
    {
      id         = 1
      name       = "John Doe"
      email      = "john@example.com"
      department = "Engineering"
    },
    {
      id         = 2
      name       = "Jane Smith"
      email      = "jane@example.com"
      department = "Marketing"
    }
  ])
}

output "create_test_file_command" {
  description = "Command to create a test JSON file locally"
  value = "echo '${jsonencode([
    {
      id         = 1
      name       = "John Doe"
      email      = "john@example.com"
      department = "Engineering"
    },
    {
      id         = 2
      name       = "Jane Smith"
      email      = "jane@example.com"
      department = "Marketing"
    }
  ])}' > test-data.json"
}

# =============================================================================
# INFRASTRUCTURE SUMMARY
# =============================================================================

output "infrastructure_summary" {
  description = "Summary of deployed infrastructure components"
  value = {
    input_bucket    = aws_s3_bucket.input.bucket
    output_bucket   = aws_s3_bucket.output.bucket
    lambda_function = aws_lambda_function.converter.function_name
    lambda_runtime  = aws_lambda_function.converter.runtime
    lambda_memory   = aws_lambda_function.converter.memory_size
    lambda_timeout  = aws_lambda_function.converter.timeout
    log_group       = aws_cloudwatch_log_group.lambda.name
    log_retention   = aws_cloudwatch_log_group.lambda.retention_in_days
    monitoring      = var.enable_monitoring
    region          = data.aws_region.current.name
    account_id      = data.aws_caller_identity.current.account_id
  }
}

# =============================================================================
# COST ESTIMATION OUTPUTS
# =============================================================================

output "estimated_monthly_costs" {
  description = "Estimated monthly costs for the infrastructure (approximate)"
  value = {
    lambda_requests_1million = "$0.20"
    lambda_compute_gb_second = "$0.0000166667"
    s3_standard_storage_gb   = "$0.023"
    s3_requests_per_1000     = "$0.0004 (PUT) / $0.0004 (GET)"
    cloudwatch_logs_gb       = "$0.50"
    total_estimated_monthly  = "$1-5 for typical usage"
    free_tier_eligible       = "Yes (first 1M requests, 400K GB-seconds)"
  }
}

# =============================================================================
# SECURITY OUTPUTS
# =============================================================================

output "security_features" {
  description = "Security features enabled in the deployment"
  value = {
    s3_encryption         = "AES256 server-side encryption enabled"
    s3_public_access      = "Public access blocked on all buckets"
    s3_versioning         = "Versioning enabled for data protection"
    iam_least_privilege   = "Lambda role follows least privilege principle"
    cloudwatch_logging    = "Comprehensive logging enabled"
    event_driven_trigger  = "Secure S3 event-driven processing"
  }
}