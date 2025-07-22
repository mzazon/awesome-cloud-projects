# outputs.tf
# Output values for AWS AppSync and DynamoDB Streams real-time data synchronization

# ============================================================================
# DynamoDB Outputs
# ============================================================================

output "dynamodb_table_name" {
  description = "Name of the DynamoDB table"
  value       = aws_dynamodb_table.realtime_data.name
}

output "dynamodb_table_arn" {
  description = "ARN of the DynamoDB table"
  value       = aws_dynamodb_table.realtime_data.arn
}

output "dynamodb_stream_arn" {
  description = "ARN of the DynamoDB stream"
  value       = aws_dynamodb_table.realtime_data.stream_arn
}

output "dynamodb_stream_label" {
  description = "Label of the DynamoDB stream"
  value       = aws_dynamodb_table.realtime_data.stream_label
}

# ============================================================================
# Lambda Function Outputs
# ============================================================================

output "lambda_function_name" {
  description = "Name of the Lambda function"
  value       = aws_lambda_function.stream_processor.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function"
  value       = aws_lambda_function.stream_processor.arn
}

output "lambda_function_invoke_arn" {
  description = "Invoke ARN of the Lambda function"
  value       = aws_lambda_function.stream_processor.invoke_arn
}

output "lambda_execution_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_execution_role.arn
}

output "lambda_dead_letter_queue_url" {
  description = "URL of the Lambda dead letter queue"
  value       = aws_sqs_queue.dlq.id
}

