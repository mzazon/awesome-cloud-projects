# outputs.tf
# Output values for AWS QR Code Generator infrastructure

# API Gateway information
output "api_gateway_url" {
  description = "The base URL for the API Gateway"
  value       = "https://${aws_api_gateway_rest_api.qr_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${aws_api_gateway_stage.api_stage.stage_name}"
}

output "api_gateway_generate_endpoint" {
  description = "The full URL for the QR code generation endpoint"
  value       = "https://${aws_api_gateway_rest_api.qr_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${aws_api_gateway_stage.api_stage.stage_name}/generate"
}

output "api_gateway_id" {
  description = "ID of the API Gateway"
  value       = aws_api_gateway_rest_api.qr_api.id
}

output "api_gateway_arn" {
  description = "ARN of the API Gateway"
  value       = aws_api_gateway_rest_api.qr_api.arn
}

# Lambda function information
output "lambda_function_name" {
  description = "Name of the Lambda function"
  value       = aws_lambda_function.qr_generator.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function"
  value       = aws_lambda_function.qr_generator.arn
}

output "lambda_function_invoke_arn" {
  description = "Invoke ARN of the Lambda function"
  value       = aws_lambda_function.qr_generator.invoke_arn
}

output "lambda_function_version" {
  description = "Latest published version of the Lambda function"
  value       = aws_lambda_function.qr_generator.version
}

# S3 bucket information
output "s3_bucket_name" {
  description = "Name of the S3 bucket storing QR codes"
  value       = aws_s3_bucket.qr_bucket.id
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket"
  value       = aws_s3_bucket.qr_bucket.arn
}

output "s3_bucket_domain_name" {
  description = "Domain name of the S3 bucket"
  value       = aws_s3_bucket.qr_bucket.bucket_domain_name
}

output "s3_bucket_regional_domain_name" {
  description = "Regional domain name of the S3 bucket"
  value       = aws_s3_bucket.qr_bucket.bucket_regional_domain_name
}

output "s3_bucket_website_endpoint" {
  description = "Website endpoint of the S3 bucket"
  value       = aws_s3_bucket.qr_bucket.website_endpoint
}

# IAM role information
output "lambda_role_name" {
  description = "Name of the Lambda execution role"
  value       = aws_iam_role.lambda_role.name
}

output "lambda_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_role.arn
}

# CloudWatch log groups
output "lambda_log_group_name" {
  description = "Name of the Lambda CloudWatch log group"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

output "api_log_group_name" {
  description = "Name of the API Gateway CloudWatch log group"
  value       = aws_cloudwatch_log_group.api_logs.name
}

# Resource naming information
output "resource_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_string.suffix.result
}

output "common_tags" {
  description = "Common tags applied to all resources"
  value       = local.common_tags
}

# Testing information
output "sample_curl_command" {
  description = "Sample curl command to test the QR code generator"
  value = <<-EOT
    curl -X POST ${aws_api_gateway_rest_api.qr_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${aws_api_gateway_stage.api_stage.stage_name}/generate \
      -H "Content-Type: application/json" \
      -d '{"text": "Hello, World! This is my QR code."}'
  EOT
}

# Cost estimation information
output "estimated_monthly_cost" {
  description = "Estimated monthly cost for typical usage (USD)"
  value = {
    lambda_requests_1000 = "$0.20"
    lambda_compute_gb_s  = "$0.0000166667 per GB-second"
    api_gateway_requests = "$3.50 per million requests"
    s3_storage_gb       = "$0.023 per GB"
    cloudwatch_logs     = "$0.50 per GB ingested"
    total_estimate      = "$1-5 for light usage"
  }
}

# Security information
output "security_considerations" {
  description = "Important security considerations for this deployment"
  value = {
    s3_public_access = "S3 bucket allows public read access for QR code images"
    api_authentication = "API Gateway has no authentication - consider adding API keys or Cognito"
    lambda_permissions = "Lambda has minimal S3 write permissions"
    cors_enabled = var.enable_cors ? "CORS is enabled for web applications" : "CORS is disabled"
    encryption = "S3 server-side encryption is enabled with AES256"
  }
}