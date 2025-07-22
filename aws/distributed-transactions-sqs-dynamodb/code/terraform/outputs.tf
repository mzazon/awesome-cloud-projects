# Outputs for Distributed Transaction Processing Infrastructure

# ============================================================================
# Core Infrastructure Outputs
# ============================================================================

output "stack_name" {
  description = "Name of the deployed stack"
  value       = local.stack_name
}

output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "aws_account_id" {
  description = "AWS account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

# ============================================================================
# DynamoDB Table Outputs
# ============================================================================

output "dynamodb_tables" {
  description = "DynamoDB table information"
  value = {
    saga_state = {
      name = aws_dynamodb_table.saga_state.name
      arn  = aws_dynamodb_table.saga_state.arn
    }
    orders = {
      name = aws_dynamodb_table.orders.name
      arn  = aws_dynamodb_table.orders.arn
    }
    payments = {
      name = aws_dynamodb_table.payments.name
      arn  = aws_dynamodb_table.payments.arn
    }
    inventory = {
      name = aws_dynamodb_table.inventory.name
      arn  = aws_dynamodb_table.inventory.arn
    }
  }
}

output "saga_state_table_name" {
  description = "Name of the saga state table"
  value       = aws_dynamodb_table.saga_state.name
}

output "saga_state_table_arn" {
  description = "ARN of the saga state table"
  value       = aws_dynamodb_table.saga_state.arn
}

output "orders_table_name" {
  description = "Name of the orders table"
  value       = aws_dynamodb_table.orders.name
}

output "payments_table_name" {
  description = "Name of the payments table"
  value       = aws_dynamodb_table.payments.name
}

output "inventory_table_name" {
  description = "Name of the inventory table"
  value       = aws_dynamodb_table.inventory.name
}

# ============================================================================
# SQS Queue Outputs
# ============================================================================

output "sqs_queues" {
  description = "SQS queue information"
  value = {
    order_processing = {
      name = aws_sqs_queue.order_processing.name
      url  = aws_sqs_queue.order_processing.url
      arn  = aws_sqs_queue.order_processing.arn
    }
    payment_processing = {
      name = aws_sqs_queue.payment_processing.name
      url  = aws_sqs_queue.payment_processing.url
      arn  = aws_sqs_queue.payment_processing.arn
    }
    inventory_update = {
      name = aws_sqs_queue.inventory_update.name
      url  = aws_sqs_queue.inventory_update.url
      arn  = aws_sqs_queue.inventory_update.arn
    }
    compensation = {
      name = aws_sqs_queue.compensation.name
      url  = aws_sqs_queue.compensation.url
      arn  = aws_sqs_queue.compensation.arn
    }
    dlq = {
      name = aws_sqs_queue.dlq.name
      url  = aws_sqs_queue.dlq.url
      arn  = aws_sqs_queue.dlq.arn
    }
  }
}

output "order_processing_queue_url" {
  description = "URL of the order processing queue"
  value       = aws_sqs_queue.order_processing.url
}

output "payment_processing_queue_url" {
  description = "URL of the payment processing queue"
  value       = aws_sqs_queue.payment_processing.url
}

output "inventory_update_queue_url" {
  description = "URL of the inventory update queue"
  value       = aws_sqs_queue.inventory_update.url
}

output "compensation_queue_url" {
  description = "URL of the compensation queue"
  value       = aws_sqs_queue.compensation.url
}

output "dead_letter_queue_url" {
  description = "URL of the dead letter queue"
  value       = aws_sqs_queue.dlq.url
}

# ============================================================================
# Lambda Function Outputs
# ============================================================================

output "lambda_functions" {
  description = "Lambda function information"
  value = {
    orchestrator = {
      name = aws_lambda_function.orchestrator.function_name
      arn  = aws_lambda_function.orchestrator.arn
    }
    compensation_handler = {
      name = aws_lambda_function.compensation_handler.function_name
      arn  = aws_lambda_function.compensation_handler.arn
    }
    order_service = {
      name = aws_lambda_function.order_service.function_name
      arn  = aws_lambda_function.order_service.arn
    }
    payment_service = {
      name = aws_lambda_function.payment_service.function_name
      arn  = aws_lambda_function.payment_service.arn
    }
    inventory_service = {
      name = aws_lambda_function.inventory_service.function_name
      arn  = aws_lambda_function.inventory_service.arn
    }
  }
}

output "orchestrator_function_name" {
  description = "Name of the orchestrator Lambda function"
  value       = aws_lambda_function.orchestrator.function_name
}

output "orchestrator_function_arn" {
  description = "ARN of the orchestrator Lambda function"
  value       = aws_lambda_function.orchestrator.arn
}

# ============================================================================
# API Gateway Outputs
# ============================================================================

output "api_gateway_info" {
  description = "API Gateway information"
  value = {
    api_id      = aws_api_gateway_rest_api.transaction_api.id
    api_name    = aws_api_gateway_rest_api.transaction_api.name
    stage_name  = var.api_gateway_stage
    endpoint_url = "https://${aws_api_gateway_rest_api.transaction_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${var.api_gateway_stage}"
  }
}

output "api_gateway_url" {
  description = "Base URL of the API Gateway"
  value       = "https://${aws_api_gateway_rest_api.transaction_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${var.api_gateway_stage}"
}

output "transactions_endpoint" {
  description = "Full URL for the transactions endpoint"
  value       = "https://${aws_api_gateway_rest_api.transaction_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${var.api_gateway_stage}/transactions"
}

# ============================================================================
# IAM Role Outputs
# ============================================================================

output "lambda_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_role.arn
}

