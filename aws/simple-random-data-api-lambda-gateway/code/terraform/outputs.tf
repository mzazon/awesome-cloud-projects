# Outputs for Simple Random Data API Infrastructure
# These outputs provide important information about the deployed resources

# API Gateway URL - Primary endpoint for the random data API
output "api_gateway_url" {
  description = "URL of the API Gateway endpoint for random data API"
  value       = "https://${aws_api_gateway_rest_api.random_data_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${aws_api_gateway_stage.main.stage_name}/random"
}

# API Gateway REST API ID - Useful for further configuration or integration
output "api_gateway_id" {
  description = "ID of the API Gateway REST API"
  value       = aws_api_gateway_rest_api.random_data_api.id
}

# API Gateway REST API name
output "api_gateway_name" {
  description = "Name of the API Gateway REST API"
  value       = aws_api_gateway_rest_api.random_data_api.name
}

# API Gateway stage name
output "api_stage_name" {
  description = "Name of the API Gateway stage"
  value       = aws_api_gateway_stage.main.stage_name
}

# Lambda function details
output "lambda_function_name" {
  description = "Name of the Lambda function"
  value       = aws_lambda_function.random_data_api.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function"
  value       = aws_lambda_function.random_data_api.arn
}

output "lambda_function_invoke_arn" {
  description = "Invoke ARN of the Lambda function"
  value       = aws_lambda_function.random_data_api.invoke_arn
}

# Lambda execution role details
output "lambda_execution_role_name" {
  description = "Name of the Lambda execution role"
  value       = aws_iam_role.lambda_execution_role.name
}

output "lambda_execution_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_execution_role.arn
}

# CloudWatch Log Groups
output "lambda_log_group_name" {
  description = "Name of the Lambda function CloudWatch log group"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

output "lambda_log_group_arn" {
  description = "ARN of the Lambda function CloudWatch log group"
  value       = aws_cloudwatch_log_group.lambda_logs.arn
}

output "api_gateway_log_group_name" {
  description = "Name of the API Gateway CloudWatch log group (if logging enabled)"
  value       = var.enable_api_logging ? aws_cloudwatch_log_group.api_gateway_logs[0].name : null
}

output "api_gateway_log_group_arn" {
  description = "ARN of the API Gateway CloudWatch log group (if logging enabled)"
  value       = var.enable_api_logging ? aws_cloudwatch_log_group.api_gateway_logs[0].arn : null
}

# Resource naming and identification
output "resource_name_prefix" {
  description = "Common name prefix used for all resources"
  value       = local.name_prefix
}

output "random_suffix" {
  description = "Random suffix used for unique resource naming"
  value       = random_id.suffix.hex
}

# AWS Account and Region information
output "aws_account_id" {
  description = "AWS Account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

output "aws_region" {
  description = "AWS Region where resources are deployed"
  value       = data.aws_region.current.name
}

# Sample API usage examples
output "sample_api_calls" {
  description = "Sample API calls to test the deployed endpoint"
  value = {
    "random_quote"  = "curl -X GET '${aws_api_gateway_rest_api.random_data_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${aws_api_gateway_stage.main.stage_name}/random?type=quote'"
    "random_number" = "curl -X GET '${aws_api_gateway_rest_api.random_data_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${aws_api_gateway_stage.main.stage_name}/random?type=number'"
    "random_color"  = "curl -X GET '${aws_api_gateway_rest_api.random_data_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${aws_api_gateway_stage.main.stage_name}/random?type=color'"
    "default_call"  = "curl -X GET '${aws_api_gateway_rest_api.random_data_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${aws_api_gateway_stage.main.stage_name}/random'"
  }
}

# Configuration summary
output "deployment_summary" {
  description = "Summary of the deployed infrastructure"
  value = {
    project_name     = var.project_name
    environment      = var.environment
    api_endpoint     = "https://${aws_api_gateway_rest_api.random_data_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${aws_api_gateway_stage.main.stage_name}/random"
    lambda_runtime   = var.lambda_runtime
    lambda_memory    = var.lambda_memory_size
    lambda_timeout   = var.lambda_timeout
    api_logging      = var.enable_api_logging
    cors_enabled     = var.enable_cors
    log_retention    = var.log_retention_days
  }
}