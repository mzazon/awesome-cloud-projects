# Output values for the Simple Color Palette Generator infrastructure
# These outputs provide important information for verification and integration

output "function_url" {
  description = "The HTTPS URL endpoint for the color palette generator"
  value       = aws_lambda_function_url.palette_generator_url.function_url
}

output "function_name" {
  description = "Name of the deployed Lambda function"
  value       = aws_lambda_function.palette_generator.function_name
}

output "function_arn" {
  description = "ARN of the deployed Lambda function"
  value       = aws_lambda_function.palette_generator.arn
}

output "s3_bucket_name" {
  description = "Name of the S3 bucket storing color palettes"
  value       = aws_s3_bucket.palette_storage.bucket
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket storing color palettes"
  value       = aws_s3_bucket.palette_storage.arn
}

output "s3_bucket_domain_name" {
  description = "Domain name of the S3 bucket"
  value       = aws_s3_bucket.palette_storage.bucket_domain_name
}

output "iam_role_name" {
  description = "Name of the IAM role used by the Lambda function"
  value       = aws_iam_role.lambda_execution_role.name
}

output "iam_role_arn" {
  description = "ARN of the IAM role used by the Lambda function"
  value       = aws_iam_role.lambda_execution_role.arn
}

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch Log Group for Lambda function logs"
  value       = var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.lambda_logs[0].name : null
}

output "resource_suffix" {
  description = "Random suffix used for resource naming"
  value       = local.resource_suffix
}

# Usage examples and testing information
output "usage_examples" {
  description = "Examples of how to use the color palette generator API"
  value = {
    complementary_palette = "${aws_lambda_function_url.palette_generator_url.function_url}?type=complementary"
    analogous_palette    = "${aws_lambda_function_url.palette_generator_url.function_url}?type=analogous"
    triadic_palette      = "${aws_lambda_function_url.palette_generator_url.function_url}?type=triadic"
    random_palette       = "${aws_lambda_function_url.palette_generator_url.function_url}?type=random"
    default_palette      = aws_lambda_function_url.palette_generator_url.function_url
  }
}

# Resource costs and management information
output "resource_information" {
  description = "Information about deployed resources and costs"
  value = {
    lambda_timeout      = "${var.lambda_timeout} seconds"
    lambda_memory       = "${var.lambda_memory_size} MB"
    s3_versioning      = var.enable_s3_versioning ? "Enabled" : "Disabled"
    log_retention      = var.enable_cloudwatch_logs ? "${var.log_retention_days} days" : "Disabled"
    estimated_cost     = "~$0.01-$0.05 per month for typical usage (AWS Free Tier eligible)"
  }
}

# Security and compliance information
output "security_features" {
  description = "Security features implemented in this deployment"
  value = {
    s3_encryption           = "AES256 server-side encryption enabled"
    s3_public_access_block = "All public access blocked"
    iam_principle          = "Least privilege access implemented"
    cors_configuration     = "CORS configured for web application integration"
    function_url_auth      = "Public access with CORS protection"
  }
}

# Validation commands for testing the deployment
output "validation_commands" {
  description = "Commands to validate the deployment"
  value = {
    test_function = "curl -s '${aws_lambda_function_url.palette_generator_url.function_url}?type=complementary' | jq '.'"
    list_palettes = "aws s3 ls s3://${aws_s3_bucket.palette_storage.bucket}/palettes/ --human-readable"
    check_logs    = var.enable_cloudwatch_logs ? "aws logs describe-log-groups --log-group-name-prefix '/aws/lambda/${local.function_name}'" : "CloudWatch logs disabled"
    function_info = "aws lambda get-function --function-name ${local.function_name}"
  }
}