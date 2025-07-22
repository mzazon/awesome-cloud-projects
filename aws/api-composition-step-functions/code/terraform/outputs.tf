# outputs.tf - Output values for the API Composition infrastructure

# ========================================
# API Gateway Outputs
# ========================================

output "api_gateway_id" {
  description = "ID of the API Gateway REST API"
  value       = aws_api_gateway_rest_api.composition_api.id
}

output "api_gateway_arn" {
  description = "ARN of the API Gateway REST API"
  value       = aws_api_gateway_rest_api.composition_api.arn
}

output "api_gateway_url" {
  description = "Base URL of the API Gateway (invoke URL)"
  value       = "https://${aws_api_gateway_rest_api.composition_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${var.api_gateway_stage_name}"
}

output "api_gateway_stage_name" {
  description = "Name of the API Gateway deployment stage"
  value       = var.api_gateway_stage_name
}

output "orders_endpoint" {
  description = "Complete URL for the orders endpoint (POST)"
  value       = "https://${aws_api_gateway_rest_api.composition_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${var.api_gateway_stage_name}/orders"
}

output "status_endpoint_template" {
  description = "Template URL for the order status endpoint (GET)"
  value       = "https://${aws_api_gateway_rest_api.composition_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${var.api_gateway_stage_name}/orders/{orderId}/status"
}

# ========================================
# Step Functions Outputs
# ========================================

output "step_functions_state_machine_arn" {
  description = "ARN of the Step Functions state machine"
  value       = aws_sfn_state_machine.order_workflow.arn
}

output "step_functions_state_machine_name" {
  description = "Name of the Step Functions state machine"
  value       = aws_sfn_state_machine.order_workflow.name
}

output "step_functions_role_arn" {
  description = "ARN of the Step Functions execution role"
  value       = aws_iam_role.step_functions_role.arn
}

# ========================================
# Lambda Function Outputs
# ========================================

output "user_service_function_name" {
  description = "Name of the user validation service Lambda function"
  value       = aws_lambda_function.user_service.function_name
}

output "user_service_function_arn" {
  description = "ARN of the user validation service Lambda function"
  value       = aws_lambda_function.user_service.arn
}

output "inventory_service_function_name" {
  description = "Name of the inventory service Lambda function"
  value       = aws_lambda_function.inventory_service.function_name
}

output "inventory_service_function_arn" {
  description = "ARN of the inventory service Lambda function"
  value       = aws_lambda_function.inventory_service.arn
}

# ========================================
# DynamoDB Outputs
# ========================================

output "orders_table_name" {
  description = "Name of the DynamoDB orders table"
  value       = aws_dynamodb_table.orders.name
}

output "orders_table_arn" {
  description = "ARN of the DynamoDB orders table"
  value       = aws_dynamodb_table.orders.arn
}

output "audit_table_name" {
  description = "Name of the DynamoDB audit table"
  value       = aws_dynamodb_table.audit.name
}

output "audit_table_arn" {
  description = "ARN of the DynamoDB audit table"
  value       = aws_dynamodb_table.audit.arn
}

# ========================================
# IAM Role Outputs
# ========================================

output "lambda_execution_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_execution_role.arn
}

output "api_gateway_role_arn" {
  description = "ARN of the API Gateway execution role"
  value       = aws_iam_role.api_gateway_role.arn
}

# ========================================
# CloudWatch Outputs
# ========================================

output "step_functions_log_group_name" {
  description = "Name of the Step Functions CloudWatch log group (if logging enabled)"
  value       = var.enable_step_functions_logging ? aws_cloudwatch_log_group.step_functions_logs[0].name : null
}

output "api_gateway_log_group_name" {
  description = "Name of the API Gateway CloudWatch log group (if logging enabled)"
  value       = var.enable_api_gateway_logging ? aws_cloudwatch_log_group.api_gateway_logs[0].name : null
}

# ========================================
# Testing and Validation Outputs
# ========================================

output "test_order_curl_command" {
  description = "Example curl command to test order creation"
  value = <<-EOT
    curl -X POST "${aws_api_gateway_rest_api.composition_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${var.api_gateway_stage_name}/orders" \
      -H "Content-Type: application/json" \
      -d '{
        "orderId": "test-order-123",
        "userId": "testuser456",
        "items": [
          {
            "productId": "prod-1",
            "quantity": 2
          },
          {
            "productId": "prod-2",
            "quantity": 1
          }
        ]
      }'
  EOT
}

output "test_status_curl_command" {
  description = "Example curl command to check order status"
  value = <<-EOT
    curl -X GET "${aws_api_gateway_rest_api.composition_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${var.api_gateway_stage_name}/orders/test-order-123/status"
  EOT
}

# ========================================
# Monitoring and Management Outputs
# ========================================

output "aws_console_step_functions_url" {
  description = "AWS Console URL for Step Functions state machine"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/states/home?region=${data.aws_region.current.name}#/statemachines/view/${aws_sfn_state_machine.order_workflow.arn}"
}

output "aws_console_api_gateway_url" {
  description = "AWS Console URL for API Gateway"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/apigateway/home?region=${data.aws_region.current.name}#/apis/${aws_api_gateway_rest_api.composition_api.id}/resources"
}

output "aws_console_dynamodb_orders_url" {
  description = "AWS Console URL for DynamoDB orders table"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/dynamodbv2/home?region=${data.aws_region.current.name}#table?name=${aws_dynamodb_table.orders.name}"
}

output "aws_console_dynamodb_audit_url" {
  description = "AWS Console URL for DynamoDB audit table"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/dynamodbv2/home?region=${data.aws_region.current.name}#table?name=${aws_dynamodb_table.audit.name}"
}

# ========================================
# Resource Summary
# ========================================

output "deployment_summary" {
  description = "Summary of deployed resources"
  value = {
    project_name    = var.project_name
    environment     = var.environment
    aws_region      = data.aws_region.current.name
    aws_account_id  = data.aws_caller_identity.current.account_id
    unique_suffix   = random_id.suffix.hex
    
    api_gateway = {
      id         = aws_api_gateway_rest_api.composition_api.id
      stage_name = var.api_gateway_stage_name
      url        = "https://${aws_api_gateway_rest_api.composition_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${var.api_gateway_stage_name}"
    }
    
    step_functions = {
      state_machine_name = aws_sfn_state_machine.order_workflow.name
      state_machine_arn  = aws_sfn_state_machine.order_workflow.arn
    }
    
    lambda_functions = {
      user_service      = aws_lambda_function.user_service.function_name
      inventory_service = aws_lambda_function.inventory_service.function_name
    }
    
    dynamodb_tables = {
      orders_table = aws_dynamodb_table.orders.name
      audit_table  = aws_dynamodb_table.audit.name
    }
    
    logging_enabled = {
      step_functions = var.enable_step_functions_logging
      api_gateway    = var.enable_api_gateway_logging
    }
  }
}