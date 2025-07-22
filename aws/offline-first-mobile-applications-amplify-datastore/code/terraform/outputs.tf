# AWS Amplify DataStore - Terraform Outputs
# This file defines outputs for the offline-first mobile application infrastructure,
# providing essential information for client configuration and integration.

# =============================================================================
# COGNITO OUTPUTS
# =============================================================================

output "cognito_user_pool_id" {
  description = "ID of the Cognito User Pool"
  value       = aws_cognito_user_pool.user_pool.id
}

output "cognito_user_pool_arn" {
  description = "ARN of the Cognito User Pool"
  value       = aws_cognito_user_pool.user_pool.arn
}

output "cognito_user_pool_client_id" {
  description = "ID of the Cognito User Pool Client"
  value       = aws_cognito_user_pool_client.user_pool_client.id
}

output "cognito_user_pool_domain" {
  description = "Cognito User Pool domain"
  value       = aws_cognito_user_pool.user_pool.domain
}

output "cognito_identity_pool_id" {
  description = "ID of the Cognito Identity Pool"
  value       = aws_cognito_identity_pool.identity_pool.id
}

output "cognito_user_pool_endpoint" {
  description = "Endpoint of the Cognito User Pool"
  value       = aws_cognito_user_pool.user_pool.endpoint
}

# =============================================================================
# APPSYNC OUTPUTS
# =============================================================================

output "appsync_graphql_api_id" {
  description = "ID of the AppSync GraphQL API"
  value       = aws_appsync_graphql_api.api.id
}

output "appsync_graphql_api_arn" {
  description = "ARN of the AppSync GraphQL API"
  value       = aws_appsync_graphql_api.api.arn
}

output "appsync_graphql_endpoint" {
  description = "GraphQL endpoint URL"
  value       = aws_appsync_graphql_api.api.uris["GRAPHQL"]
}

output "appsync_realtime_endpoint" {
  description = "Real-time endpoint URL for subscriptions"
  value       = aws_appsync_graphql_api.api.uris["REALTIME"]
}

output "appsync_api_key" {
  description = "AppSync API key (if API key authentication is used)"
  value       = var.appsync_authentication_type == "API_KEY" ? aws_appsync_graphql_api.api.api_keys : null
  sensitive   = true
}

# =============================================================================
# DYNAMODB OUTPUTS
# =============================================================================

output "dynamodb_task_table_name" {
  description = "Name of the DynamoDB Task table"
  value       = aws_dynamodb_table.task_table.name
}

output "dynamodb_task_table_arn" {
  description = "ARN of the DynamoDB Task table"
  value       = aws_dynamodb_table.task_table.arn
}

output "dynamodb_project_table_name" {
  description = "Name of the DynamoDB Project table"
  value       = aws_dynamodb_table.project_table.name
}

output "dynamodb_project_table_arn" {
  description = "ARN of the DynamoDB Project table"
  value       = aws_dynamodb_table.project_table.arn
}

output "dynamodb_task_table_stream_arn" {
  description = "ARN of the DynamoDB Task table stream"
  value       = aws_dynamodb_table.task_table.stream_arn
}

output "dynamodb_project_table_stream_arn" {
  description = "ARN of the DynamoDB Project table stream"
  value       = aws_dynamodb_table.project_table.stream_arn
}

# =============================================================================
# AMPLIFY OUTPUTS
# =============================================================================

output "amplify_app_id" {
  description = "ID of the Amplify app"
  value       = var.create_amplify_app ? aws_amplify_app.app[0].id : null
}

output "amplify_app_arn" {
  description = "ARN of the Amplify app"
  value       = var.create_amplify_app ? aws_amplify_app.app[0].arn : null
}

output "amplify_app_name" {
  description = "Name of the Amplify app"
  value       = var.create_amplify_app ? aws_amplify_app.app[0].name : null
}

output "amplify_default_domain" {
  description = "Default domain of the Amplify app"
  value       = var.create_amplify_app ? aws_amplify_app.app[0].default_domain : null
}

output "amplify_app_url" {
  description = "URL of the Amplify app"
  value       = var.create_amplify_app ? "https://${aws_amplify_branch.main[0].branch_name}.${aws_amplify_app.app[0].default_domain}" : null
}

output "amplify_branch_name" {
  description = "Name of the main Amplify branch"
  value       = var.create_amplify_app ? aws_amplify_branch.main[0].branch_name : null
}

output "amplify_custom_domain" {
  description = "Custom domain for the Amplify app"
  value       = var.create_amplify_app && var.create_custom_domain && var.custom_domain_name != "" ? aws_amplify_domain_association.domain[0].domain_name : null
}

output "amplify_custom_domain_url" {
  description = "Custom domain URL for the Amplify app"
  value       = var.create_amplify_app && var.create_custom_domain && var.custom_domain_name != "" ? "https://${aws_amplify_domain_association.domain[0].domain_name}" : null
}

# =============================================================================
# IAM OUTPUTS
# =============================================================================

output "authenticated_role_arn" {
  description = "ARN of the authenticated IAM role"
  value       = aws_iam_role.authenticated_role.arn
}

output "appsync_service_role_arn" {
  description = "ARN of the AppSync service role"
  value       = aws_iam_role.appsync_dynamodb_role.arn
}

# =============================================================================
# REGION AND ACCOUNT OUTPUTS
# =============================================================================

