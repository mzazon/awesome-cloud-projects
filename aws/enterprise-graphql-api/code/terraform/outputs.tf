# Core API Information
output "graphql_api_id" {
  description = "AppSync GraphQL API ID"
  value       = aws_appsync_graphql_api.main.id
}

output "graphql_endpoint" {
  description = "AppSync GraphQL API endpoint URL"
  value       = aws_appsync_graphql_api.main.uris["GRAPHQL"]
}

output "realtime_endpoint" {
  description = "AppSync Real-time endpoint URL for subscriptions"
  value       = aws_appsync_graphql_api.main.uris["REALTIME"]
}

output "api_key" {
  description = "AppSync API Key for development access"
  value       = aws_appsync_api_key.main.key
  sensitive   = true
}

output "api_key_expires" {
  description = "AppSync API Key expiration timestamp"
  value       = aws_appsync_api_key.main.expires
}

# Authentication Information
output "user_pool_id" {
  description = "Cognito User Pool ID"
  value       = aws_cognito_user_pool.main.id
}

output "user_pool_client_id" {
  description = "Cognito User Pool Client ID"
  value       = aws_cognito_user_pool_client.main.id
}

output "user_pool_arn" {
  description = "Cognito User Pool ARN"
  value       = aws_cognito_user_pool.main.arn
}

output "user_pool_endpoint" {
  description = "Cognito User Pool endpoint"
  value       = aws_cognito_user_pool.main.endpoint
}

# Database Information
output "products_table_name" {
  description = "DynamoDB Products table name"
  value       = aws_dynamodb_table.products.name
}

output "products_table_arn" {
  description = "DynamoDB Products table ARN"
  value       = aws_dynamodb_table.products.arn
}

output "products_table_stream_arn" {
  description = "DynamoDB Products table stream ARN"
  value       = aws_dynamodb_table.products.stream_arn
}

output "users_table_name" {
  description = "DynamoDB Users table name"
  value       = aws_dynamodb_table.users.name
}

output "users_table_arn" {
  description = "DynamoDB Users table ARN"
  value       = aws_dynamodb_table.users.arn
}

output "analytics_table_name" {
  description = "DynamoDB Analytics table name"
  value       = aws_dynamodb_table.analytics.name
}

output "analytics_table_arn" {
  description = "DynamoDB Analytics table ARN"
  value       = aws_dynamodb_table.analytics.arn
}

# Search Information
output "opensearch_domain_name" {
  description = "OpenSearch domain name"
  value       = aws_opensearch_domain.products_search.domain_name
}

output "opensearch_endpoint" {
  description = "OpenSearch domain endpoint"
  value       = aws_opensearch_domain.products_search.endpoint
}

output "opensearch_arn" {
  description = "OpenSearch domain ARN"
  value       = aws_opensearch_domain.products_search.arn
}

output "opensearch_kibana_endpoint" {
  description = "OpenSearch Kibana endpoint"
  value       = aws_opensearch_domain.products_search.kibana_endpoint
}

# Lambda Information
output "lambda_function_name" {
  description = "Lambda business logic function name"
  value       = aws_lambda_function.business_logic.function_name
}

output "lambda_function_arn" {
  description = "Lambda business logic function ARN"
  value       = aws_lambda_function.business_logic.arn
}

output "lambda_invoke_arn" {
  description = "Lambda business logic function invoke ARN"
  value       = aws_lambda_function.business_logic.invoke_arn
}

# Data Source Information
output "products_datasource_name" {
  description = "AppSync Products data source name"
  value       = aws_appsync_datasource.products.name
}

output "business_logic_datasource_name" {
  description = "AppSync Lambda data source name"
  value       = aws_appsync_datasource.business_logic.name
}

# Test User Information
output "test_user_email" {
  description = "Test user email address"
  value       = var.create_test_user ? var.test_user_email : null
}

