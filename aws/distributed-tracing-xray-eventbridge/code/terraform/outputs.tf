# Output values for the distributed tracing infrastructure

output "api_gateway_endpoint" {
  description = "API Gateway endpoint URL for testing the distributed tracing flow"
  value       = "https://${aws_api_gateway_rest_api.tracing_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${aws_api_gateway_stage.tracing_stage.stage_name}"
}

output "api_gateway_test_url" {
  description = "Complete test URL for creating orders"
  value       = "https://${aws_api_gateway_rest_api.tracing_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${aws_api_gateway_stage.tracing_stage.stage_name}/orders/customer123"
}

output "eventbridge_custom_bus_name" {
  description = "Name of the custom EventBridge event bus"
  value       = aws_cloudwatch_event_bus.custom_bus.name
}

output "eventbridge_custom_bus_arn" {
  description = "ARN of the custom EventBridge event bus"
  value       = aws_cloudwatch_event_bus.custom_bus.arn
}

output "lambda_function_names" {
  description = "Names of all Lambda functions created"
  value = {
    order_service        = aws_lambda_function.order_service.function_name
    payment_service      = aws_lambda_function.payment_service.function_name
    inventory_service    = aws_lambda_function.inventory_service.function_name
    notification_service = aws_lambda_function.notification_service.function_name
  }
}

output "lambda_function_arns" {
  description = "ARNs of all Lambda functions created"
  value = {
    order_service        = aws_lambda_function.order_service.arn
    payment_service      = aws_lambda_function.payment_service.arn
    inventory_service    = aws_lambda_function.inventory_service.arn
    notification_service = aws_lambda_function.notification_service.arn
  }
}

output "iam_role_arn" {
  description = "ARN of the IAM role used by Lambda functions"
  value       = aws_iam_role.lambda_execution_role.arn
}

output "iam_role_name" {
  description = "Name of the IAM role used by Lambda functions"
  value       = aws_iam_role.lambda_execution_role.name
}

output "eventbridge_rules" {
  description = "EventBridge rules configuration"
  value = {
    payment_processing = {
      name = aws_cloudwatch_event_rule.payment_processing_rule.name
      arn  = aws_cloudwatch_event_rule.payment_processing_rule.arn
    }
    inventory_update = {
      name = aws_cloudwatch_event_rule.inventory_update_rule.name
      arn  = aws_cloudwatch_event_rule.inventory_update_rule.arn
    }
    notification = {
      name = aws_cloudwatch_event_rule.notification_rule.name
      arn  = aws_cloudwatch_event_rule.notification_rule.arn
    }
  }
}

output "cloudwatch_log_groups" {
  description = "CloudWatch log group names for monitoring"
  value = {
    order_service        = aws_cloudwatch_log_group.order_service_logs.name
    payment_service      = aws_cloudwatch_log_group.payment_service_logs.name
    inventory_service    = aws_cloudwatch_log_group.inventory_service_logs.name
    notification_service = aws_cloudwatch_log_group.notification_service_logs.name
    api_gateway         = var.enable_detailed_monitoring ? aws_cloudwatch_log_group.api_gateway_logs[0].name : null
  }
}

output "x_ray_console_url" {
  description = "URL to view X-Ray traces in the AWS console"
  value       = "https://console.aws.amazon.com/xray/home?region=${data.aws_region.current.name}#/traces"
}

output "x_ray_service_map_url" {
  description = "URL to view X-Ray service map in the AWS console"
  value       = "https://console.aws.amazon.com/xray/home?region=${data.aws_region.current.name}#/service-map"
}

output "testing_instructions" {
  description = "Commands to test the distributed tracing implementation"
  value = {
    curl_command = "curl -X POST -H \"Content-Type: application/json\" -d '{\"productId\": \"12345\", \"quantity\": 1}' ${aws_api_gateway_rest_api.tracing_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${aws_api_gateway_stage.tracing_stage.stage_name}/orders/customer123"
    
    view_traces = "aws xray get-trace-summaries --time-range-type TimeRangeByStartTime --start-time $(date -u -d '10 minutes ago' +%Y-%m-%dT%H:%M:%S) --end-time $(date -u +%Y-%m-%dT%H:%M:%S)"
    
    view_logs = {
      order_service        = "aws logs tail ${aws_cloudwatch_log_group.order_service_logs.name} --follow"
      payment_service      = "aws logs tail ${aws_cloudwatch_log_group.payment_service_logs.name} --follow"
      inventory_service    = "aws logs tail ${aws_cloudwatch_log_group.inventory_service_logs.name} --follow"
      notification_service = "aws logs tail ${aws_cloudwatch_log_group.notification_service_logs.name} --follow"
    }
  }
}

output "resource_summary" {
  description = "Summary of created resources"
  value = {
    total_lambda_functions = 4
    total_eventbridge_rules = 3
    api_gateway_enabled = true
    x_ray_tracing_enabled = true
    custom_event_bus = aws_cloudwatch_event_bus.custom_bus.name
    region = data.aws_region.current.name
    account_id = data.aws_caller_identity.current.account_id
  }
}

output "estimated_monthly_cost_usd" {
  description = "Estimated monthly cost in USD for low-volume usage (1000 requests/month)"
  value = {
    lambda_functions = "~$0.20 (1000 requests, 128MB, 1s avg duration)"
    api_gateway = "~$3.50 (1000 requests)"
    x_ray_traces = "~$5.00 (1000 traces recorded)"
    eventbridge_events = "~$1.00 (1000 custom events)"
    cloudwatch_logs = "~$0.50 (log ingestion and storage)"
    total_estimated = "~$10.20/month"
    note = "Actual costs may vary based on usage patterns and AWS pricing changes"
  }
}