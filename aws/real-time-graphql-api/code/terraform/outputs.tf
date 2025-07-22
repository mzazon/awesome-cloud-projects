# ==============================================================================
# Outputs for AWS AppSync GraphQL API Infrastructure
# ==============================================================================
# This file defines all output values that can be used by other Terraform
# configurations or for reference after deployment.
# ==============================================================================

# ------------------------------------------------------------------------------
# AppSync API Outputs
# ------------------------------------------------------------------------------

output "appsync_api_id" {
  description = "The ID of the AppSync GraphQL API"
  value       = aws_appsync_graphql_api.blog_api.id
}

output "appsync_api_arn" {
  description = "The ARN of the AppSync GraphQL API"
  value       = aws_appsync_graphql_api.blog_api.arn
}

output "appsync_api_name" {
  description = "The name of the AppSync GraphQL API"
  value       = aws_appsync_graphql_api.blog_api.name
}

output "graphql_endpoint" {
  description = "The GraphQL endpoint URL"
  value       = aws_appsync_graphql_api.blog_api.uris["GRAPHQL"]
}

output "realtime_endpoint" {
  description = "The real-time subscription endpoint URL"
  value       = aws_appsync_graphql_api.blog_api.uris["REALTIME"]
}

output "api_key" {
  description = "The AppSync API key for testing (if enabled)"
  value       = var.enable_api_key_auth ? aws_appsync_api_key.blog_api_key[0].key : null
  sensitive   = true
}

output "api_key_expires" {
  description = "The API key expiration timestamp"
  value       = var.enable_api_key_auth ? aws_appsync_api_key.blog_api_key[0].expires : null
}

# ------------------------------------------------------------------------------
# DynamoDB Table Outputs
# ------------------------------------------------------------------------------

output "dynamodb_table_name" {
  description = "The name of the DynamoDB table"
  value       = aws_dynamodb_table.blog_posts.name
}

output "dynamodb_table_arn" {
  description = "The ARN of the DynamoDB table"
  value       = aws_dynamodb_table.blog_posts.arn
}

output "dynamodb_table_id" {
  description = "The ID of the DynamoDB table"
  value       = aws_dynamodb_table.blog_posts.id
}

output "dynamodb_gsi_name" {
  description = "The name of the DynamoDB Global Secondary Index"
  value       = "AuthorIndex"
}

# ------------------------------------------------------------------------------
# Cognito User Pool Outputs
# ------------------------------------------------------------------------------

output "cognito_user_pool_id" {
  description = "The ID of the Cognito User Pool"
  value       = aws_cognito_user_pool.blog_users.id
}

output "cognito_user_pool_arn" {
  description = "The ARN of the Cognito User Pool"
  value       = aws_cognito_user_pool.blog_users.arn
}

output "cognito_user_pool_name" {
  description = "The name of the Cognito User Pool"
  value       = aws_cognito_user_pool.blog_users.name
}

output "cognito_user_pool_domain" {
  description = "The domain name of the Cognito User Pool"
  value       = aws_cognito_user_pool.blog_users.domain
}

output "cognito_user_pool_client_id" {
  description = "The ID of the Cognito User Pool Client"
  value       = aws_cognito_user_pool_client.blog_client.id
}

output "cognito_user_pool_client_secret" {
  description = "The client secret of the Cognito User Pool Client"
  value       = aws_cognito_user_pool_client.blog_client.client_secret
  sensitive   = true
}

# ------------------------------------------------------------------------------
# IAM Role Outputs
# ------------------------------------------------------------------------------

output "appsync_service_role_arn" {
  description = "The ARN of the AppSync service role"
  value       = aws_iam_role.appsync_dynamodb_role.arn
}

output "appsync_service_role_name" {
  description = "The name of the AppSync service role"
  value       = aws_iam_role.appsync_dynamodb_role.name
}

output "appsync_logging_role_arn" {
  description = "The ARN of the AppSync logging role"
  value       = aws_iam_role.appsync_logging_role.arn
}

# ------------------------------------------------------------------------------
# Data Source Outputs
# ------------------------------------------------------------------------------

output "appsync_datasource_name" {
  description = "The name of the AppSync DynamoDB data source"
  value       = aws_appsync_datasource.blog_posts_datasource.name
}

output "appsync_datasource_arn" {
  description = "The ARN of the AppSync DynamoDB data source"
  value       = aws_appsync_datasource.blog_posts_datasource.arn
}

