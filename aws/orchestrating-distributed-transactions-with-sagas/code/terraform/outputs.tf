# outputs.tf - Output values for the saga patterns infrastructure

# ============================================================================
# API Gateway Outputs
# ============================================================================

output "api_gateway_url" {
  description = "Base URL of the API Gateway"
  value       = "https://${aws_api_gateway_rest_api.saga_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${var.api_gateway_stage_name}"
}

output "api_gateway_id" {
  description = "ID of the API Gateway REST API"
  value       = aws_api_gateway_rest_api.saga_api.id
}

output "orders_endpoint" {
  description = "Complete URL for the orders endpoint"
  value       = "https://${aws_api_gateway_rest_api.saga_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${var.api_gateway_stage_name}/orders"
}

# ============================================================================
# Step Functions Outputs
# ============================================================================

output "step_functions_arn" {
  description = "ARN of the Step Functions state machine"
  value       = aws_sfn_state_machine.saga_orchestrator.arn
}

output "step_functions_name" {
  description = "Name of the Step Functions state machine"
  value       = aws_sfn_state_machine.saga_orchestrator.name
}

output "step_functions_console_url" {
  description = "URL to view the Step Functions state machine in AWS Console"
  value       = "https://console.aws.amazon.com/states/home?region=${data.aws_region.current.name}#/statemachines/view/${aws_sfn_state_machine.saga_orchestrator.arn}"
}

# ============================================================================
# DynamoDB Outputs
# ============================================================================

output "dynamodb_table_orders" {
  description = "Name of the orders DynamoDB table"
  value       = aws_dynamodb_table.orders.name
}

output "dynamodb_table_inventory" {
  description = "Name of the inventory DynamoDB table"
  value       = aws_dynamodb_table.inventory.name
}

output "dynamodb_table_payments" {
  description = "Name of the payments DynamoDB table"
  value       = aws_dynamodb_table.payments.name
}

output "dynamodb_table_arns" {
  description = "ARNs of all DynamoDB tables"
  value = {
    orders    = aws_dynamodb_table.orders.arn
    inventory = aws_dynamodb_table.inventory.arn
    payments  = aws_dynamodb_table.payments.arn
  }
}

# ============================================================================
# Lambda Function Outputs
# ============================================================================

output "lambda_functions" {
  description = "Details of all Lambda functions"
  value = {
    order_service = {
      function_name = aws_lambda_function.order_service.function_name
      arn          = aws_lambda_function.order_service.arn
    }
    inventory_service = {
      function_name = aws_lambda_function.inventory_service.function_name
      arn          = aws_lambda_function.inventory_service.arn
    }
    payment_service = {
      function_name = aws_lambda_function.payment_service.function_name
      arn          = aws_lambda_function.payment_service.arn
    }
    notification_service = {
      function_name = aws_lambda_function.notification_service.function_name
      arn          = aws_lambda_function.notification_service.arn
    }
    cancel_order = {
      function_name = aws_lambda_function.cancel_order.function_name
      arn          = aws_lambda_function.cancel_order.arn
    }
    revert_inventory = {
      function_name = aws_lambda_function.revert_inventory.function_name
      arn          = aws_lambda_function.revert_inventory.arn
    }
    refund_payment = {
      function_name = aws_lambda_function.refund_payment.function_name
      arn          = aws_lambda_function.refund_payment.arn
    }
  }
}

# ============================================================================
# SNS Outputs
# ============================================================================

output "sns_topic_arn" {
  description = "ARN of the SNS topic for notifications"
  value       = aws_sns_topic.notifications.arn
}

output "sns_topic_name" {
  description = "Name of the SNS topic for notifications"
  value       = aws_sns_topic.notifications.name
}

# ============================================================================
# CloudWatch Outputs
# ============================================================================

output "cloudwatch_log_groups" {
  description = "Names of CloudWatch log groups"
  value = {
    step_functions = aws_cloudwatch_log_group.step_functions.name
    api_gateway    = var.enable_api_gateway_logging ? aws_cloudwatch_log_group.api_gateway_logs[0].name : null
    lambda_logs    = { for k, v in aws_cloudwatch_log_group.lambda_logs : k => v.name }
  }
}

# ============================================================================
# IAM Role Outputs
# ============================================================================

output "iam_roles" {
  description = "ARNs of IAM roles created"
  value = {
    lambda_execution_role = aws_iam_role.lambda_execution_role.arn
    step_functions_role   = aws_iam_role.step_functions_role.arn
    api_gateway_role      = aws_iam_role.api_gateway_role.arn
  }
}

