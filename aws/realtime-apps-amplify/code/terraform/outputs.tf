# Outputs for AWS Full-Stack Real-Time Applications with Amplify and AppSync

# Cognito User Pool outputs
output "cognito_user_pool_id" {
  description = "ID of the Cognito User Pool"
  value       = aws_cognito_user_pool.chat_users.id
}

output "cognito_user_pool_arn" {
  description = "ARN of the Cognito User Pool"
  value       = aws_cognito_user_pool.chat_users.arn
}

output "cognito_user_pool_client_id" {
  description = "ID of the Cognito User Pool Client"
  value       = aws_cognito_user_pool_client.chat_client.id
}

output "cognito_user_pool_domain" {
  description = "Domain of the Cognito User Pool"
  value       = aws_cognito_user_pool_domain.chat_domain.domain
}

output "cognito_identity_pool_id" {
  description = "ID of the Cognito Identity Pool"
  value       = aws_cognito_identity_pool.chat_identity.id
}

# AppSync API outputs
output "appsync_graphql_endpoint" {
  description = "GraphQL endpoint URL for the AppSync API"
  value       = aws_appsync_graphql_api.chat_api.graphql_endpoint
}

output "appsync_api_id" {
  description = "ID of the AppSync GraphQL API"
  value       = aws_appsync_graphql_api.chat_api.id
}

output "appsync_api_arn" {
  description = "ARN of the AppSync GraphQL API"
  value       = aws_appsync_graphql_api.chat_api.arn
}

output "appsync_realtime_endpoint" {
  description = "WebSocket endpoint URL for real-time subscriptions"
  value       = "wss://${aws_appsync_graphql_api.chat_api.id}.appsync-realtime-api.${data.aws_region.current.name}.amazonaws.com/graphql"
}

output "appsync_api_key" {
  description = "API key for the AppSync API (if enabled)"
  value       = var.enable_api_key_auth ? aws_appsync_api_key.chat_api_key[0].key : null
  sensitive   = true
}

# DynamoDB table outputs
output "dynamodb_chat_rooms_table_name" {
  description = "Name of the DynamoDB table for chat rooms"
  value       = aws_dynamodb_table.chat_rooms.name
}

output "dynamodb_chat_rooms_table_arn" {
  description = "ARN of the DynamoDB table for chat rooms"
  value       = aws_dynamodb_table.chat_rooms.arn
}

output "dynamodb_messages_table_name" {
  description = "Name of the DynamoDB table for messages"
  value       = aws_dynamodb_table.messages.name
}

output "dynamodb_messages_table_arn" {
  description = "ARN of the DynamoDB table for messages"
  value       = aws_dynamodb_table.messages.arn
}

output "dynamodb_reactions_table_name" {
  description = "Name of the DynamoDB table for reactions"
  value       = aws_dynamodb_table.reactions.name
}

output "dynamodb_reactions_table_arn" {
  description = "ARN of the DynamoDB table for reactions"
  value       = aws_dynamodb_table.reactions.arn
}

output "dynamodb_user_presence_table_name" {
  description = "Name of the DynamoDB table for user presence"
  value       = aws_dynamodb_table.user_presence.name
}

output "dynamodb_user_presence_table_arn" {
  description = "ARN of the DynamoDB table for user presence"
  value       = aws_dynamodb_table.user_presence.arn
}

output "dynamodb_notifications_table_name" {
  description = "Name of the DynamoDB table for notifications"
  value       = aws_dynamodb_table.notifications.name
}

output "dynamodb_notifications_table_arn" {
  description = "ARN of the DynamoDB table for notifications"
  value       = aws_dynamodb_table.notifications.arn
}

# Lambda function outputs
output "lambda_realtime_handler_function_name" {
  description = "Name of the Lambda function for real-time operations"
  value       = aws_lambda_function.realtime_handler.function_name
}

output "lambda_realtime_handler_function_arn" {
  description = "ARN of the Lambda function for real-time operations"
  value       = aws_lambda_function.realtime_handler.arn
}

output "lambda_realtime_handler_invoke_arn" {
  description = "Invoke ARN of the Lambda function for real-time operations"
  value       = aws_lambda_function.realtime_handler.invoke_arn
}

# Amplify application outputs
output "amplify_app_id" {
  description = "ID of the Amplify application"
  value       = aws_amplify_app.chat_app.id
}

output "amplify_app_arn" {
  description = "ARN of the Amplify application"
  value       = aws_amplify_app.chat_app.arn
}

output "amplify_default_domain" {
  description = "Default domain of the Amplify application"
  value       = aws_amplify_app.chat_app.default_domain
}

output "amplify_app_url" {
  description = "URL of the Amplify application"
  value       = "https://${var.amplify_branch_name}.${aws_amplify_app.chat_app.default_domain}"
}

# IAM role outputs
output "cognito_moderators_role_arn" {
  description = "ARN of the Cognito Moderators role"
  value       = aws_iam_role.moderators_role.arn
}

output "cognito_users_role_arn" {
  description = "ARN of the Cognito Users role"
  value       = aws_iam_role.users_role.arn
}

output "cognito_admins_role_arn" {
  description = "ARN of the Cognito Admins role"
  value       = aws_iam_role.admins_role.arn
}

output "lambda_execution_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_role.arn
}

output "appsync_service_role_arn" {
  description = "ARN of the AppSync service role"
  value       = aws_iam_role.appsync_service_role.arn
}

