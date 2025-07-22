# ===================================
# Core API Information
# ===================================

output "appsync_api_id" {
  description = "The ID of the AppSync GraphQL API"
  value       = aws_appsync_graphql_api.chat_api.id
}

output "appsync_api_arn" {
  description = "The ARN of the AppSync GraphQL API"
  value       = aws_appsync_graphql_api.chat_api.arn
}

output "appsync_api_uris" {
  description = "Map of API URIs (GraphQL and Real-time endpoints)"
  value = {
    graphql   = aws_appsync_graphql_api.chat_api.uris["GRAPHQL"]
    realtime  = aws_appsync_graphql_api.chat_api.uris["REALTIME"]
  }
}

output "graphql_endpoint" {
  description = "The GraphQL endpoint URL for client applications"
  value       = aws_appsync_graphql_api.chat_api.uris["GRAPHQL"]
}

output "realtime_endpoint" {
  description = "The Real-time WebSocket endpoint URL for subscriptions"
  value       = aws_appsync_graphql_api.chat_api.uris["REALTIME"]
}

# ===================================
# Authentication Information
# ===================================

output "cognito_user_pool_id" {
  description = "The ID of the Cognito User Pool"
  value       = aws_cognito_user_pool.chat_users.id
}

output "cognito_user_pool_arn" {
  description = "The ARN of the Cognito User Pool"
  value       = aws_cognito_user_pool.chat_users.arn
}

output "cognito_user_pool_client_id" {
  description = "The ID of the Cognito User Pool Client"
  value       = aws_cognito_user_pool_client.chat_client.id
}

output "cognito_user_pool_client_secret" {
  description = "The secret of the Cognito User Pool Client (sensitive)"
  value       = aws_cognito_user_pool_client.chat_client.client_secret
  sensitive   = true
}

output "cognito_user_pool_domain" {
  description = "The domain name of the Cognito User Pool"
  value       = aws_cognito_user_pool.chat_users.domain
}

# ===================================
# Database Information
# ===================================

output "dynamodb_tables" {
  description = "Map of DynamoDB table information"
  value = {
    messages = {
      name = aws_dynamodb_table.messages.name
      arn  = aws_dynamodb_table.messages.arn
      id   = aws_dynamodb_table.messages.id
      stream_arn = var.enable_dynamodb_streams ? aws_dynamodb_table.messages.stream_arn : null
    }
    conversations = {
      name = aws_dynamodb_table.conversations.name
      arn  = aws_dynamodb_table.conversations.arn
      id   = aws_dynamodb_table.conversations.id
    }
    users = {
      name = aws_dynamodb_table.users.name
      arn  = aws_dynamodb_table.users.arn
      id   = aws_dynamodb_table.users.id
    }
  }
}

output "messages_table_name" {
  description = "The name of the messages DynamoDB table"
  value       = aws_dynamodb_table.messages.name
}

output "conversations_table_name" {
  description = "The name of the conversations DynamoDB table"
  value       = aws_dynamodb_table.conversations.name
}

output "users_table_name" {
  description = "The name of the users DynamoDB table"
  value       = aws_dynamodb_table.users.name
}

output "messages_table_stream_arn" {
  description = "The ARN of the DynamoDB stream for the messages table (if enabled)"
  value       = var.enable_dynamodb_streams ? aws_dynamodb_table.messages.stream_arn : null
}

# ===================================
# IAM Roles and Policies
# ===================================

output "appsync_service_role_arn" {
  description = "The ARN of the IAM role used by AppSync for DynamoDB access"
  value       = aws_iam_role.appsync_dynamodb_role.arn
}

output "appsync_logs_role_arn" {
  description = "The ARN of the IAM role used by AppSync for CloudWatch logs (if logging is enabled)"
  value       = var.enable_appsync_logging ? aws_iam_role.appsync_logs_role[0].arn : null
}

# ===================================
# Monitoring and Alerting
# ===================================

output "sns_topic_arn" {
  description = "The ARN of the SNS topic for CloudWatch alarms (if enabled)"
  value       = var.enable_cloudwatch_alarms && length(var.alarm_email_endpoints) > 0 ? aws_sns_topic.chat_app_alerts[0].arn : null
}

output "cloudwatch_log_group_name" {
  description = "The name of the CloudWatch log group for AppSync (if logging is enabled)"
  value       = var.enable_appsync_logging ? "/aws/appsync/apis/${aws_appsync_graphql_api.chat_api.id}" : null
}

# ===================================
# Test Users Information
# ===================================

output "test_users" {
  description = "Information about created test users (if enabled)"
  value = var.create_test_users ? {
    usernames = aws_cognito_user.test_users[*].username
    emails    = [for user in aws_cognito_user.test_users : user.attributes.email]
    count     = length(aws_cognito_user.test_users)
  } : null
}

output "test_user_credentials" {
  description = "Test user login credentials (if test users are enabled)"
  value = var.create_test_users ? {
    for i, user in aws_cognito_user.test_users : user.username => {
      email    = user.attributes.email
      username = user.username
      password = "TestPassword123!"
    }
  } : {}
  sensitive = true
}

# ===================================
# Configuration for Client Applications
# ===================================