output "lambda_role_name" {
  description = "Name of the Lambda execution role"
  value       = aws_iam_role.lambda_role.name
}

# ============================================================================
# CloudWatch Monitoring Outputs
# ============================================================================

output "cloudwatch_alarms" {
  description = "CloudWatch alarm information"
  value = var.enable_monitoring ? {
    failed_transactions = {
      name = aws_cloudwatch_metric_alarm.failed_transactions[0].alarm_name
      arn  = aws_cloudwatch_metric_alarm.failed_transactions[0].arn
    }
    sqs_message_age = {
      name = aws_cloudwatch_metric_alarm.sqs_message_age[0].alarm_name
      arn  = aws_cloudwatch_metric_alarm.sqs_message_age[0].arn
    }
  } : {}
}

output "cloudwatch_dashboard_url" {
  description = "URL to the CloudWatch dashboard"
  value = var.enable_monitoring ? "https://console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.transaction_dashboard[0].dashboard_name}" : null
}

# ============================================================================
# Sample Testing Data
# ============================================================================

output "sample_transaction_request" {
  description = "Sample transaction request for testing"
  value = jsonencode({
    customerId = "CUST-001"
    productId  = "PROD-001"
    quantity   = 2
    amount     = 2599.98
  })
}

output "sample_curl_command" {
  description = "Sample curl command for testing the API"
  value = "curl -X POST -H 'Content-Type: application/json' -d '{\"customerId\": \"CUST-001\", \"productId\": \"PROD-001\", \"quantity\": 2, \"amount\": 2599.98}' https://${aws_api_gateway_rest_api.transaction_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${var.api_gateway_stage}/transactions"
}

# ============================================================================
# Resource Cleanup Commands
# ============================================================================

output "cleanup_commands" {
  description = "Commands to clean up resources manually if needed"
  value = {
    lambda_functions = "aws lambda list-functions --query 'Functions[?contains(FunctionName, `${local.stack_name}`)].FunctionName' --output text"
    dynamodb_tables  = "aws dynamodb list-tables --query 'TableNames[?contains(@, `${local.stack_name}`)]' --output text"
    sqs_queues      = "aws sqs list-queues --queue-name-prefix ${local.stack_name}"
    api_gateway     = "aws apigateway get-rest-apis --query 'items[?name==`${aws_api_gateway_rest_api.transaction_api.name}`].id' --output text"
  }
}

# ============================================================================
# Monitoring and Debugging
# ============================================================================

output "monitoring_info" {
  description = "Information for monitoring and debugging"
  value = {
    cloudwatch_log_groups = var.enable_cloudwatch_logs ? [
      "/aws/lambda/${aws_lambda_function.orchestrator.function_name}",
      "/aws/lambda/${aws_lambda_function.compensation_handler.function_name}",
      "/aws/lambda/${aws_lambda_function.order_service.function_name}",
      "/aws/lambda/${aws_lambda_function.payment_service.function_name}",
      "/aws/lambda/${aws_lambda_function.inventory_service.function_name}"
    ] : []
    
    useful_aws_cli_commands = {
      check_saga_state = "aws dynamodb scan --table-name ${aws_dynamodb_table.saga_state.name} --projection-expression 'TransactionId, #status, CurrentStep' --expression-attribute-names '{\"#status\": \"Status\"}'"
      check_inventory = "aws dynamodb scan --table-name ${aws_dynamodb_table.inventory.name} --projection-expression 'ProductId, QuantityAvailable'"
      check_queue_messages = "aws sqs get-queue-attributes --queue-url ${aws_sqs_queue.order_processing.url} --attribute-names All"
      view_logs = "aws logs describe-log-groups --log-group-name-prefix '/aws/lambda/${local.stack_name}'"
    }
  }
}

# ============================================================================
# Terraform State Information
# ============================================================================

output "terraform_state_info" {
  description = "Information about the Terraform state"
  value = {
    workspace = terraform.workspace
    random_suffix = random_string.suffix.result
    stack_name = local.stack_name
    deployment_time = timestamp()
  }
}