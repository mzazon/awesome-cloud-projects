# Output values for the Simple Password Generator infrastructure

# Lambda Function Information
output "lambda_function_name" {
  description = "Name of the deployed Lambda function"
  value       = aws_lambda_function.password_generator.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function"
  value       = aws_lambda_function.password_generator.arn
}

output "lambda_function_invoke_arn" {
  description = "ARN to be used for invoking Lambda Function from API Gateway"
  value       = aws_lambda_function.password_generator.invoke_arn
}

output "lambda_function_url" {
  description = "Function URL for HTTP(S) invocation of the Lambda function"
  value       = aws_lambda_function_url.password_generator.function_url
}

output "lambda_function_version" {
  description = "Latest published version of the Lambda Function"
  value       = aws_lambda_function.password_generator.version
}

output "lambda_function_last_modified" {
  description = "Date this Lambda function was last modified"
  value       = aws_lambda_function.password_generator.last_modified
}

# S3 Bucket Information
output "s3_bucket_name" {
  description = "Name of the S3 bucket storing generated passwords"
  value       = aws_s3_bucket.password_storage.id
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket"
  value       = aws_s3_bucket.password_storage.arn
}

output "s3_bucket_domain_name" {
  description = "Bucket domain name for S3 bucket"
  value       = aws_s3_bucket.password_storage.bucket_domain_name
}

output "s3_bucket_regional_domain_name" {
  description = "Regional domain name for S3 bucket"
  value       = aws_s3_bucket.password_storage.bucket_regional_domain_name
}

# IAM Role Information
output "lambda_execution_role_arn" {
  description = "ARN of the IAM role used by Lambda function"
  value       = aws_iam_role.lambda_execution_role.arn
}

output "lambda_execution_role_name" {
  description = "Name of the IAM role used by Lambda function"
  value       = aws_iam_role.lambda_execution_role.name
}

# CloudWatch Information
output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch Log Group for Lambda function"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch Log Group"
  value       = aws_cloudwatch_log_group.lambda_logs.arn
}

# Usage Information
output "test_invocation_payload" {
  description = "Sample JSON payload for testing the Lambda function"
  value = jsonencode({
    length            = 16
    include_uppercase = true
    include_lowercase = true
    include_numbers   = true
    include_symbols   = true
    name             = "test-password"
  })
}

output "aws_cli_test_command" {
  description = "AWS CLI command to test the deployed Lambda function"
  value = join(" ", [
    "aws lambda invoke",
    "--function-name", aws_lambda_function.password_generator.function_name,
    "--payload", "'${jsonencode({
      length            = 20
      include_uppercase = true
      include_lowercase = true
      include_numbers   = true
      include_symbols   = false
      name             = "terraform-test"
    })}'",
    "response.json && cat response.json"
  ])
}

output "curl_test_command" {
  description = "cURL command to test the Lambda function URL"
  value = join(" ", [
    "curl -X POST",
    "'${aws_lambda_function_url.password_generator.function_url}'",
    "-H 'Content-Type: application/json'",
    "-d '${jsonencode({
      length            = 16
      include_uppercase = true
      include_lowercase = true
      include_numbers   = true
      include_symbols   = true
      name             = "curl-test"
    })}'"
  ])
}

# Security Information
output "s3_bucket_encryption" {
  description = "S3 bucket server-side encryption configuration"
  value = {
    algorithm           = "AES256"
    bucket_key_enabled = true
  }
}

output "s3_versioning_status" {
  description = "S3 bucket versioning status"
  value       = var.s3_enable_versioning ? "Enabled" : "Disabled"
}

output "resource_tags" {
  description = "Common tags applied to all resources"
  value       = local.common_tags
}

# Cost Information
output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown (USD, approximate)"
  value = {
    lambda_requests_1000 = "0.0000002 per request (first 1 million free)"
    lambda_compute_gb_s  = "0.0000166667 per GB-second"
    s3_storage_gb        = "0.023 per GB (Standard)"
    s3_requests_1000     = "0.0004 per 1000 PUT requests"
    cloudwatch_logs_gb   = "0.50 per GB ingested"
    total_note          = "Actual costs depend on usage patterns. Most testing will be covered by AWS Free Tier."
  }
}

# Regional Information
output "deployment_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "aws_account_id" {
  description = "AWS Account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
  sensitive   = true
}