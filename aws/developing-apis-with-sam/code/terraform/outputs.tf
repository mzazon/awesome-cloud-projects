# API Gateway outputs
output "api_gateway_url" {
  description = "Base URL for the API Gateway"
  value       = "https://${aws_api_gateway_rest_api.users_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${aws_api_gateway_stage.api_stage.stage_name}/"
}

output "api_gateway_id" {
  description = "ID of the API Gateway REST API"
  value       = aws_api_gateway_rest_api.users_api.id
}

output "api_gateway_execution_arn" {
  description = "Execution ARN of the API Gateway"
  value       = aws_api_gateway_rest_api.users_api.execution_arn
}

output "api_gateway_stage_name" {
  description = "Name of the API Gateway stage"
  value       = aws_api_gateway_stage.api_stage.stage_name
}

# DynamoDB outputs
output "dynamodb_table_name" {
  description = "Name of the DynamoDB table"
  value       = aws_dynamodb_table.users.name
}

output "dynamodb_table_arn" {
  description = "ARN of the DynamoDB table"
  value       = aws_dynamodb_table.users.arn
}

# Lambda function outputs
output "lambda_function_names" {
  description = "Names of all Lambda functions"
  value = {
    for k, v in aws_lambda_function.api_functions : k => v.function_name
  }
}

output "lambda_function_arns" {
  description = "ARNs of all Lambda functions"
  value = {
    for k, v in aws_lambda_function.api_functions : k => v.arn
  }
}

output "lambda_function_invoke_arns" {
  description = "Invoke ARNs of all Lambda functions"
  value = {
    for k, v in aws_lambda_function.api_functions : k => v.invoke_arn
  }
}

# IAM outputs
output "lambda_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_role.arn
}

output "lambda_role_name" {
  description = "Name of the Lambda execution role"
  value       = aws_iam_role.lambda_role.name
}

# CloudWatch outputs
output "lambda_log_groups" {
  description = "CloudWatch log group names for Lambda functions"
  value = {
    for k, v in aws_cloudwatch_log_group.lambda_logs : k => v.name
  }
}

output "api_gateway_log_group" {
  description = "CloudWatch log group name for API Gateway (if enabled)"
  value       = var.enable_api_gateway_logging ? aws_cloudwatch_log_group.api_gateway_logs[0].name : null
}

output "cloudwatch_dashboard_url" {
  description = "URL to the CloudWatch dashboard"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.api_dashboard.dashboard_name}"
}

# Resource identifiers
output "resource_suffix" {
  description = "Random suffix used for resource naming"
  value       = local.resource_suffix
}

output "project_name" {
  description = "Project name used for resource naming"
  value       = var.project_name
}

output "environment" {
  description = "Environment name"
  value       = var.environment
}

# API endpoints for testing
output "api_endpoints" {
  description = "Complete API endpoint URLs for testing"
  value = {
    list_users   = "https://${aws_api_gateway_rest_api.users_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${aws_api_gateway_stage.api_stage.stage_name}/users"
    create_user  = "https://${aws_api_gateway_rest_api.users_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${aws_api_gateway_stage.api_stage.stage_name}/users"
    get_user     = "https://${aws_api_gateway_rest_api.users_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${aws_api_gateway_stage.api_stage.stage_name}/users/{id}"
    update_user  = "https://${aws_api_gateway_rest_api.users_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${aws_api_gateway_stage.api_stage.stage_name}/users/{id}"
    delete_user  = "https://${aws_api_gateway_rest_api.users_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${aws_api_gateway_stage.api_stage.stage_name}/users/{id}"
  }
}

# curl command examples for testing
output "curl_examples" {
  description = "Example curl commands for testing the API"
  value = {
    list_users = "curl -X GET \"https://${aws_api_gateway_rest_api.users_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${aws_api_gateway_stage.api_stage.stage_name}/users\""
    create_user = "curl -X POST \"https://${aws_api_gateway_rest_api.users_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${aws_api_gateway_stage.api_stage.stage_name}/users\" -H \"Content-Type: application/json\" -d '{\"name\": \"John Doe\", \"email\": \"john@example.com\", \"age\": 30}'"
    get_user = "curl -X GET \"https://${aws_api_gateway_rest_api.users_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${aws_api_gateway_stage.api_stage.stage_name}/users/{user_id}\""
    update_user = "curl -X PUT \"https://${aws_api_gateway_rest_api.users_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${aws_api_gateway_stage.api_stage.stage_name}/users/{user_id}\" -H \"Content-Type: application/json\" -d '{\"name\": \"Jane Doe\", \"age\": 31}'"
    delete_user = "curl -X DELETE \"https://${aws_api_gateway_rest_api.users_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${aws_api_gateway_stage.api_stage.stage_name}/users/{user_id}\""
  }
}

# Cost estimation guidance
output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown (USD) for typical usage"
  value = {
    api_gateway_requests = "First 1M requests: Free, then $3.50 per million requests"
    lambda_requests      = "First 1M requests: Free, then $0.20 per million requests"
    lambda_compute       = "First 400,000 GB-seconds: Free, then $0.0000166667 per GB-second"
    dynamodb_storage     = "First 25GB: Free, then $0.25 per GB per month"
    dynamodb_requests    = "Pay-per-request: $0.25 per million read requests, $1.25 per million write requests"
    cloudwatch_logs      = "$0.50 per GB ingested, $0.03 per GB stored per month"
    note                 = "Costs shown are for us-east-1 region and may vary by region and usage patterns"
  }
}