output "test_user_password" {
  description = "Test user password"
  value       = var.create_test_user ? "DevUser123!" : null
  sensitive   = true
}

# Regional Information
output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "aws_account_id" {
  description = "AWS account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

# Resource Naming
output "project_name" {
  description = "Project name used for resource naming"
  value       = var.project_name
}

output "name_prefix" {
  description = "Common name prefix for all resources"
  value       = local.name_prefix
}

output "random_suffix" {
  description = "Random suffix used for unique resource naming"
  value       = random_string.suffix.result
}

# Security and Compliance
output "deletion_protection_enabled" {
  description = "Whether deletion protection is enabled for critical resources"
  value       = var.enable_deletion_protection
}

output "backup_enabled" {
  description = "Whether automated backups are enabled"
  value       = var.enable_backup
}

output "encryption_enabled" {
  description = "Whether encryption is enabled for supported resources"
  value       = var.enable_opensearch_encryption
}

# Monitoring Information
output "enhanced_monitoring_enabled" {
  description = "Whether enhanced monitoring is enabled"
  value       = var.enable_enhanced_monitoring
}

output "xray_tracing_enabled" {
  description = "Whether X-Ray tracing is enabled for AppSync"
  value       = var.enable_appsync_xray
}

# Sample Data Information
output "sample_data_loaded" {
  description = "Whether sample data was loaded into tables"
  value       = var.enable_sample_data
}

# AppSync Console Links
output "appsync_console_url" {
  description = "AWS Console URL for AppSync API"
  value       = "https://console.aws.amazon.com/appsync/home?region=${data.aws_region.current.name}#/apis/${aws_appsync_graphql_api.main.id}/home"
}

output "dynamodb_console_url" {
  description = "AWS Console URL for DynamoDB tables"
  value       = "https://console.aws.amazon.com/dynamodb/home?region=${data.aws_region.current.name}#tables:"
}

output "opensearch_console_url" {
  description = "AWS Console URL for OpenSearch domain"
  value       = "https://console.aws.amazon.com/opensearch/home?region=${data.aws_region.current.name}#opensearch/domains/${aws_opensearch_domain.products_search.domain_name}"
}

output "cognito_console_url" {
  description = "AWS Console URL for Cognito User Pool"
  value       = "https://console.aws.amazon.com/cognito/users/?region=${data.aws_region.current.name}#/pool/${aws_cognito_user_pool.main.id}/users"
}

# GraphQL Testing Information
output "graphql_introspection_query" {
  description = "GraphQL introspection query for schema exploration"
  value = "query IntrospectionQuery { __schema { queryType { name } mutationType { name } subscriptionType { name } types { ...FullType } directives { name description locations args { ...InputValue } } } } fragment FullType on __Type { kind name description fields(includeDeprecated: true) { name description args { ...InputValue } type { ...TypeRef } isDeprecated deprecationReason } inputFields { ...InputValue } interfaces { ...TypeRef } enumValues(includeDeprecated: true) { name description isDeprecated deprecationReason } possibleTypes { ...TypeRef } } fragment InputValue on __InputValue { name description type { ...TypeRef } defaultValue } fragment TypeRef on __Type { kind name ofType { kind name ofType { kind name ofType { kind name ofType { kind name ofType { kind name ofType { kind name ofType { kind name } } } } } } } }"
}

# Cost Estimation Information
output "estimated_monthly_cost_usd" {
  description = "Estimated monthly cost in USD for this infrastructure"
  value = {
    opensearch_domain = "~$15-50 (depending on instance hours)"
    dynamodb_tables   = "~$0-25 (pay-per-request billing)"
    lambda_functions  = "~$0-5 (depends on invocations)"
    appsync_api      = "~$0-10 (depends on requests and resolvers)"
    cognito_users    = "~$0-5 (depends on monthly active users)"
    data_transfer    = "~$0-10 (depends on usage patterns)"
    total_estimated  = "~$15-105 per month for development workloads"
  }
}