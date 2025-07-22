# EventBridge outputs
output "event_bus_name" {
  description = "Name of the custom EventBridge bus"
  value       = aws_cloudwatch_event_bus.event_sourcing_bus.name
}

output "event_bus_arn" {
  description = "ARN of the custom EventBridge bus"
  value       = aws_cloudwatch_event_bus.event_sourcing_bus.arn
}

output "event_archive_name" {
  description = "Name of the event archive for replay capability"
  value       = aws_cloudwatch_event_archive.event_archive.name
}

# DynamoDB outputs
output "event_store_table_name" {
  description = "Name of the DynamoDB event store table"
  value       = aws_dynamodb_table.event_store.name
}

output "event_store_table_arn" {
  description = "ARN of the DynamoDB event store table"
  value       = aws_dynamodb_table.event_store.arn
}

output "event_store_stream_arn" {
  description = "ARN of the DynamoDB event store stream"
  value       = aws_dynamodb_table.event_store.stream_arn
}

output "read_model_table_name" {
  description = "Name of the DynamoDB read model table"
  value       = aws_dynamodb_table.read_model.name
}

output "read_model_table_arn" {
  description = "ARN of the DynamoDB read model table"
  value       = aws_dynamodb_table.read_model.arn
}

# Lambda function outputs
output "command_handler_function_name" {
  description = "Name of the command handler Lambda function"
  value       = aws_lambda_function.command_handler.function_name
}

output "command_handler_function_arn" {
  description = "ARN of the command handler Lambda function"
  value       = aws_lambda_function.command_handler.arn
}

output "projection_handler_function_name" {
  description = "Name of the projection handler Lambda function"
  value       = aws_lambda_function.projection_handler.function_name
}

output "projection_handler_function_arn" {
  description = "ARN of the projection handler Lambda function"
  value       = aws_lambda_function.projection_handler.arn
}

output "query_handler_function_name" {
  description = "Name of the query handler Lambda function"
  value       = aws_lambda_function.query_handler.function_name
}

output "query_handler_function_arn" {
  description = "ARN of the query handler Lambda function"
  value       = aws_lambda_function.query_handler.arn
}

# IAM outputs
output "lambda_execution_role_name" {
  description = "Name of the IAM role for Lambda functions"
  value       = aws_iam_role.lambda_execution_role.name
}

output "lambda_execution_role_arn" {
  description = "ARN of the IAM role for Lambda functions"
  value       = aws_iam_role.lambda_execution_role.arn
}

# SQS outputs
output "dead_letter_queue_name" {
  description = "Name of the SQS dead letter queue"
  value       = aws_sqs_queue.dead_letter_queue.name
}

output "dead_letter_queue_url" {
  description = "URL of the SQS dead letter queue"
  value       = aws_sqs_queue.dead_letter_queue.url
}

output "dead_letter_queue_arn" {
  description = "ARN of the SQS dead letter queue"
  value       = aws_sqs_queue.dead_letter_queue.arn
}

# EventBridge rules outputs
output "financial_events_rule_name" {
  description = "Name of the EventBridge rule for financial events"
  value       = aws_cloudwatch_event_rule.financial_events_rule.name
}

output "financial_events_rule_arn" {
  description = "ARN of the EventBridge rule for financial events"
  value       = aws_cloudwatch_event_rule.financial_events_rule.arn
}

# CloudWatch alarms outputs
output "cloudwatch_alarms_enabled" {
  description = "Whether CloudWatch alarms are enabled"
  value       = var.enable_cloudwatch_alarms
}

output "event_store_write_throttles_alarm_name" {
  description = "Name of the CloudWatch alarm for DynamoDB write throttles"
  value       = var.enable_cloudwatch_alarms ? aws_cloudwatch_metric_alarm.event_store_write_throttles[0].alarm_name : null
}

output "command_handler_errors_alarm_name" {
  description = "Name of the CloudWatch alarm for command handler errors"
  value       = var.enable_cloudwatch_alarms ? aws_cloudwatch_metric_alarm.command_handler_errors[0].alarm_name : null
}

output "eventbridge_failed_invocations_alarm_name" {
  description = "Name of the CloudWatch alarm for EventBridge failed invocations"
  value       = var.enable_cloudwatch_alarms ? aws_cloudwatch_metric_alarm.eventbridge_failed_invocations[0].alarm_name : null
}

# General outputs
output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "aws_account_id" {
  description = "AWS account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

output "resource_suffix" {
  description = "Suffix used for resource naming"
  value       = local.resource_suffix
}

output "environment" {
  description = "Environment designation"
  value       = var.environment
}

# Testing and validation outputs
output "test_command_payload" {
  description = "Sample payload for testing the command handler"
  value = jsonencode({
    aggregateId = "account-123"
    eventType   = "AccountCreated"
    eventData = {
      accountId    = "account-123"
      customerId   = "customer-456"
      accountType  = "checking"
      createdAt    = "2024-01-15T10:00:00Z"
    }
  })
}

output "test_query_payload" {
  description = "Sample payload for testing the query handler"
  value = jsonencode({
    queryType   = "getAccountSummary"
    accountId   = "account-123"
  })
}

# Instructions for testing
output "testing_instructions" {
  description = "Instructions for testing the deployed infrastructure"
  value = <<-EOT
    To test the deployed infrastructure:
    
    1. Test command processing:
       aws lambda invoke --function-name ${aws_lambda_function.command_handler.function_name} --payload '${jsonencode({
         aggregateId = "account-123"
         eventType   = "AccountCreated"
         eventData = {
           accountId    = "account-123"
           customerId   = "customer-456"
           accountType  = "checking"
           createdAt    = "2024-01-15T10:00:00Z"
         }
       })}' response.json
    
    2. Check the event store:
       aws dynamodb query --table-name ${aws_dynamodb_table.event_store.name} --key-condition-expression "AggregateId = :aid" --expression-attribute-values '{":aid": {"S": "account-123"}}'
    
    3. Test query processing:
       aws lambda invoke --function-name ${aws_lambda_function.query_handler.function_name} --payload '${jsonencode({
         queryType = "getAccountSummary"
         accountId = "account-123"
       })}' query_response.json
    
    4. Monitor CloudWatch logs:
       aws logs describe-log-groups --log-group-name-prefix /aws/lambda/
  EOT
}