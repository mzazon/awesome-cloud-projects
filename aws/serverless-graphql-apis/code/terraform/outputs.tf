# GraphQL API outputs
output "graphql_api_id" {
  description = "The ID of the AppSync GraphQL API"
  value       = aws_appsync_graphql_api.task_api.id
}

output "graphql_api_url" {
  description = "The URL of the AppSync GraphQL API"
  value       = aws_appsync_graphql_api.task_api.uris["GRAPHQL"]
}

output "graphql_api_arn" {
  description = "The ARN of the AppSync GraphQL API"
  value       = aws_appsync_graphql_api.task_api.arn
}

output "graphql_api_name" {
  description = "The name of the AppSync GraphQL API"
  value       = aws_appsync_graphql_api.task_api.name
}

output "websocket_url" {
  description = "The WebSocket URL for real-time subscriptions"
  value       = aws_appsync_graphql_api.task_api.uris["REALTIME"]
}

# DynamoDB outputs
output "dynamodb_table_name" {
  description = "The name of the DynamoDB table"
  value       = aws_dynamodb_table.tasks.name
}

output "dynamodb_table_arn" {
  description = "The ARN of the DynamoDB table"
  value       = aws_dynamodb_table.tasks.arn
}

output "dynamodb_global_secondary_index_name" {
  description = "The name of the DynamoDB Global Secondary Index"
  value       = "UserIdIndex"
}

# Lambda function outputs
output "lambda_function_name" {
  description = "The name of the Lambda function"
  value       = aws_lambda_function.task_processor.function_name
}

output "lambda_function_arn" {
  description = "The ARN of the Lambda function"
  value       = aws_lambda_function.task_processor.arn
}

output "lambda_function_invoke_arn" {
  description = "The invoke ARN of the Lambda function"
  value       = aws_lambda_function.task_processor.invoke_arn
}

# IAM role outputs
output "appsync_role_arn" {
  description = "The ARN of the AppSync service role"
  value       = aws_iam_role.appsync.arn
}

output "lambda_role_arn" {
  description = "The ARN of the Lambda execution role"
  value       = aws_iam_role.lambda.arn
}

output "scheduler_role_arn" {
  description = "The ARN of the EventBridge Scheduler role"
  value       = aws_iam_role.scheduler.arn
}

# CloudWatch outputs
output "appsync_log_group_name" {
  description = "The name of the AppSync CloudWatch log group"
  value       = aws_cloudwatch_log_group.appsync.name
}

output "lambda_log_group_name" {
  description = "The name of the Lambda CloudWatch log group"
  value       = aws_cloudwatch_log_group.lambda.name
}

# Sample schedule output (conditional)
output "sample_schedule_name" {
  description = "The name of the sample EventBridge schedule (if enabled)"
  value       = var.enable_sample_schedule ? aws_scheduler_schedule.sample_reminder[0].name : null
}

# Resource identifiers for easy reference
output "resource_suffix" {
  description = "The random suffix used for resource naming"
  value       = local.suffix
}

output "name_prefix" {
  description = "The naming prefix used for all resources"
  value       = local.name_prefix
}

# Useful information for testing and integration
output "aws_region" {
  description = "The AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "aws_account_id" {
  description = "The AWS account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

# Connection information for clients
output "connection_info" {
  description = "Connection information for GraphQL clients"
  value = {
    graphql_endpoint = aws_appsync_graphql_api.task_api.uris["GRAPHQL"]
    websocket_endpoint = aws_appsync_graphql_api.task_api.uris["REALTIME"]
    authentication_type = var.graphql_authentication_type
    region = data.aws_region.current.name
  }
  sensitive = false
}

# Schema information
output "graphql_schema_summary" {
  description = "Summary of the GraphQL schema capabilities"
  value = {
    queries = ["getTask", "listUserTasks"]
    mutations = ["createTask", "updateTask", "deleteTask", "sendReminder"]
    subscriptions = ["onTaskCreated", "onTaskUpdated", "onTaskDeleted"]
    types = ["Task", "TaskStatus", "CreateTaskInput", "UpdateTaskInput"]
  }
}

# Sample GraphQL operations for testing
output "sample_graphql_operations" {
  description = "Sample GraphQL operations for testing the API"
  value = {
    create_task_mutation = <<-EOT
      mutation CreateTask($input: CreateTaskInput!) {
        createTask(input: $input) {
          id
          title
          description
          dueDate
          status
          createdAt
        }
      }
    EOT
    
    list_tasks_query = <<-EOT
      query ListUserTasks($userId: String!) {
        listUserTasks(userId: $userId) {
          id
          title
          status
          dueDate
          createdAt
        }
      }
    EOT
    
    task_subscription = <<-EOT
      subscription OnTaskUpdated($userId: String!) {
        onTaskUpdated(userId: $userId) {
          id
          title
          status
          updatedAt
        }
      }
    EOT
  }
}