output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "aws_account_id" {
  description = "AWS account ID"
  value       = data.aws_caller_identity.current.account_id
}

# =============================================================================
# CONFIGURATION OUTPUTS FOR CLIENT APPLICATIONS
# =============================================================================

output "amplify_configuration" {
  description = "Amplify configuration for client applications"
  value = {
    aws_project_region = data.aws_region.current.name
    aws_cognito_region = data.aws_region.current.name
    aws_user_pools_id  = aws_cognito_user_pool.user_pool.id
    aws_user_pools_web_client_id = aws_cognito_user_pool_client.user_pool_client.id
    aws_cognito_identity_pool_id = aws_cognito_identity_pool.identity_pool.id
    aws_appsync_graphqlEndpoint = aws_appsync_graphql_api.api.uris["GRAPHQL"]
    aws_appsync_region = data.aws_region.current.name
    aws_appsync_authenticationType = var.appsync_authentication_type
    aws_appsync_apiKey = var.appsync_authentication_type == "API_KEY" ? aws_appsync_graphql_api.api.api_keys : null
    aws_appsync_additionalAuthenticationTypes = []
    aws_appsync_conflictResolution = {
      strategy = var.conflict_resolution_strategy
      autoMerge = var.conflict_resolution_strategy == "AUTOMERGE"
    }
    aws_appsync_maxRecordsToSync = 10000
    aws_appsync_syncPageSize = 1000
    aws_appsync_syncExpressions = var.datastore_sync_expressions
  }
  sensitive = true
}

output "amplify_configuration_json" {
  description = "Amplify configuration as JSON string for client applications"
  value = jsonencode({
    aws_project_region = data.aws_region.current.name
    aws_cognito_region = data.aws_region.current.name
    aws_user_pools_id  = aws_cognito_user_pool.user_pool.id
    aws_user_pools_web_client_id = aws_cognito_user_pool_client.user_pool_client.id
    aws_cognito_identity_pool_id = aws_cognito_identity_pool.identity_pool.id
    aws_appsync_graphqlEndpoint = aws_appsync_graphql_api.api.uris["GRAPHQL"]
    aws_appsync_region = data.aws_region.current.name
    aws_appsync_authenticationType = var.appsync_authentication_type
    aws_appsync_apiKey = var.appsync_authentication_type == "API_KEY" ? aws_appsync_graphql_api.api.api_keys : null
    aws_appsync_additionalAuthenticationTypes = []
    aws_appsync_conflictResolution = {
      strategy = var.conflict_resolution_strategy
      autoMerge = var.conflict_resolution_strategy == "AUTOMERGE"
    }
    aws_appsync_maxRecordsToSync = 10000
    aws_appsync_syncPageSize = 1000
    aws_appsync_syncExpressions = var.datastore_sync_expressions
  })
  sensitive = true
}

# =============================================================================
# DATASTORE CONFIGURATION
# =============================================================================

output "datastore_configuration" {
  description = "DataStore configuration for offline-first applications"
  value = {
    enabled = var.enable_datastore
    conflict_resolution_strategy = var.conflict_resolution_strategy
    sync_expressions = var.datastore_sync_expressions
    max_records_to_sync = 10000
    sync_page_size = 1000
    full_sync_interval = 24 * 60 * 60 * 1000  # 24 hours in milliseconds
  }
}

# =============================================================================
# MONITORING OUTPUTS
# =============================================================================

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for AppSync"
  value       = aws_cloudwatch_log_group.appsync_logs.name
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for notifications"
  value       = var.notifications_email != "" ? aws_sns_topic.notifications[0].arn : null
}

# =============================================================================
# SECURITY OUTPUTS
# =============================================================================

output "security_configuration" {
  description = "Security configuration summary"
  value = {
    authentication_type = var.appsync_authentication_type
    cognito_user_pool_id = aws_cognito_user_pool.user_pool.id
    cognito_identity_pool_id = aws_cognito_identity_pool.identity_pool.id
    dynamodb_encryption_enabled = var.enable_server_side_encryption
    dynamodb_point_in_time_recovery = var.enable_point_in_time_recovery
    dynamodb_deletion_protection = var.enable_deletion_protection
    advanced_security_mode = "ENFORCED"
  }
}

# =============================================================================
# RESOURCE SUMMARY
# =============================================================================

output "resource_summary" {
  description = "Summary of created resources"
  value = {
    cognito_user_pool = aws_cognito_user_pool.user_pool.name
    cognito_identity_pool = aws_cognito_identity_pool.identity_pool.identity_pool_name
    appsync_api = aws_appsync_graphql_api.api.name
    dynamodb_tables = {
      task_table = aws_dynamodb_table.task_table.name
      project_table = aws_dynamodb_table.project_table.name
    }
    amplify_app = var.create_amplify_app ? aws_amplify_app.app[0].name : null
    region = data.aws_region.current.name
    account_id = data.aws_caller_identity.current.account_id
  }
}

# =============================================================================
# NEXT STEPS
# =============================================================================

output "next_steps" {
  description = "Next steps for configuring your offline-first mobile application"
  value = [
    "1. Configure your mobile application with the Amplify configuration JSON",
    "2. Install AWS Amplify libraries in your mobile project",
    "3. Initialize DataStore in your application code",
    "4. Implement authentication flow using Cognito",
    "5. Start building your offline-first features",
    "6. Test offline functionality and data synchronization",
    "7. Monitor application performance using CloudWatch"
  ]
}