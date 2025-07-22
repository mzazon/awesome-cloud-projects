# Output Values for CQRS Event Sourcing Infrastructure
# These outputs provide essential information for testing, integration, and management

# ========================================
# Project Information
# ========================================

output "project_name" {
  description = "The project name used for resource naming"
  value       = var.project_name
}

output "environment" {
  description = "The deployment environment"
  value       = var.environment
}

output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "aws_account_id" {
  description = "AWS account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

output "resource_name_prefix" {
  description = "The name prefix used for all resources"
  value       = local.name_prefix
}

# ========================================
# DynamoDB Tables
# ========================================

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

output "user_read_model_table_name" {
  description = "Name of the user profiles read model table"
  value       = aws_dynamodb_table.user_read_model.name
}

output "user_read_model_table_arn" {
  description = "ARN of the user profiles read model table"
  value       = aws_dynamodb_table.user_read_model.arn
}

output "order_read_model_table_name" {
  description = "Name of the order summaries read model table"
  value       = aws_dynamodb_table.order_read_model.name
}

output "order_read_model_table_arn" {
  description = "ARN of the order summaries read model table"
  value       = aws_dynamodb_table.order_read_model.arn
}

# ========================================
# EventBridge Resources
# ========================================

output "event_bus_name" {
  description = "Name of the custom EventBridge bus for domain events"
  value       = aws_cloudwatch_event_bus.domain_events.name
}

output "event_bus_arn" {
  description = "ARN of the custom EventBridge bus"
  value       = aws_cloudwatch_event_bus.domain_events.arn
}

output "event_archive_name" {
  description = "Name of the EventBridge archive for event replay"
  value       = aws_cloudwatch_event_archive.domain_events_archive.name
}

output "event_archive_arn" {
  description = "ARN of the EventBridge archive"
  value       = aws_cloudwatch_event_archive.domain_events_archive.arn
}

# ========================================
# Lambda Functions
# ========================================

output "command_handler_function_name" {
  description = "Name of the command handler Lambda function"
  value       = aws_lambda_function.command_handler.function_name
}

output "command_handler_function_arn" {
  description = "ARN of the command handler Lambda function"
  value       = aws_lambda_function.command_handler.arn
}

output "stream_processor_function_name" {
  description = "Name of the stream processor Lambda function"
  value       = aws_lambda_function.stream_processor.function_name
}

output "stream_processor_function_arn" {
  description = "ARN of the stream processor Lambda function"
  value       = aws_lambda_function.stream_processor.arn
}

output "user_projection_function_name" {
  description = "Name of the user projection Lambda function"
  value       = aws_lambda_function.user_projection.function_name
}

output "user_projection_function_arn" {
  description = "ARN of the user projection Lambda function"
  value       = aws_lambda_function.user_projection.arn
}

output "order_projection_function_name" {
  description = "Name of the order projection Lambda function"
  value       = aws_lambda_function.order_projection.function_name
}

output "order_projection_function_arn" {
  description = "ARN of the order projection Lambda function"
  value       = aws_lambda_function.order_projection.arn
}

output "query_handler_function_name" {
  description = "Name of the query handler Lambda function"
  value       = aws_lambda_function.query_handler.function_name
}

output "query_handler_function_arn" {
  description = "ARN of the query handler Lambda function"
  value       = aws_lambda_function.query_handler.arn
}

# ========================================
# IAM Roles
# ========================================

output "command_handler_role_name" {
  description = "Name of the command handler IAM role"
  value       = aws_iam_role.command_handler_role.name
}

output "command_handler_role_arn" {
  description = "ARN of the command handler IAM role"
  value       = aws_iam_role.command_handler_role.arn
}

output "projection_handler_role_name" {
  description = "Name of the projection handler IAM role"
  value       = aws_iam_role.projection_handler_role.name
}

output "projection_handler_role_arn" {
  description = "ARN of the projection handler IAM role"
  value       = aws_iam_role.projection_handler_role.arn
}

# ========================================
# EventBridge Rules
# ========================================

output "user_events_rule_name" {
  description = "Name of the EventBridge rule for user events"
  value       = aws_cloudwatch_event_rule.user_events.name
}

output "user_events_rule_arn" {
  description = "ARN of the EventBridge rule for user events"
  value       = aws_cloudwatch_event_rule.user_events.arn
}

output "order_events_rule_name" {
  description = "Name of the EventBridge rule for order events"
  value       = aws_cloudwatch_event_rule.order_events.name
}

output "order_events_rule_arn" {
  description = "ARN of the EventBridge rule for order events"
  value       = aws_cloudwatch_event_rule.order_events.arn
}

# ========================================
# Testing and Integration Information
# ========================================

output "test_commands" {
  description = "Commands for testing the CQRS implementation"
  value = {
    create_user_command = "aws lambda invoke --function-name ${aws_lambda_function.command_handler.function_name} --payload '{\"commandType\":\"CreateUser\",\"email\":\"test@example.com\",\"name\":\"Test User\"}' response.json"
    
    create_order_command = "aws lambda invoke --function-name ${aws_lambda_function.command_handler.function_name} --payload '{\"commandType\":\"CreateOrder\",\"userId\":\"USER_ID\",\"items\":[{\"product\":\"laptop\",\"quantity\":1,\"price\":999.99}],\"totalAmount\":999.99}' response.json"
    
    query_user_profile = "aws lambda invoke --function-name ${aws_lambda_function.query_handler.function_name} --payload '{\"queryType\":\"GetUserProfile\",\"userId\":\"USER_ID\"}' query_result.json"
    
    query_orders_by_user = "aws lambda invoke --function-name ${aws_lambda_function.query_handler.function_name} --payload '{\"queryType\":\"GetOrdersByUser\",\"userId\":\"USER_ID\"}' query_result.json"
    
    check_event_store = "aws dynamodb scan --table-name ${aws_dynamodb_table.event_store.name} --max-items 10"
  }
}

output "monitoring_commands" {
  description = "Commands for monitoring the CQRS system"
  value = {
    check_lambda_logs = "aws logs describe-log-groups --log-group-name-prefix '/aws/lambda/${local.name_prefix}'"
    
    check_dynamodb_streams = "aws dynamodb describe-table --table-name ${aws_dynamodb_table.event_store.name} --query 'Table.StreamSpecification'"
    
    check_eventbridge_rules = "aws events list-rules --event-bus-name ${aws_cloudwatch_event_bus.domain_events.name}"
    
    view_event_archive = "aws events describe-archive --archive-name ${aws_cloudwatch_event_archive.domain_events_archive.name}"
  }
}

# ========================================
# Cost Estimation
# ========================================

output "cost_estimation" {
  description = "Estimated monthly costs for the deployed resources"
  value = {
    disclaimer = "Costs are estimates based on minimal usage and may vary significantly based on actual usage patterns"
    
    dynamodb_tables = {
      event_store = "~$${(var.event_store_read_capacity * 0.25 + var.event_store_write_capacity * 1.25) * 24 * 30 / 1000} per month (base capacity)"
      read_models = "~$${((var.read_model_read_capacity + var.read_model_write_capacity) * 2 * 0.25 + (var.gsi_read_capacity + var.gsi_write_capacity) * 4 * 0.25) * 24 * 30 / 1000} per month (base capacity)"
    }
    
    lambda_functions = {
      note = "Lambda costs depend on invocations and duration. Estimated for light usage:"
      estimated_monthly = "~$5-15 per month for typical development/testing workload"
    }
    
    eventbridge = {
      custom_bus = "No additional charge for custom bus"
      events = "$1.00 per million events published"
      archive = "$0.10 per million events archived"
    }
    
    total_estimated = "~$10-30 per month for development/testing workload"
  }
}

# ========================================
# Security Information
# ========================================

output "security_notes" {
  description = "Important security considerations for the deployment"
  value = {
    iam_roles = {
      command_role = "Has access only to event store table - follows principle of least privilege"
      projection_role = "Has access only to read model tables - cannot modify event store"
    }
    
    encryption = {
      dynamodb = "All DynamoDB tables use AWS managed encryption at rest"
      lambda = "Lambda environment variables are encrypted with AWS managed keys"
      eventbridge = "EventBridge uses server-side encryption for events"
    }
    
    network = {
      note = "All resources operate within AWS managed networks with default security"
      recommendation = "For production, consider VPC endpoints for DynamoDB and EventBridge"
    }
    
    access_control = {
      note = "IAM policies implement strict separation between command and query sides"
      recommendation = "Review and customize IAM policies for your specific security requirements"
    }
  }
}

# ========================================
# Architecture Summary
# ========================================

output "architecture_summary" {
  description = "Summary of the deployed CQRS Event Sourcing architecture"
  value = {
    pattern = "Command Query Responsibility Segregation (CQRS) with Event Sourcing"
    
    command_side = {
      description = "Handles write operations and business commands"
      components = [
        "Command Handler Lambda (${aws_lambda_function.command_handler.function_name})",
        "Event Store DynamoDB Table (${aws_dynamodb_table.event_store.name})",
        "Stream Processor Lambda (${aws_lambda_function.stream_processor.function_name})"
      ]
    }
    
    query_side = {
      description = "Handles read operations from optimized read models"
      components = [
        "Query Handler Lambda (${aws_lambda_function.query_handler.function_name})",
        "User Read Model Table (${aws_dynamodb_table.user_read_model.name})",
        "Order Read Model Table (${aws_dynamodb_table.order_read_model.name})"
      ]
    }
    
    event_processing = {
      description = "Manages event distribution and eventual consistency"
      components = [
        "Custom EventBridge Bus (${aws_cloudwatch_event_bus.domain_events.name})",
        "User Projection Lambda (${aws_lambda_function.user_projection.function_name})",
        "Order Projection Lambda (${aws_lambda_function.order_projection.function_name})",
        "Event Archive (${aws_cloudwatch_event_archive.domain_events_archive.name})"
      ]
    }
    
    key_benefits = [
      "Independent scaling of read and write operations",
      "Complete audit trail through event sourcing",
      "Eventual consistency with real-time updates",
      "Event replay capabilities for debugging and recovery",
      "Loose coupling between bounded contexts"
    ]
  }
}