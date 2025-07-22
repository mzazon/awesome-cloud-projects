# Output Values
# This file defines outputs that provide important information about the deployed infrastructure

# EventBridge Outputs
output "eventbridge_bus_name" {
  description = "Name of the custom EventBridge bus"
  value       = aws_cloudwatch_event_bus.microservices_bus.name
}

output "eventbridge_bus_arn" {
  description = "ARN of the custom EventBridge bus"
  value       = aws_cloudwatch_event_bus.microservices_bus.arn
}

# DynamoDB Outputs
output "dynamodb_table_name" {
  description = "Name of the DynamoDB orders table"
  value       = aws_dynamodb_table.orders.name
}

output "dynamodb_table_arn" {
  description = "ARN of the DynamoDB orders table"
  value       = aws_dynamodb_table.orders.arn
}

# Lambda Function Outputs
output "lambda_functions" {
  description = "Map of Lambda function names and their ARNs"
  value = {
    order_service       = aws_lambda_function.order_service.arn
    payment_service     = aws_lambda_function.payment_service.arn
    inventory_service   = aws_lambda_function.inventory_service.arn
    notification_service = aws_lambda_function.notification_service.arn
  }
}

output "order_service_function_name" {
  description = "Name of the Order Service Lambda function"
  value       = aws_lambda_function.order_service.function_name
}

output "payment_service_function_name" {
  description = "Name of the Payment Service Lambda function"
  value       = aws_lambda_function.payment_service.function_name
}

output "inventory_service_function_name" {
  description = "Name of the Inventory Service Lambda function"
  value       = aws_lambda_function.inventory_service.function_name
}

output "notification_service_function_name" {
  description = "Name of the Notification Service Lambda function"
  value       = aws_lambda_function.notification_service.function_name
}

# Step Functions Outputs
output "state_machine_arn" {
  description = "ARN of the Step Functions state machine"
  value       = aws_sfn_state_machine.order_processing.arn
}

output "state_machine_name" {
  description = "Name of the Step Functions state machine"
  value       = aws_sfn_state_machine.order_processing.name
}

# IAM Role Outputs
output "lambda_execution_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_execution_role.arn
}

output "step_functions_execution_role_arn" {
  description = "ARN of the Step Functions execution role"
  value       = aws_iam_role.step_functions_execution_role.arn
}

# CloudWatch Outputs
output "cloudwatch_log_groups" {
  description = "Map of CloudWatch log group names and ARNs"
  value = {
    order_service        = aws_cloudwatch_log_group.order_service.arn
    payment_service      = aws_cloudwatch_log_group.payment_service.arn
    inventory_service    = aws_cloudwatch_log_group.inventory_service.arn
    notification_service = aws_cloudwatch_log_group.notification_service.arn
    step_functions       = aws_cloudwatch_log_group.step_functions.arn
  }
}

output "cloudwatch_dashboard_url" {
  description = "URL to the CloudWatch dashboard (if enhanced monitoring is enabled)"
  value = var.enable_enhanced_monitoring ? "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.microservices_dashboard[0].dashboard_name}" : "Enhanced monitoring is disabled"
}

# EventBridge Rules Outputs
output "eventbridge_rules" {
  description = "Map of EventBridge rule names and ARNs"
  value = {
    order_created_rule = aws_cloudwatch_event_rule.order_created.arn
    payment_events_rule = aws_cloudwatch_event_rule.payment_events.arn
  }
}

# Resource Name Outputs for Integration
output "resource_names" {
  description = "Map of all resource names for easy reference"
  value = {
    project_name               = var.project_name
    environment               = var.environment
    eventbridge_bus           = aws_cloudwatch_event_bus.microservices_bus.name
    dynamodb_table            = aws_dynamodb_table.orders.name
    order_service_function    = aws_lambda_function.order_service.function_name
    payment_service_function  = aws_lambda_function.payment_service.function_name
    inventory_service_function = aws_lambda_function.inventory_service.function_name
    notification_service_function = aws_lambda_function.notification_service.function_name
    state_machine             = aws_sfn_state_machine.order_processing.name
  }
}

# Testing and Validation Outputs
output "test_order_command" {
  description = "AWS CLI command to test the order processing workflow"
  value = "aws lambda invoke --function-name ${aws_lambda_function.order_service.function_name} --payload '{\"customerId\":\"customer-123\",\"items\":[{\"productId\":\"prod-001\",\"quantity\":2,\"price\":29.99}],\"totalAmount\":59.98}' test-response.json"
}

output "step_functions_console_url" {
  description = "URL to view Step Functions executions in AWS Console"
  value = "https://${var.aws_region}.console.aws.amazon.com/states/home?region=${var.aws_region}#/statemachines/view/${aws_sfn_state_machine.order_processing.arn}"
}

output "eventbridge_console_url" {
  description = "URL to view EventBridge in AWS Console"
  value = "https://${var.aws_region}.console.aws.amazon.com/events/home?region=${var.aws_region}#/eventbus/${aws_cloudwatch_event_bus.microservices_bus.name}"
}