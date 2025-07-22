# Outputs for AWS AppSync real-time data synchronization infrastructure

# AppSync API information
output "appsync_api_id" {
  description = "The AppSync GraphQL API ID"
  value       = aws_appsync_graphql_api.tasks_api.id
}

output "appsync_api_name" {
  description = "The AppSync GraphQL API name"
  value       = aws_appsync_graphql_api.tasks_api.name
}

output "appsync_api_arn" {
  description = "The AppSync GraphQL API ARN"
  value       = aws_appsync_graphql_api.tasks_api.arn
}

output "graphql_url" {
  description = "The GraphQL endpoint URL"
  value       = aws_appsync_graphql_api.tasks_api.uris["GRAPHQL"]
}

output "realtime_url" {
  description = "The real-time WebSocket endpoint URL for subscriptions"
  value       = aws_appsync_graphql_api.tasks_api.uris["REALTIME"]
}

# API Key (if using API_KEY authentication)
output "api_key" {
  description = "The AppSync API key for testing (if API_KEY authentication is enabled)"
  value       = var.authentication_type == "API_KEY" ? aws_appsync_api_key.tasks_api_key[0].key : null
  sensitive   = true
}

output "api_key_expires" {
  description = "The AppSync API key expiration date"
  value       = var.authentication_type == "API_KEY" ? aws_appsync_api_key.tasks_api_key[0].expires : null
}

# DynamoDB table information
output "dynamodb_table_name" {
  description = "The name of the DynamoDB table storing tasks"
  value       = aws_dynamodb_table.tasks.name
}

output "dynamodb_table_arn" {
  description = "The ARN of the DynamoDB table"
  value       = aws_dynamodb_table.tasks.arn
}

output "dynamodb_stream_arn" {
  description = "The ARN of the DynamoDB table stream"
  value       = aws_dynamodb_table.tasks.stream_arn
}

output "dynamodb_gsi_name" {
  description = "The name of the Global Secondary Index for status queries"
  value       = "status-createdAt-index"
}

# IAM role information
output "appsync_service_role_arn" {
  description = "The ARN of the IAM role used by AppSync to access DynamoDB"
  value       = aws_iam_role.appsync_dynamodb_role.arn
}

output "appsync_service_role_name" {
  description = "The name of the IAM role used by AppSync"
  value       = aws_iam_role.appsync_dynamodb_role.name
}

# CloudWatch logging information
output "cloudwatch_log_group_name" {
  description = "The CloudWatch log group name for AppSync logs"
  value       = var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.appsync_logs[0].name : null
}

output "cloudwatch_log_group_arn" {
  description = "The CloudWatch log group ARN for AppSync logs"
  value       = var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.appsync_logs[0].arn : null
}

# Resource naming and configuration
output "resource_name_prefix" {
  description = "The prefix used for naming resources"
  value       = local.name_prefix
}

output "environment" {
  description = "The environment name"
  value       = var.environment
}

output "aws_region" {
  description = "The AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "aws_account_id" {
  description = "The AWS account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

# Sample GraphQL operations for testing
output "sample_create_task_mutation" {
  description = "Sample GraphQL mutation for creating a task"
  value = <<-EOT
mutation CreateTask {
  createTask(input: {
    title: "Sample Task"
    description: "This is a sample task created via GraphQL"
    priority: HIGH
    assignedTo: "user@example.com"
  }) {
    id
    title
    description
    status
    priority
    assignedTo
    createdAt
    updatedAt
    version
  }
}
EOT
}

output "sample_list_tasks_query" {
  description = "Sample GraphQL query for listing tasks"
  value = <<-EOT
query ListTasks {
  listTasks(limit: 20) {
    items {
      id
      title
      description
      status
      priority
      assignedTo
      createdAt
      updatedAt
      version
    }
    nextToken
  }
}
EOT
}

output "sample_task_subscription" {
  description = "Sample GraphQL subscription for real-time task updates"
  value = <<-EOT
subscription OnTaskCreated {
  onTaskCreated {
    id
    title
    description
    status
    priority
    assignedTo
    createdAt
    updatedAt
    version
  }
}
EOT
}

# Connection instructions
output "connection_instructions" {
  description = "Instructions for connecting to the AppSync API"
  value = <<-EOT
To connect to your AppSync API:

1. GraphQL Endpoint: ${aws_appsync_graphql_api.tasks_api.uris["GRAPHQL"]}
2. Real-time Endpoint: ${aws_appsync_graphql_api.tasks_api.uris["REALTIME"]}
3. Authentication: ${var.authentication_type}
${var.authentication_type == "API_KEY" ? "4. API Key: Use the 'api_key' output value (marked as sensitive)" : ""}

For testing with curl (if using API_KEY):
curl -X POST \\
  ${aws_appsync_graphql_api.tasks_api.uris["GRAPHQL"]} \\
  -H "Content-Type: application/json" \\
  -H "x-api-key: YOUR_API_KEY" \\
  -d '{"query": "query { listTasks { items { id title status } } }"}'

For real-time subscriptions, use AWS AppSync client SDKs:
- JavaScript: @aws-amplify/api-graphql
- iOS: AWSAppSync
- Android: AWSAppSync
EOT
}

# Cost optimization recommendations
output "cost_optimization_notes" {
  description = "Recommendations for optimizing costs"
  value = <<-EOT
Cost Optimization Recommendations:

1. DynamoDB Capacity:
   - Current: ${var.dynamodb_read_capacity} RCU, ${var.dynamodb_write_capacity} WCU
   - Consider switching to On-Demand billing for variable workloads
   - Monitor usage and adjust capacity based on actual traffic

2. CloudWatch Logs:
   - Current retention: ${var.log_retention_days} days
   - Consider shorter retention for development environments
   - Use log filtering to reduce storage costs

3. API Key Expiration:
   - Current: ${var.api_key_expires_in_days} days
   - Use short-lived keys for testing environments
   - Implement Cognito User Pools for production authentication

4. Cleanup:
   - Remember to run 'terraform destroy' after testing
   - Monitor AWS costs in the billing dashboard
EOT
}