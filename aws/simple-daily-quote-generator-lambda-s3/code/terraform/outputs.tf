# S3 bucket information
output "s3_bucket_name" {
  description = "Name of the S3 bucket storing quote data"
  value       = aws_s3_bucket.quotes_bucket.id
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket storing quote data"
  value       = aws_s3_bucket.quotes_bucket.arn
}

output "s3_bucket_domain_name" {
  description = "Domain name of the S3 bucket"
  value       = aws_s3_bucket.quotes_bucket.bucket_domain_name
}

output "quotes_object_key" {
  description = "S3 object key for the quotes JSON file"
  value       = aws_s3_object.quotes_data.key
}

output "quotes_object_etag" {
  description = "ETag of the quotes JSON file"
  value       = aws_s3_object.quotes_data.etag
}

# Lambda function information
output "lambda_function_name" {
  description = "Name of the Lambda function"
  value       = aws_lambda_function.quote_generator.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function"
  value       = aws_lambda_function.quote_generator.arn
}

output "lambda_function_invoke_arn" {
  description = "Invoke ARN of the Lambda function"
  value       = aws_lambda_function.quote_generator.invoke_arn
}

output "lambda_function_url" {
  description = "HTTPS URL for direct Lambda function invocation"
  value       = aws_lambda_function_url.quote_generator_url.function_url
}

output "lambda_function_url_id" {
  description = "ID of the Lambda function URL configuration"
  value       = aws_lambda_function_url.quote_generator_url.url_id
}

# IAM role information
output "lambda_execution_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_execution_role.arn
}

output "lambda_execution_role_name" {
  description = "Name of the Lambda execution role"
  value       = aws_iam_role.lambda_execution_role.name
}

# CloudWatch information
output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for Lambda function"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group for Lambda function"
  value       = aws_cloudwatch_log_group.lambda_logs.arn
}

# Configuration information
output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "aws_account_id" {
  description = "AWS account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

output "resource_name_suffix" {
  description = "Random suffix used for resource naming"
  value       = local.name_suffix
}

# API testing information
output "test_commands" {
  description = "Commands to test the deployed API"
  value = {
    curl_test = "curl -s ${aws_lambda_function_url.quote_generator_url.function_url}"
    aws_cli_test = "aws lambda invoke --function-name ${aws_lambda_function.quote_generator.function_name} --payload '{}' response.json && cat response.json"
    multiple_requests = "for i in {1..3}; do echo \"Request $i:\"; curl -s ${aws_lambda_function_url.quote_generator_url.function_url} | jq '.quote'; echo; done"
  }
}

# Cost estimation information
output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown (USD)"
  value = {
    lambda_requests = "First 1M requests/month: FREE (AWS Free Tier)"
    lambda_compute = "First 400,000 GB-seconds/month: FREE (AWS Free Tier)"
    s3_storage = "First 5 GB/month: FREE (AWS Free Tier)"
    s3_requests = "2,000 GET requests/month: FREE (AWS Free Tier)"
    cloudwatch_logs = "First 5 GB ingested/month: FREE (AWS Free Tier)"
    total_estimate = "$0.01-$0.05/month for typical usage beyond free tier"
  }
}

# Security information
output "security_features" {
  description = "Security features implemented"
  value = {
    s3_encryption = "AES-256 server-side encryption enabled"
    s3_public_access = "All public access blocked"
    iam_permissions = "Least privilege - Lambda can only read from specific S3 bucket"
    https_only = "Lambda Function URL uses HTTPS only"
    cors_configured = "CORS properly configured for web access"
  }
}

# Validation commands
output "validation_commands" {
  description = "Commands to validate the deployment"
  value = {
    check_s3_bucket = "aws s3 ls s3://${aws_s3_bucket.quotes_bucket.id}"
    check_lambda = "aws lambda get-function --function-name ${aws_lambda_function.quote_generator.function_name}"
    check_iam_role = "aws iam get-role --role-name ${aws_iam_role.lambda_execution_role.name}"
    test_api = "curl -s ${aws_lambda_function_url.quote_generator_url.function_url} | jq ."
  }
}