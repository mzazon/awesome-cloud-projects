# EventBridge outputs
output "event_bus_name" {
  description = "Name of the custom EventBridge event bus"
  value       = aws_cloudwatch_event_bus.ecommerce_events.name
}

output "event_bus_arn" {
  description = "ARN of the custom EventBridge event bus"
  value       = aws_cloudwatch_event_bus.ecommerce_events.arn
}

# Lambda function outputs
output "lambda_function_name" {
  description = "Name of the Lambda function"
  value       = aws_lambda_function.event_processor.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function"
  value       = aws_lambda_function.event_processor.arn
}

output "lambda_invoke_arn" {
  description = "Invoke ARN of the Lambda function"
  value       = aws_lambda_function.event_processor.invoke_arn
}

# SNS topic outputs
output "sns_topic_name" {
  description = "Name of the SNS topic"
  value       = aws_sns_topic.order_notifications.name
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic"
  value       = aws_sns_topic.order_notifications.arn
}

# SQS queue outputs
output "sqs_queue_name" {
  description = "Name of the SQS queue"
  value       = aws_sqs_queue.event_processing.name
}

output "sqs_queue_arn" {
  description = "ARN of the SQS queue"
  value       = aws_sqs_queue.event_processing.arn
}

output "sqs_queue_url" {
  description = "URL of the SQS queue"
  value       = aws_sqs_queue.event_processing.url
}

# EventBridge rules outputs
output "eventbridge_rules" {
  description = "Map of EventBridge rules and their ARNs"
  value = {
    order_events_rule = {
      name = aws_cloudwatch_event_rule.order_events_rule.name
      arn  = aws_cloudwatch_event_rule.order_events_rule.arn
    }
    high_value_orders_rule = {
      name = aws_cloudwatch_event_rule.high_value_orders_rule.name
      arn  = aws_cloudwatch_event_rule.high_value_orders_rule.arn
    }
    all_events_sqs_rule = {
      name = aws_cloudwatch_event_rule.all_events_sqs_rule.name
      arn  = aws_cloudwatch_event_rule.all_events_sqs_rule.arn
    }
    user_registration_rule = {
      name = aws_cloudwatch_event_rule.user_registration_rule.name
      arn  = aws_cloudwatch_event_rule.user_registration_rule.arn
    }
  }
}

# IAM role outputs
output "eventbridge_execution_role_arn" {
  description = "ARN of the EventBridge execution role"
  value       = aws_iam_role.eventbridge_execution_role.arn
}

output "lambda_execution_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_execution_role.arn
}

# CloudWatch Log Group outputs
output "lambda_log_group_name" {
  description = "Name of the Lambda function's CloudWatch log group"
  value       = var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.lambda_logs[0].name : null
}

output "lambda_log_group_arn" {
  description = "ARN of the Lambda function's CloudWatch log group"
  value       = var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.lambda_logs[0].arn : null
}

# Configuration outputs for testing
output "high_value_order_threshold" {
  description = "Threshold amount for high-value orders"
  value       = var.high_value_order_threshold
}

# Sample event publishing commands
output "sample_event_commands" {
  description = "Sample AWS CLI commands for publishing events"
  value = {
    order_created = "aws events put-events --entries '[{\"Source\":\"ecommerce.orders\",\"DetailType\":\"Order Created\",\"Detail\":\"{\\\"orderId\\\":\\\"test-order-123\\\",\\\"customerId\\\":\\\"customer-456\\\",\\\"totalAmount\\\":1500.00,\\\"currency\\\":\\\"USD\\\"}\",\"EventBusName\":\"${aws_cloudwatch_event_bus.ecommerce_events.name}\"}]'"
    
    user_registered = "aws events put-events --entries '[{\"Source\":\"ecommerce.users\",\"DetailType\":\"User Registered\",\"Detail\":\"{\\\"userId\\\":\\\"user-789\\\",\\\"email\\\":\\\"user@example.com\\\",\\\"firstName\\\":\\\"John\\\",\\\"lastName\\\":\\\"Doe\\\"}\",\"EventBusName\":\"${aws_cloudwatch_event_bus.ecommerce_events.name}\"}]'"
    
    payment_processed = "aws events put-events --entries '[{\"Source\":\"ecommerce.payments\",\"DetailType\":\"Payment Processed\",\"Detail\":\"{\\\"paymentId\\\":\\\"payment-101\\\",\\\"orderId\\\":\\\"order-123\\\",\\\"amount\\\":299.99,\\\"currency\\\":\\\"USD\\\"}\",\"EventBusName\":\"${aws_cloudwatch_event_bus.ecommerce_events.name}\"}]'"
  }
}

# Monitoring commands
output "monitoring_commands" {
  description = "Commands for monitoring the event-driven architecture"
  value = {
    check_lambda_logs = "aws logs describe-log-streams --log-group-name /aws/lambda/${aws_lambda_function.event_processor.function_name} --order-by LastEventTime --descending --max-items 1"
    
    check_sqs_messages = "aws sqs get-queue-attributes --queue-url ${aws_sqs_queue.event_processing.url} --attribute-names ApproximateNumberOfMessages"
    
    list_eventbridge_rules = "aws events list-rules --event-bus-name ${aws_cloudwatch_event_bus.ecommerce_events.name}"
    
    get_eventbridge_metrics = "aws cloudwatch get-metric-statistics --namespace AWS/Events --metric-name SuccessfulInvocations --dimensions Name=EventBusName,Value=${aws_cloudwatch_event_bus.ecommerce_events.name} --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) --end-time $(date -u +%Y-%m-%dT%H:%M:%S) --period 300 --statistics Sum"
  }
}

# AWS account and region information
output "aws_account_id" {
  description = "AWS account ID where resources are created"
  value       = data.aws_caller_identity.current.account_id
}

output "aws_region" {
  description = "AWS region where resources are created"
  value       = data.aws_region.current.name
}

# Resource summary
output "resource_summary" {
  description = "Summary of created resources"
  value = {
    event_bus_name     = aws_cloudwatch_event_bus.ecommerce_events.name
    lambda_function    = aws_lambda_function.event_processor.function_name
    sns_topic         = aws_sns_topic.order_notifications.name
    sqs_queue         = aws_sqs_queue.event_processing.name
    eventbridge_rules = length(keys({
      order_events_rule      = aws_cloudwatch_event_rule.order_events_rule.name
      high_value_orders_rule = aws_cloudwatch_event_rule.high_value_orders_rule.name
      all_events_sqs_rule    = aws_cloudwatch_event_rule.all_events_sqs_rule.name
      user_registration_rule = aws_cloudwatch_event_rule.user_registration_rule.name
    }))
    total_targets = 6  # 2 Lambda targets + 1 SNS target + 1 SQS target + 2 Lambda targets
  }
}