output "lambda_log_group_name" {
  description = "Name of the Lambda CloudWatch log group"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

# ============================================================================
# AppSync API Outputs
# ============================================================================

output "appsync_api_id" {
  description = "ID of the AppSync GraphQL API"
  value       = aws_appsync_graphql_api.main.id
}

output "appsync_api_arn" {
  description = "ARN of the AppSync GraphQL API"
  value       = aws_appsync_graphql_api.main.arn
}

output "appsync_api_url" {
  description = "GraphQL endpoint URL"
  value       = aws_appsync_graphql_api.main.uris["GRAPHQL"]
}

output "appsync_api_realtime_url" {
  description = "Real-time WebSocket endpoint URL"
  value       = aws_appsync_graphql_api.main.uris["REALTIME"]
}

output "appsync_api_name" {
  description = "Name of the AppSync GraphQL API"
  value       = aws_appsync_graphql_api.main.name
}

output "appsync_api_key" {
  description = "AppSync API key (if API_KEY authentication is used)"
  value       = var.appsync_authentication_type == "API_KEY" ? aws_appsync_api_key.main[0].key : null
  sensitive   = true
}

output "appsync_api_key_id" {
  description = "AppSync API key ID (if API_KEY authentication is used)"
  value       = var.appsync_authentication_type == "API_KEY" ? aws_appsync_api_key.main[0].id : null
}

output "appsync_datasource_name" {
  description = "Name of the AppSync DynamoDB data source"
  value       = aws_appsync_datasource.dynamodb.name
}

output "appsync_datasource_arn" {
  description = "ARN of the AppSync DynamoDB data source"
  value       = aws_appsync_datasource.dynamodb.arn
}

# ============================================================================
# CloudWatch Monitoring Outputs
# ============================================================================

output "cloudwatch_lambda_log_group_name" {
  description = "Name of the Lambda CloudWatch log group"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

output "cloudwatch_appsync_log_group_name" {
  description = "Name of the AppSync CloudWatch log group (if enabled)"
  value       = var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.appsync_logs[0].name : null
}

output "cloudwatch_lambda_errors_alarm_name" {
  description = "Name of the Lambda errors CloudWatch alarm"
  value       = aws_cloudwatch_metric_alarm.lambda_errors.alarm_name
}

output "cloudwatch_dynamodb_throttling_alarm_name" {
  description = "Name of the DynamoDB throttling CloudWatch alarm"
  value       = aws_cloudwatch_metric_alarm.dynamodb_throttling.alarm_name
}

# ============================================================================
# IAM Role Outputs
# ============================================================================

output "appsync_dynamodb_role_arn" {
  description = "ARN of the AppSync DynamoDB service role"
  value       = aws_iam_role.appsync_dynamodb_role.arn
}

output "appsync_logs_role_arn" {
  description = "ARN of the AppSync CloudWatch logs role (if enabled)"
  value       = var.enable_cloudwatch_logs ? aws_iam_role.appsync_logs_role[0].arn : null
}

# ============================================================================
# Event Source Mapping Outputs
# ============================================================================

output "event_source_mapping_uuid" {
  description = "UUID of the Lambda event source mapping"
  value       = aws_lambda_event_source_mapping.dynamodb_stream.uuid
}

output "event_source_mapping_state" {
  description = "State of the Lambda event source mapping"
  value       = aws_lambda_event_source_mapping.dynamodb_stream.state
}

# ============================================================================
# Utility Outputs
# ============================================================================

output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "aws_account_id" {
  description = "AWS account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

output "resource_name_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_string.suffix.result
}

output "common_tags" {
  description = "Common tags applied to all resources"
  value       = local.common_tags
}

# ============================================================================
# GraphQL Sample Queries and Mutations
# ============================================================================

output "sample_graphql_queries" {
  description = "Sample GraphQL queries for testing"
  value = {
    create_mutation = <<-EOT
      mutation CreateDataItem($input: CreateDataItemInput!) {
        createDataItem(input: $input) {
          id
          title
          content
          timestamp
          version
        }
      }
    EOT
    
    update_mutation = <<-EOT
      mutation UpdateDataItem($input: UpdateDataItemInput!) {
        updateDataItem(input: $input) {
          id
          title
          content
          timestamp
          version
        }
      }
    EOT
    
    delete_mutation = <<-EOT
      mutation DeleteDataItem($id: ID!) {
        deleteDataItem(id: $id) {
          id
          title
          content
          timestamp
          version
        }
      }
    EOT
    
    get_query = <<-EOT
      query GetDataItem($id: ID!) {
        getDataItem(id: $id) {
          id
          title
          content
          timestamp
          version
        }
      }
    EOT
    
    list_query = <<-EOT
      query ListDataItems {
        listDataItems {
          id
          title
          content
          timestamp
          version
        }
      }
    EOT
    
    subscription_created = <<-EOT
      subscription OnDataItemCreated {
        onDataItemCreated {
          id
          title
          content
          timestamp
          version
        }
      }
    EOT
    
    subscription_updated = <<-EOT
      subscription OnDataItemUpdated {
        onDataItemUpdated {
          id
          title
          content
          timestamp
          version
        }
      }
    EOT
    
    subscription_deleted = <<-EOT
      subscription OnDataItemDeleted {
        onDataItemDeleted {
          id
          title
          content
          timestamp
          version
        }
      }
    EOT
  }
}

output "sample_mutation_variables" {
  description = "Sample variables for GraphQL mutations"
  value = {
    create_variables = <<-EOT
      {
        "input": {
          "title": "Sample Real-time Item",
          "content": "This is a test item for real-time synchronization"
        }
      }
    EOT
    
    update_variables = <<-EOT
      {
        "input": {
          "id": "ITEM_ID_HERE",
          "title": "Updated Real-time Item",
          "content": "This item has been updated for real-time synchronization"
        }
      }
    EOT
    
    delete_variables = <<-EOT
      {
        "id": "ITEM_ID_HERE"
      }
    EOT
    
    get_variables = <<-EOT
      {
        "id": "ITEM_ID_HERE"
      }
    EOT
  }
}

# ============================================================================
# Curl Commands for Testing
# ============================================================================

output "curl_test_commands" {
  description = "Curl commands for testing the AppSync API"
  value = var.appsync_authentication_type == "API_KEY" ? {
    create_item = <<-EOT
      curl -X POST \
        -H "Content-Type: application/json" \
        -H "x-api-key: ${aws_appsync_api_key.main[0].key}" \
        -d '{"query":"mutation CreateItem($input: CreateDataItemInput!) { createDataItem(input: $input) { id title content timestamp version } }","variables":{"input":{"title":"Test Item","content":"Testing real-time sync"}}}' \
        ${aws_appsync_graphql_api.main.uris["GRAPHQL"]}
    EOT
    
    list_items = <<-EOT
      curl -X POST \
        -H "Content-Type: application/json" \
        -H "x-api-key: ${aws_appsync_api_key.main[0].key}" \
        -d '{"query":"query ListItems { listDataItems { id title content timestamp version } }"}' \
        ${aws_appsync_graphql_api.main.uris["GRAPHQL"]}
    EOT
  } : null
  
  sensitive = true
}

# ============================================================================
# Deployment Instructions
# ============================================================================

output "deployment_instructions" {
  description = "Instructions for deploying and testing the solution"
  value = <<-EOT
    # Real-time Data Synchronization with AWS AppSync and DynamoDB Streams
    
    ## Deployment Complete!
    
    Your real-time data synchronization infrastructure has been deployed successfully.
    
    ### Key Resources Created:
    - DynamoDB Table: ${aws_dynamodb_table.realtime_data.name}
    - Lambda Function: ${aws_lambda_function.stream_processor.function_name}
    - AppSync API: ${aws_appsync_graphql_api.main.name}
    - GraphQL Endpoint: ${aws_appsync_graphql_api.main.uris["GRAPHQL"]}
    - Real-time WebSocket: ${aws_appsync_graphql_api.main.uris["REALTIME"]}
    
    ### Testing the Solution:
    
    1. Use the provided curl commands to test mutations
    2. Set up GraphQL subscriptions to test real-time features
    3. Monitor CloudWatch logs for Lambda function execution
    4. Check DynamoDB streams for change events
    
    ### Next Steps:
    
    1. Implement client-side subscription handlers
    2. Add authentication and authorization
    3. Implement advanced filtering and routing
    4. Set up monitoring and alerting
    5. Add error handling and retry logic
    
    ### Monitoring:
    
    - Lambda Logs: ${aws_cloudwatch_log_group.lambda_logs.name}
    - AppSync Logs: ${var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.appsync_logs[0].name : "Not enabled"}
    - CloudWatch Alarms: Created for errors and throttling
    
    ### Security:
    
    - API Authentication: ${var.appsync_authentication_type}
    - DynamoDB Encryption: Enabled at rest
    - IAM Roles: Least privilege access configured
    
    For detailed usage instructions, refer to the original recipe documentation.
  EOT
}