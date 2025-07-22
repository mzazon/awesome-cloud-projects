# WebSocket API Outputs
output "websocket_api_id" {
  description = "ID of the WebSocket API"
  value       = aws_apigatewayv2_api.websocket_api.id
}

output "websocket_api_endpoint" {
  description = "WebSocket API endpoint URL"
  value       = "wss://${aws_apigatewayv2_api.websocket_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${var.stage_name}"
}

output "websocket_api_execution_arn" {
  description = "Execution ARN of the WebSocket API"
  value       = aws_apigatewayv2_api.websocket_api.execution_arn
}

output "api_gateway_stage_name" {
  description = "Name of the API Gateway stage"
  value       = aws_apigatewayv2_stage.websocket_stage.name
}

output "api_gateway_stage_invoke_url" {
  description = "Invoke URL for the API Gateway stage"
  value       = aws_apigatewayv2_stage.websocket_stage.invoke_url
}

# Lambda Function Outputs
output "connect_function_name" {
  description = "Name of the WebSocket connect handler Lambda function"
  value       = aws_lambda_function.connect_handler.function_name
}

output "connect_function_arn" {
  description = "ARN of the WebSocket connect handler Lambda function"
  value       = aws_lambda_function.connect_handler.arn
}

output "disconnect_function_name" {
  description = "Name of the WebSocket disconnect handler Lambda function"
  value       = aws_lambda_function.disconnect_handler.function_name
}

output "disconnect_function_arn" {
  description = "ARN of the WebSocket disconnect handler Lambda function"
  value       = aws_lambda_function.disconnect_handler.arn
}

output "message_function_name" {
  description = "Name of the WebSocket message handler Lambda function"
  value       = aws_lambda_function.message_handler.function_name
}

output "message_function_arn" {
  description = "ARN of the WebSocket message handler Lambda function"
  value       = aws_lambda_function.message_handler.arn
}

# DynamoDB Table Outputs
output "connections_table_name" {
  description = "Name of the connections DynamoDB table"
  value       = aws_dynamodb_table.connections.name
}

output "connections_table_arn" {
  description = "ARN of the connections DynamoDB table"
  value       = aws_dynamodb_table.connections.arn
}

output "rooms_table_name" {
  description = "Name of the rooms DynamoDB table"
  value       = aws_dynamodb_table.rooms.name
}

output "rooms_table_arn" {
  description = "ARN of the rooms DynamoDB table"
  value       = aws_dynamodb_table.rooms.arn
}

output "messages_table_name" {
  description = "Name of the messages DynamoDB table"
  value       = aws_dynamodb_table.messages.name
}

output "messages_table_arn" {
  description = "ARN of the messages DynamoDB table"
  value       = aws_dynamodb_table.messages.arn
}

# IAM Role Outputs
output "lambda_role_name" {
  description = "Name of the Lambda execution role"
  value       = aws_iam_role.lambda_role.name
}

output "lambda_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_role.arn
}

# CloudWatch Log Group Outputs
output "connect_log_group_name" {
  description = "Name of the connect handler CloudWatch log group"
  value       = aws_cloudwatch_log_group.connect_logs.name
}

output "disconnect_log_group_name" {
  description = "Name of the disconnect handler CloudWatch log group"
  value       = aws_cloudwatch_log_group.disconnect_logs.name
}

output "message_log_group_name" {
  description = "Name of the message handler CloudWatch log group"
  value       = aws_cloudwatch_log_group.message_logs.name
}

# Security Outputs
output "kms_key_id" {
  description = "ID of the KMS key used for encryption"
  value       = var.enable_encryption ? aws_kms_key.websocket_key[0].id : null
}

output "kms_key_arn" {
  description = "ARN of the KMS key used for encryption"
  value       = var.enable_encryption ? aws_kms_key.websocket_key[0].arn : null
}

output "kms_key_alias" {
  description = "Alias of the KMS key used for encryption"
  value       = var.enable_encryption ? aws_kms_alias.websocket_key_alias[0].name : null
}

# Configuration Outputs
output "resource_suffix" {
  description = "Random suffix used for resource naming"
  value       = local.resource_suffix
}

output "name_prefix" {
  description = "Prefix used for resource naming"
  value       = local.name_prefix
}

output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "aws_account_id" {
  description = "AWS account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

# Route Configuration Outputs
output "custom_routes" {
  description = "List of custom routes created"
  value       = var.custom_routes
}

output "route_selection_expression" {
  description = "Route selection expression used by the WebSocket API"
  value       = var.route_selection_expression
}

# Testing and Connection Information
output "test_connection_url" {
  description = "Sample WebSocket connection URL for testing"
  value       = "wss://${aws_apigatewayv2_api.websocket_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${var.stage_name}?userId=testuser&username=TestUser&roomId=general&token=valid_test_token"
}

output "websocket_client_test_command" {
  description = "Command to test WebSocket connection using wscat"
  value       = "wscat -c 'wss://${aws_apigatewayv2_api.websocket_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${var.stage_name}?userId=testuser&username=TestUser&roomId=general&token=valid_test_token'"
}

# Monitoring and Logging
output "cloudwatch_dashboard_url" {
  description = "URL to CloudWatch dashboard for monitoring"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_apigatewayv2_api.websocket_api.name}"
}

output "api_gateway_logs_url" {
  description = "URL to API Gateway logs in CloudWatch"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#logStream:group=/aws/apigateway/${aws_apigatewayv2_api.websocket_api.id}/${var.stage_name}"
}

# Deployment Information
output "deployment_timestamp" {
  description = "Timestamp of the deployment"
  value       = timestamp()
}

output "terraform_version" {
  description = "Terraform version used for deployment"
  value       = "~> 1.0"
}

output "aws_provider_version" {
  description = "AWS provider version used for deployment"
  value       = "~> 5.0"
}