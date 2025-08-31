# Outputs for Simple Timezone Converter with Lambda and API Gateway
# This file defines output values that can be used by other Terraform configurations or displayed after apply

# Lambda Function Outputs
output "lambda_function_name" {
  description = "Name of the created Lambda function"
  value       = aws_lambda_function.timezone_converter.function_name
}

output "lambda_function_arn" {
  description = "ARN of the created Lambda function"
  value       = aws_lambda_function.timezone_converter.arn
}

output "lambda_function_qualified_arn" {
  description = "Qualified ARN of the Lambda function (includes version)"
  value       = aws_lambda_function.timezone_converter.qualified_arn
}

output "lambda_function_invoke_arn" {
  description = "Invoke ARN of the Lambda function"
  value       = aws_lambda_function.timezone_converter.invoke_arn
}

output "lambda_function_runtime" {
  description = "Runtime of the Lambda function"
  value       = aws_lambda_function.timezone_converter.runtime
}

output "lambda_function_memory_size" {
  description = "Memory size of the Lambda function"
  value       = aws_lambda_function.timezone_converter.memory_size
}

output "lambda_function_timeout" {
  description = "Timeout configuration of the Lambda function"
  value       = aws_lambda_function.timezone_converter.timeout
}

output "lambda_function_last_modified" {
  description = "Date the Lambda function was last modified"
  value       = aws_lambda_function.timezone_converter.last_modified
}

# IAM Role Outputs
output "lambda_role_name" {
  description = "Name of the Lambda execution IAM role"
  value       = aws_iam_role.lambda_execution_role.name
}

output "lambda_role_arn" {
  description = "ARN of the Lambda execution IAM role"
  value       = aws_iam_role.lambda_execution_role.arn
}

# API Gateway Outputs
output "api_gateway_id" {
  description = "ID of the API Gateway REST API"
  value       = aws_api_gateway_rest_api.timezone_converter_api.id
}

output "api_gateway_name" {
  description = "Name of the API Gateway REST API"
  value       = aws_api_gateway_rest_api.timezone_converter_api.name
}

output "api_gateway_root_resource_id" {
  description = "Root resource ID of the API Gateway"
  value       = aws_api_gateway_rest_api.timezone_converter_api.root_resource_id
}

output "api_gateway_execution_arn" {
  description = "Execution ARN of the API Gateway"
  value       = aws_api_gateway_rest_api.timezone_converter_api.execution_arn
}

output "api_gateway_created_date" {
  description = "Creation date of the API Gateway"
  value       = aws_api_gateway_rest_api.timezone_converter_api.created_date
}

# API Gateway Deployment Outputs
output "api_gateway_deployment_id" {
  description = "ID of the API Gateway deployment"
  value       = aws_api_gateway_deployment.timezone_converter_deployment.id
}

output "api_gateway_stage_name" {
  description = "Name of the API Gateway deployment stage"
  value       = aws_api_gateway_stage.timezone_converter_stage.stage_name
}

output "api_gateway_stage_url" {
  description = "URL of the API Gateway stage"
  value       = aws_api_gateway_stage.timezone_converter_stage.invoke_url
}

# Complete API Endpoint URLs
output "api_endpoint_url" {
  description = "Complete URL for the timezone converter API endpoint"
  value       = "${aws_api_gateway_stage.timezone_converter_stage.invoke_url}/convert"
}

output "api_base_url" {
  description = "Base URL of the API Gateway"
  value       = aws_api_gateway_stage.timezone_converter_stage.invoke_url
}

# Resource Naming and Tags
output "resource_suffix" {
  description = "Suffix used for resource naming"
  value       = local.resource_suffix
}

output "resource_tags" {
  description = "Common tags applied to all resources"
  value       = local.common_tags
}

# CloudWatch Logs Outputs
output "lambda_log_group_name" {
  description = "Name of the Lambda function's CloudWatch log group"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

output "lambda_log_group_arn" {
  description = "ARN of the Lambda function's CloudWatch log group"
  value       = aws_cloudwatch_log_group.lambda_logs.arn
}

output "lambda_log_retention_days" {
  description = "Log retention period in days"
  value       = aws_cloudwatch_log_group.lambda_logs.retention_in_days
}

# API Gateway Resource Outputs
output "convert_resource_id" {
  description = "ID of the /convert API Gateway resource"
  value       = aws_api_gateway_resource.convert_resource.id
}

output "convert_resource_path" {
  description = "Path of the /convert API Gateway resource"
  value       = aws_api_gateway_resource.convert_resource.path
}

# Lambda Permission Outputs
output "lambda_permission_statement_id" {
  description = "Statement ID of the Lambda permission for API Gateway"
  value       = aws_lambda_permission.api_gateway_invoke.statement_id
}

# Testing and Validation Outputs
output "curl_test_command" {
  description = "Sample curl command to test the API endpoint"
  value = <<-EOT
curl -X POST ${aws_api_gateway_stage.timezone_converter_stage.invoke_url}/convert \
  -H "Content-Type: application/json" \
  -d '{
    "timestamp": "2025-07-12T15:30:00",
    "from_timezone": "UTC",
    "to_timezone": "America/New_York"
  }'
EOT
}

output "lambda_test_command" {
  description = "AWS CLI command to test the Lambda function directly"
  value = <<-EOT
aws lambda invoke \
  --function-name ${aws_lambda_function.timezone_converter.function_name} \
  --payload '{"timestamp":"2025-07-12T15:30:00","from_timezone":"UTC","to_timezone":"America/New_York"}' \
  response.json
EOT
}

# Deployment Information
output "deployment_summary" {
  description = "Summary of the deployed resources"
  value = {
    api_endpoint    = "${aws_api_gateway_stage.timezone_converter_stage.invoke_url}/convert"
    lambda_function = aws_lambda_function.timezone_converter.function_name
    lambda_runtime  = aws_lambda_function.timezone_converter.runtime
    api_stage      = aws_api_gateway_stage.timezone_converter_stage.stage_name
    environment    = var.environment
  }
}

# Cost Estimation Information
output "estimated_monthly_cost" {
  description = "Estimated monthly cost information (in USD, approximate)"
  value = {
    lambda_requests = "1M requests/month = $0.20"
    lambda_duration = "100ms avg duration = $0.0000167 per request"
    api_gateway     = "1M requests/month = $3.50"
    cloudwatch_logs = "1GB logs/month = $0.50"
    total_estimate  = "~$4.20/month for 1M requests"
    free_tier_note  = "First 12 months include significant free tier allowances"
  }
}