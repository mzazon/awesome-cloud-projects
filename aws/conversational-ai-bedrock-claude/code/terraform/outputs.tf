# Outputs for the conversational AI application

output "api_gateway_url" {
  description = "URL of the API Gateway endpoint for the conversational AI application"
  value       = "https://${aws_api_gateway_rest_api.conversational_ai_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${var.api_stage_name}"
}

output "chat_endpoint" {
  description = "Complete URL for the chat endpoint"
  value       = "https://${aws_api_gateway_rest_api.conversational_ai_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${var.api_stage_name}/chat"
}

output "api_gateway_id" {
  description = "ID of the API Gateway REST API"
  value       = aws_api_gateway_rest_api.conversational_ai_api.id
}

output "api_gateway_arn" {
  description = "ARN of the API Gateway REST API"
  value       = aws_api_gateway_rest_api.conversational_ai_api.arn
}

output "lambda_function_name" {
  description = "Name of the Lambda function handling conversational AI requests"
  value       = aws_lambda_function.conversational_ai_handler.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function"
  value       = aws_lambda_function.conversational_ai_handler.arn
}

output "lambda_function_invoke_arn" {
  description = "Invoke ARN of the Lambda function"
  value       = aws_lambda_function.conversational_ai_handler.invoke_arn
}

output "lambda_log_group_name" {
  description = "Name of the CloudWatch Log Group for Lambda function"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

output "dynamodb_table_name" {
  description = "Name of the DynamoDB table storing conversation history"
  value       = aws_dynamodb_table.conversations.name
}

output "dynamodb_table_arn" {
  description = "ARN of the DynamoDB table"
  value       = aws_dynamodb_table.conversations.arn
}

output "iam_role_name" {
  description = "Name of the IAM role used by Lambda function"
  value       = aws_iam_role.lambda_execution_role.name
}

output "iam_role_arn" {
  description = "ARN of the IAM role used by Lambda function"
  value       = aws_iam_role.lambda_execution_role.arn
}

output "claude_model_id" {
  description = "Claude model ID being used by the application"
  value       = var.claude_model_id
}

output "api_gateway_stage_name" {
  description = "Name of the API Gateway stage"
  value       = aws_api_gateway_stage.conversational_ai_stage.stage_name
}

output "api_gateway_log_group_name" {
  description = "Name of the CloudWatch Log Group for API Gateway access logs"
  value       = aws_cloudwatch_log_group.api_gateway_logs.name
}

output "api_gateway_execution_log_group_name" {
  description = "Name of the CloudWatch Log Group for API Gateway execution logs"
  value       = aws_cloudwatch_log_group.api_gateway_execution_logs.name
}

output "xray_tracing_enabled" {
  description = "Whether X-Ray tracing is enabled for the application"
  value       = var.enable_xray_tracing
}

output "cors_enabled" {
  description = "Whether CORS is enabled for the API"
  value       = var.enable_cors
}

output "available_bedrock_models" {
  description = "List of available Anthropic models in Bedrock"
  value       = data.aws_bedrock_foundation_models.claude_models.model_summaries[*].model_id
}

output "resource_prefix" {
  description = "Resource prefix used for naming"
  value       = local.resource_prefix
}

output "resource_suffix" {
  description = "Random suffix used for unique resource naming"
  value       = local.resource_suffix
}

output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "aws_account_id" {
  description = "AWS account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

# Test and validation outputs
output "test_curl_command" {
  description = "Example curl command to test the API"
  value = <<-EOT
    curl -X POST https://${aws_api_gateway_rest_api.conversational_ai_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${var.api_stage_name}/chat \
      -H "Content-Type: application/json" \
      -d '{
        "message": "Hello! What can you help me with?",
        "session_id": "test-session-123",
        "user_id": "test-user"
      }'
  EOT
}

output "configuration_summary" {
  description = "Summary of key configuration values"
  value = {
    environment                = var.environment
    project_name              = var.project_name
    claude_model_id          = var.claude_model_id
    lambda_runtime           = var.lambda_runtime
    lambda_timeout           = var.lambda_timeout
    lambda_memory_size       = var.lambda_memory_size
    max_tokens              = var.max_tokens
    temperature             = var.temperature
    conversation_history_limit = var.conversation_history_limit
    dynamodb_billing_mode   = var.dynamodb_billing_mode
    api_stage_name          = var.api_stage_name
    xray_tracing_enabled    = var.enable_xray_tracing
    cors_enabled            = var.enable_cors
    log_retention_days      = var.log_retention_days
  }
}