output "client_configuration" {
  description = "Configuration object for client applications"
  value = {
    aws_region                 = data.aws_region.current.name
    aws_cognito_region        = data.aws_region.current.name
    aws_user_pools_id         = aws_cognito_user_pool.chat_users.id
    aws_user_pools_web_client_id = aws_cognito_user_pool_client.chat_client.id
    aws_appsync_graphqlEndpoint = aws_appsync_graphql_api.chat_api.uris["GRAPHQL"]
    aws_appsync_region         = data.aws_region.current.name
    aws_appsync_authenticationType = "AMAZON_COGNITO_USER_POOLS"
    aws_appsync_apiKey         = null  # Not using API key authentication
  }
}

# ===================================
# Resource Information
# ===================================

output "resource_summary" {
  description = "Summary of all created resources"
  value = {
    project_name     = var.project_name
    environment      = var.environment
    aws_region       = data.aws_region.current.name
    aws_account_id   = data.aws_caller_identity.current.account_id
    random_suffix    = random_string.suffix.result
    
    resources_created = {
      appsync_api           = aws_appsync_graphql_api.chat_api.name
      cognito_user_pool     = aws_cognito_user_pool.chat_users.name
      dynamodb_tables       = [
        aws_dynamodb_table.messages.name,
        aws_dynamodb_table.conversations.name,
        aws_dynamodb_table.users.name
      ]
      iam_roles            = [
        aws_iam_role.appsync_dynamodb_role.name
      ]
      test_users_created   = var.create_test_users ? var.test_user_count : 0
      monitoring_enabled   = var.enable_cloudwatch_alarms
    }
    
    estimated_monthly_cost = {
      currency = "USD"
      breakdown = {
        appsync_requests   = "Pay per request (first 250K requests free)"
        appsync_realtime   = "Pay per minute connected"
        dynamodb_storage   = "Pay per GB stored"
        dynamodb_requests  = var.dynamodb_billing_mode == "PAY_PER_REQUEST" ? "Pay per request" : "Provisioned capacity"
        cognito_users      = "Free up to 50K MAU"
        cloudwatch_logs    = "Pay per GB ingested"
      }
      notes = [
        "Costs depend on actual usage patterns",
        "DynamoDB streams incur additional charges if enabled",
        "CloudWatch alarms cost $0.10 per alarm per month"
      ]
    }
  }
}

# ===================================
# Security Information
# ===================================

output "security_configuration" {
  description = "Security configuration details"
  value = {
    authentication = {
      type                    = "Amazon Cognito User Pools"
      advanced_security       = var.enable_advanced_security
      auto_verified_attributes = var.auto_verified_attributes
      password_policy = {
        minimum_length     = var.password_minimum_length
        require_uppercase  = true
        require_lowercase  = true
        require_numbers    = true
        require_symbols    = true
      }
    }
    
    data_protection = {
      dynamodb_encryption        = "AWS managed keys"
      appsync_encryption         = "HTTPS/WSS in transit"
      point_in_time_recovery     = var.enable_point_in_time_recovery
      deletion_protection        = var.enable_deletion_protection
    }
    
    access_control = {
      iam_roles_created          = [aws_iam_role.appsync_dynamodb_role.name]
      least_privilege_applied    = true
      service_to_service_auth    = "IAM roles"
    }
  }
}

# ===================================
# Development and Testing
# ===================================

output "development_endpoints" {
  description = "Endpoints and information useful for development and testing"
  value = {
    graphql_playground_url = "https://console.aws.amazon.com/appsync/home?region=${data.aws_region.current.name}#/${aws_appsync_graphql_api.chat_api.id}/v1/queries"
    cognito_console_url    = "https://console.aws.amazon.com/cognito/users/?region=${data.aws_region.current.name}#/pool/${aws_cognito_user_pool.chat_users.id}/details"
    dynamodb_console_url   = "https://console.aws.amazon.com/dynamodb/home?region=${data.aws_region.current.name}#tables:"
    cloudwatch_logs_url    = var.enable_appsync_logging ? "https://console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#logsV2:log-groups/log-group/${replace("/aws/appsync/apis/${aws_appsync_graphql_api.chat_api.id}", "/", "%2F")}" : null
  }
}

# ===================================
# Next Steps
# ===================================

output "next_steps" {
  description = "Recommended next steps after deployment"
  value = [
    "1. Test the GraphQL API using the AWS AppSync console at: https://console.aws.amazon.com/appsync/home?region=${data.aws_region.current.name}#/${aws_appsync_graphql_api.chat_api.id}/v1/queries",
    "2. Create user accounts via the Cognito console or programmatically",
    "3. Configure your client application with the provided client_configuration output",
    "4. Test real-time subscriptions by opening multiple browser tabs",
    "5. Monitor API usage in CloudWatch metrics",
    var.create_test_users ? "6. Use the created test users to validate the chat functionality" : "6. Create test users for development and testing",
    var.enable_cloudwatch_alarms ? "7. Verify CloudWatch alarms are configured properly" : "7. Consider enabling CloudWatch alarms for production monitoring",
    "8. Implement proper error handling in your client applications",
    "9. Set up CI/CD pipelines for deploying schema changes",
    "10. Review and customize the GraphQL schema for your specific use case"
  ]
}