# CloudWatch outputs
output "cloudwatch_log_group_lambda" {
  description = "CloudWatch log group for Lambda functions"
  value       = var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.lambda_logs[0].name : null
}

output "cloudwatch_log_group_appsync" {
  description = "CloudWatch log group for AppSync"
  value       = var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.appsync_logs[0].name : null
}

# SNS topic outputs
output "sns_notifications_topic_arn" {
  description = "ARN of the SNS topic for notifications"
  value       = var.notification_email != "" ? aws_sns_topic.notifications[0].arn : null
}

# Configuration outputs for frontend application
output "frontend_configuration" {
  description = "Complete configuration for frontend application"
  value = {
    region = data.aws_region.current.name
    
    # AppSync configuration
    appsync = {
      graphql_endpoint    = aws_appsync_graphql_api.chat_api.graphql_endpoint
      region             = data.aws_region.current.name
      authentication_type = var.appsync_authentication_type
      api_key            = var.enable_api_key_auth ? aws_appsync_api_key.chat_api_key[0].key : null
    }
    
    # Cognito configuration
    cognito = {
      user_pool_id        = aws_cognito_user_pool.chat_users.id
      user_pool_client_id = aws_cognito_user_pool_client.chat_client.id
      identity_pool_id    = aws_cognito_identity_pool.chat_identity.id
      region             = data.aws_region.current.name
      user_pool_domain   = aws_cognito_user_pool_domain.chat_domain.domain
    }
    
    # DynamoDB table names
    tables = {
      chat_rooms     = aws_dynamodb_table.chat_rooms.name
      messages       = aws_dynamodb_table.messages.name
      reactions      = aws_dynamodb_table.reactions.name
      user_presence  = aws_dynamodb_table.user_presence.name
      notifications  = aws_dynamodb_table.notifications.name
    }
  }
  sensitive = true
}

# Environment-specific outputs
output "environment_info" {
  description = "Environment information"
  value = {
    project_name = var.project_name
    environment  = var.environment
    region       = data.aws_region.current.name
    account_id   = data.aws_caller_identity.current.account_id
    name_suffix  = random_string.suffix.result
  }
}

# Deployment validation outputs
output "deployment_validation" {
  description = "Validation commands for deployment"
  value = {
    appsync_status = "aws appsync get-graphql-api --api-id ${aws_appsync_graphql_api.chat_api.id} --region ${data.aws_region.current.name}"
    cognito_status = "aws cognito-idp describe-user-pool --user-pool-id ${aws_cognito_user_pool.chat_users.id} --region ${data.aws_region.current.name}"
    lambda_status  = "aws lambda get-function --function-name ${aws_lambda_function.realtime_handler.function_name} --region ${data.aws_region.current.name}"
    amplify_status = "aws amplify get-app --app-id ${aws_amplify_app.chat_app.id} --region ${data.aws_region.current.name}"
  }
}

# Cost estimation outputs
output "cost_estimation" {
  description = "Estimated monthly costs for the deployed resources"
  value = {
    appsync_base_cost    = "$4.00 per million requests"
    appsync_realtime     = "$4.00 per million subscription messages"
    dynamodb_cost        = var.dynamodb_billing_mode == "PAY_PER_REQUEST" ? "$1.25 per million read/write requests" : "Based on provisioned capacity"
    lambda_cost          = "$0.20 per 1 million requests + $0.00001667 per GB-second"
    cognito_cost         = "$0.0055 per monthly active user (first 50,000 users free)"
    amplify_cost         = "$0.01 per build minute + $0.15 per GB stored"
    cloudwatch_cost      = "$0.50 per million API requests"
    estimated_monthly    = "$10-50 for development, $50-200 for production"
  }
}

# Security recommendations
output "security_recommendations" {
  description = "Security recommendations for the deployed infrastructure"
  value = {
    cognito_mfa = var.enable_cognito_mfa ? "Enabled" : "Consider enabling MFA for enhanced security"
    api_key_auth = var.enable_api_key_auth ? "Enabled - ensure API key rotation" : "Disabled"
    encryption = "All data is encrypted at rest and in transit"
    iam_roles = "Follow principle of least privilege for IAM roles"
    monitoring = var.enable_cloudwatch_logs ? "CloudWatch logging enabled" : "Consider enabling CloudWatch logs"
    xray_tracing = var.enable_xray_tracing ? "X-Ray tracing enabled" : "Consider enabling X-Ray tracing"
  }
}

# Troubleshooting outputs
output "troubleshooting_guides" {
  description = "Common troubleshooting commands and resources"
  value = {
    check_appsync_logs = var.enable_cloudwatch_logs ? "aws logs describe-log-groups --log-group-name-prefix /aws/appsync --region ${data.aws_region.current.name}" : "CloudWatch logging not enabled"
    check_lambda_logs  = var.enable_cloudwatch_logs ? "aws logs describe-log-groups --log-group-name-prefix /aws/lambda/${aws_lambda_function.realtime_handler.function_name} --region ${data.aws_region.current.name}" : "CloudWatch logging not enabled"
    test_cognito_auth  = "aws cognito-idp admin-create-user --user-pool-id ${aws_cognito_user_pool.chat_users.id} --username testuser --temporary-password TempPass123! --region ${data.aws_region.current.name}"
    test_appsync_query = "Use AWS AppSync console to test GraphQL queries"
  }
}