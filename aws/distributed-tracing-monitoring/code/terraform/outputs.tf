# Outputs for AWS X-Ray Infrastructure Monitoring

# API Gateway Outputs
output "api_gateway_id" {
  description = "ID of the API Gateway REST API"
  value       = aws_api_gateway_rest_api.main.id
}

output "api_gateway_url" {
  description = "Base URL of the API Gateway"
  value       = "https://${aws_api_gateway_rest_api.main.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${aws_api_gateway_stage.main.stage_name}"
}

output "api_endpoint_orders" {
  description = "Complete endpoint URL for orders API"
  value       = "https://${aws_api_gateway_rest_api.main.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${aws_api_gateway_stage.main.stage_name}/orders"
}

# Lambda Function Outputs
output "order_processor_function_name" {
  description = "Name of the order processor Lambda function"
  value       = aws_lambda_function.order_processor.function_name
}

output "order_processor_function_arn" {
  description = "ARN of the order processor Lambda function"
  value       = aws_lambda_function.order_processor.arn
}

output "inventory_manager_function_name" {
  description = "Name of the inventory manager Lambda function"
  value       = aws_lambda_function.inventory_manager.function_name
}

output "inventory_manager_function_arn" {
  description = "ARN of the inventory manager Lambda function"
  value       = aws_lambda_function.inventory_manager.arn
}

output "trace_analyzer_function_name" {
  description = "Name of the trace analyzer Lambda function"
  value       = aws_lambda_function.trace_analyzer.function_name
}

output "trace_analyzer_function_arn" {
  description = "ARN of the trace analyzer Lambda function"
  value       = aws_lambda_function.trace_analyzer.arn
}

# DynamoDB Outputs
output "orders_table_name" {
  description = "Name of the DynamoDB orders table"
  value       = aws_dynamodb_table.orders.name
}

output "orders_table_arn" {
  description = "ARN of the DynamoDB orders table"
  value       = aws_dynamodb_table.orders.arn
}

# IAM Outputs
output "lambda_role_name" {
  description = "Name of the Lambda execution role"
  value       = aws_iam_role.lambda_role.name
}

output "lambda_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_role.arn
}

# X-Ray Outputs
output "xray_sampling_rules" {
  description = "List of X-Ray sampling rule names"
  value = [
    aws_xray_sampling_rule.high_priority.rule_name,
    aws_xray_sampling_rule.error_traces.rule_name
  ]
}

# CloudWatch Outputs
output "cloudwatch_dashboard_url" {
  description = "URL to the CloudWatch dashboard"
  value       = var.enable_cloudwatch_dashboard ? "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.xray_monitoring[0].dashboard_name}" : null
}

output "cloudwatch_log_groups" {
  description = "CloudWatch log group names for Lambda functions"
  value = {
    order_processor    = aws_cloudwatch_log_group.order_processor.name
    inventory_manager  = aws_cloudwatch_log_group.inventory_manager.name
    trace_analyzer     = aws_cloudwatch_log_group.trace_analyzer.name
  }
}

# EventBridge Outputs
output "eventbridge_rule_name" {
  description = "Name of the EventBridge rule for trace analysis"
  value       = aws_cloudwatch_event_rule.trace_analysis.name
}

output "eventbridge_rule_arn" {
  description = "ARN of the EventBridge rule for trace analysis"
  value       = aws_cloudwatch_event_rule.trace_analysis.arn
}

# SNS Outputs (conditional)
output "sns_topic_arn" {
  description = "ARN of the SNS topic for alerts (if created)"
  value       = var.notification_email != "" ? aws_sns_topic.alerts[0].arn : null
}

# CloudWatch Alarm Outputs (conditional)
output "cloudwatch_alarm_names" {
  description = "Names of CloudWatch alarms (if created)"
  value = var.enable_cloudwatch_alarms ? [
    aws_cloudwatch_metric_alarm.high_error_rate[0].alarm_name,
    aws_cloudwatch_metric_alarm.high_latency[0].alarm_name
  ] : []
}

# X-Ray Console URLs
output "xray_console_urls" {
  description = "URLs to access X-Ray console views"
  value = {
    service_map = "https://${data.aws_region.current.name}.console.aws.amazon.com/xray/home?region=${data.aws_region.current.name}#/service-map"
    traces      = "https://${data.aws_region.current.name}.console.aws.amazon.com/xray/home?region=${data.aws_region.current.name}#/traces"
    insights    = "https://${data.aws_region.current.name}.console.aws.amazon.com/xray/home?region=${data.aws_region.current.name}#/insights"
  }
}

# Testing Information
output "test_commands" {
  description = "Example commands for testing the deployed infrastructure"
  value = {
    create_order = "curl -X POST ${aws_api_gateway_rest_api.main.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${aws_api_gateway_stage.main.stage_name}/orders -H 'Content-Type: application/json' -d '{\"customerId\": \"test-customer\", \"productId\": \"test-product\", \"quantity\": 1}'"
    
    view_traces = "aws xray get-trace-summaries --time-range-type TimeStamp --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) --end-time $(date -u +%Y-%m-%dT%H:%M:%S) --filter-expression 'service(\"order-processor\")'"
    
    view_service_map = "aws xray get-service-graph --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) --end-time $(date -u +%Y-%m-%dT%H:%M:%S)"
  }
}

# Resource Summary
output "resource_summary" {
  description = "Summary of created resources"
  value = {
    project_name     = var.project_name
    environment      = var.environment
    aws_region       = data.aws_region.current.name
    aws_account_id   = data.aws_caller_identity.current.account_id
    suffix           = local.suffix
    
    lambda_functions = {
      order_processor   = aws_lambda_function.order_processor.function_name
      inventory_manager = aws_lambda_function.inventory_manager.function_name
      trace_analyzer    = aws_lambda_function.trace_analyzer.function_name
    }
    
    api_gateway = {
      name = aws_api_gateway_rest_api.main.name
      id   = aws_api_gateway_rest_api.main.id
      url  = "https://${aws_api_gateway_rest_api.main.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${aws_api_gateway_stage.main.stage_name}"
    }
    
    dynamodb_table = aws_dynamodb_table.orders.name
    
    monitoring = {
      dashboard_created = var.enable_cloudwatch_dashboard
      alarms_created    = var.enable_cloudwatch_alarms
      notifications     = var.notification_email != ""
    }
  }
}