# ============================================================================
# Resource Naming Outputs
# ============================================================================

output "resource_suffix" {
  description = "Random suffix used for resource naming"
  value       = local.resource_suffix
}

output "common_tags" {
  description = "Common tags applied to all resources"
  value       = local.common_tags
}

# ============================================================================
# Configuration Outputs
# ============================================================================

output "configuration" {
  description = "Configuration settings used for deployment"
  value = {
    aws_region                  = data.aws_region.current.name
    environment                 = var.environment
    project_name               = var.project_name
    lambda_runtime             = var.lambda_runtime
    lambda_timeout             = var.lambda_timeout
    dynamodb_billing_mode      = var.dynamodb_billing_mode
    step_functions_logging_level = var.step_functions_logging_level
    api_gateway_stage_name     = var.api_gateway_stage_name
    payment_failure_rate       = var.payment_failure_rate
    enable_api_gateway_logging = var.enable_api_gateway_logging
    enable_x_ray_tracing       = var.enable_x_ray_tracing
    cloudwatch_log_retention_days = var.cloudwatch_log_retention_days
  }
}

# ============================================================================
# Testing and Validation Outputs
# ============================================================================

output "testing_commands" {
  description = "Commands to test the saga pattern implementation"
  value = {
    test_successful_order = <<-EOT
      curl -X POST ${aws_api_gateway_rest_api.saga_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${var.api_gateway_stage_name}/orders \
        -H "Content-Type: application/json" \
        -d '{
          "customerId": "customer-123",
          "productId": "laptop-001",
          "quantity": 2,
          "amount": 1999.98
        }'
    EOT
    
    test_insufficient_inventory = <<-EOT
      curl -X POST ${aws_api_gateway_rest_api.saga_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${var.api_gateway_stage_name}/orders \
        -H "Content-Type: application/json" \
        -d '{
          "customerId": "customer-456",
          "productId": "laptop-001",
          "quantity": 20,
          "amount": 19999.80
        }'
    EOT
    
    list_executions = <<-EOT
      aws stepfunctions list-executions \
        --state-machine-arn ${aws_sfn_state_machine.saga_orchestrator.arn} \
        --max-items 5
    EOT
    
    check_inventory = <<-EOT
      aws dynamodb scan \
        --table-name ${aws_dynamodb_table.inventory.name} \
        --query 'Items[*].[productId.S, quantity.N, reserved.N]' \
        --output table
    EOT
    
    check_orders = <<-EOT
      aws dynamodb scan \
        --table-name ${aws_dynamodb_table.orders.name} \
        --query 'Items[*].[orderId.S, customerId.S, status.S]' \
        --output table
    EOT
    
    check_payments = <<-EOT
      aws dynamodb scan \
        --table-name ${aws_dynamodb_table.payments.name} \
        --query 'Items[*].[paymentId.S, orderId.S, status.S, type.S]' \
        --output table
    EOT
  }
}

# ============================================================================
# Cleanup Commands
# ============================================================================

output "cleanup_commands" {
  description = "Commands to clean up resources"
  value = {
    terraform_destroy = "terraform destroy -auto-approve"
    manual_cleanup = <<-EOT
      # Clean up any remaining executions
      aws stepfunctions list-executions \
        --state-machine-arn ${aws_sfn_state_machine.saga_orchestrator.arn} \
        --status-filter RUNNING \
        --query 'executions[*].executionArn' \
        --output text | xargs -r -n1 aws stepfunctions stop-execution --execution-arn
      
      # Empty DynamoDB tables if needed
      aws dynamodb scan --table-name ${aws_dynamodb_table.orders.name} --query 'Items[*].orderId.S' --output text | xargs -r -n1 -I {} aws dynamodb delete-item --table-name ${aws_dynamodb_table.orders.name} --key '{"orderId":{"S":"{}"}}'
    EOT
  }
}

# ============================================================================
# Monitoring and Observability
# ============================================================================

output "monitoring_resources" {
  description = "Monitoring and observability resources"
  value = {
    step_functions_logs = aws_cloudwatch_log_group.step_functions.name
    api_gateway_logs    = var.enable_api_gateway_logging ? aws_cloudwatch_log_group.api_gateway_logs[0].name : null
    cloudwatch_dashboard_url = "https://console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:"
    x_ray_traces_url = var.enable_x_ray_tracing ? "https://console.aws.amazon.com/xray/home?region=${data.aws_region.current.name}#/traces" : null
  }
}