# ------------------------------------------------------------------------------
# Test User Outputs
# ------------------------------------------------------------------------------

output "test_user_username" {
  description = "The username of the test user (if created)"
  value       = var.create_test_user ? aws_cognito_user.test_user[0].username : null
}

output "test_user_password" {
  description = "The password of the test user (if created)"
  value       = var.create_test_user ? var.test_password : null
  sensitive   = true
}

# ------------------------------------------------------------------------------
# Environment Information
# ------------------------------------------------------------------------------

output "aws_region" {
  description = "The AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "aws_account_id" {
  description = "The AWS account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

output "random_suffix" {
  description = "The random suffix used for unique naming"
  value       = random_string.suffix.result
}

# ------------------------------------------------------------------------------
# Connection Information
# ------------------------------------------------------------------------------

output "connection_info" {
  description = "Complete connection information for the GraphQL API"
  value = {
    api_id              = aws_appsync_graphql_api.blog_api.id
    graphql_endpoint    = aws_appsync_graphql_api.blog_api.uris["GRAPHQL"]
    realtime_endpoint   = aws_appsync_graphql_api.blog_api.uris["REALTIME"]
    user_pool_id        = aws_cognito_user_pool.blog_users.id
    user_pool_client_id = aws_cognito_user_pool_client.blog_client.id
    table_name          = aws_dynamodb_table.blog_posts.name
    region              = data.aws_region.current.name
    api_key_available   = var.enable_api_key_auth
  }
}

# ------------------------------------------------------------------------------
# Deployment Information
# ------------------------------------------------------------------------------

output "deployment_info" {
  description = "Information about the deployment"
  value = {
    timestamp         = timestamp()
    environment       = var.environment
    terraform_version = "~> 1.0"
    aws_provider_version = "~> 5.0"
    resources_created = [
      "AppSync GraphQL API",
      "DynamoDB Table with GSI",
      "Cognito User Pool",
      "Cognito User Pool Client",
      "IAM Roles and Policies",
      "AppSync Data Source",
      "GraphQL Resolvers"
    ]
  }
}

# ------------------------------------------------------------------------------
# Cost Estimation Information
# ------------------------------------------------------------------------------

output "cost_estimation" {
  description = "Cost estimation information for the deployed resources"
  value = {
    dynamodb_billing_mode = var.dynamodb_billing_mode
    appsync_requests_cost = "Pay per request"
    cognito_mau_cost     = "Pay per monthly active user"
    api_key_enabled      = var.enable_api_key_auth
    xray_tracing_enabled = var.enable_xray_tracing
    logging_enabled      = var.log_level != "NONE"
    notes = [
      "DynamoDB costs depend on read/write capacity or on-demand usage",
      "AppSync costs are based on query and data modification operations",
      "Cognito costs are based on monthly active users",
      "Additional costs may apply for CloudWatch logs and X-Ray tracing"
    ]
  }
}

# ------------------------------------------------------------------------------
# Security Information
# ------------------------------------------------------------------------------

output "security_info" {
  description = "Security configuration information"
  value = {
    primary_auth_type    = "AMAZON_COGNITO_USER_POOLS"
    api_key_auth_enabled = var.enable_api_key_auth
    encryption_enabled   = var.enable_encryption
    point_in_time_recovery = var.enable_point_in_time_recovery
    xray_tracing_enabled = var.enable_xray_tracing
    logging_level        = var.log_level
  }
}

# ------------------------------------------------------------------------------
# Quick Start Commands
# ------------------------------------------------------------------------------

output "quick_start_commands" {
  description = "Quick start commands for testing the API"
  value = {
    aws_cli_test_command = "aws appsync get-graphql-api --api-id ${aws_appsync_graphql_api.blog_api.id}"
    curl_test_command    = var.enable_api_key_auth ? "curl -X POST ${aws_appsync_graphql_api.blog_api.uris["GRAPHQL"]} -H 'Content-Type: application/json' -H 'x-api-key: ${aws_appsync_api_key.blog_api_key[0].key}' -d '{\"query\":\"query { __typename }\"}'" : "Configure authentication first"
    console_url         = "https://console.aws.amazon.com/appsync/home?region=${data.aws_region.current.name}#/apis/${aws_appsync_graphql_api.blog_api.id}/v1/home"
  }
}