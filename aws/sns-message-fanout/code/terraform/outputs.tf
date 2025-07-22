# Outputs for the message fan-out SNS and SQS infrastructure

# ==========================================
# SNS TOPIC OUTPUTS
# ==========================================

output "sns_topic_arn" {
  description = "ARN of the SNS topic for order events"
  value       = aws_sns_topic.order_events.arn
}

output "sns_topic_name" {
  description = "Name of the SNS topic"
  value       = aws_sns_topic.order_events.name
}

output "sns_topic_id" {
  description = "ID of the SNS topic"
  value       = aws_sns_topic.order_events.id
}

# ==========================================
# SQS QUEUE OUTPUTS
# ==========================================

output "sqs_queue_urls" {
  description = "URLs of all primary SQS queues"
  value = {
    for queue_name, config in local.queue_configs :
    queue_name => aws_sqs_queue.primary_queues[queue_name].id
  }
}

output "sqs_queue_arns" {
  description = "ARNs of all primary SQS queues"
  value = {
    for queue_name, config in local.queue_configs :
    queue_name => aws_sqs_queue.primary_queues[queue_name].arn
  }
}

output "sqs_queue_names" {
  description = "Names of all primary SQS queues"
  value = {
    for queue_name, config in local.queue_configs :
    queue_name => aws_sqs_queue.primary_queues[queue_name].name
  }
}

# ==========================================
# DEAD LETTER QUEUE OUTPUTS
# ==========================================

output "dlq_urls" {
  description = "URLs of all dead letter queues"
  value = {
    for queue_name, config in local.queue_configs :
    queue_name => aws_sqs_queue.dlq[queue_name].id
  }
}

output "dlq_arns" {
  description = "ARNs of all dead letter queues"
  value = {
    for queue_name, config in local.queue_configs :
    queue_name => aws_sqs_queue.dlq[queue_name].arn
  }
}

output "dlq_names" {
  description = "Names of all dead letter queues"
  value = {
    for queue_name, config in local.queue_configs :
    queue_name => aws_sqs_queue.dlq[queue_name].name
  }
}

# ==========================================
# SUBSCRIPTION OUTPUTS
# ==========================================

output "sns_subscription_arns" {
  description = "ARNs of all SNS subscriptions"
  value = {
    for queue_name, config in local.queue_configs :
    queue_name => aws_sns_topic_subscription.queue_subscriptions[queue_name].arn
  }
}

output "sns_subscription_filter_policies" {
  description = "Filter policies applied to SNS subscriptions"
  value = {
    for queue_name, config in local.queue_configs :
    queue_name => config.filter_policy
  }
}

# ==========================================
# CLOUDWATCH OUTPUTS
# ==========================================

output "cloudwatch_alarm_names" {
  description = "Names of CloudWatch alarms for queue monitoring"
  value = var.enable_enhanced_monitoring ? {
    for queue_name, config in local.queue_configs :
    queue_name => aws_cloudwatch_metric_alarm.queue_depth_alarms[queue_name].alarm_name
  } : {}
}

output "cloudwatch_dashboard_name" {
  description = "Name of the CloudWatch dashboard"
  value = var.enable_enhanced_monitoring ? aws_cloudwatch_dashboard.fanout_dashboard[0].dashboard_name : null
}

output "cloudwatch_dashboard_url" {
  description = "URL to access the CloudWatch dashboard"
  value = var.enable_enhanced_monitoring ? "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.fanout_dashboard[0].dashboard_name}" : null
}

# ==========================================
# IAM OUTPUTS
# ==========================================

output "iam_role_arn" {
  description = "ARN of the IAM role for SNS-SQS integration"
  value       = aws_iam_role.sns_sqs_fanout_role.arn
}

output "iam_role_name" {
  description = "Name of the IAM role"
  value       = aws_iam_role.sns_sqs_fanout_role.name
}

# ==========================================
# CONFIGURATION OUTPUTS
# ==========================================

output "deployment_configuration" {
  description = "Summary of deployment configuration"
  value = {
    project_name     = var.project_name
    environment      = var.environment
    aws_region       = var.aws_region
    resource_prefix  = local.resource_prefix
    unique_suffix    = local.unique_suffix
    monitoring_enabled = var.enable_enhanced_monitoring
    message_retention_days = var.message_retention_period / 86400
    dlq_max_receive_count = var.dlq_max_receive_count
  }
}

# ==========================================
# TESTING OUTPUTS
# ==========================================

output "test_commands" {
  description = "CLI commands for testing the message fan-out system"
  value = {
    publish_inventory_event = "aws sns publish --topic-arn ${aws_sns_topic.order_events.arn} --message '{\"orderId\":\"test-order-123\",\"productId\":\"product-456\",\"quantity\":2}' --message-attributes '{\"eventType\":{\"DataType\":\"String\",\"StringValue\":\"inventory_update\"},\"priority\":{\"DataType\":\"String\",\"StringValue\":\"high\"}}'"
    
    publish_payment_event = "aws sns publish --topic-arn ${aws_sns_topic.order_events.arn} --message '{\"orderId\":\"test-order-123\",\"paymentId\":\"payment-789\",\"amount\":99.99}' --message-attributes '{\"eventType\":{\"DataType\":\"String\",\"StringValue\":\"payment_confirmation\"},\"priority\":{\"DataType\":\"String\",\"StringValue\":\"high\"}}'"
    
    check_inventory_queue = "aws sqs receive-message --queue-url ${aws_sqs_queue.primary_queues["inventory"].id} --max-number-of-messages 10 --wait-time-seconds 10"
    
    check_analytics_queue = "aws sqs receive-message --queue-url ${aws_sqs_queue.primary_queues["analytics"].id} --max-number-of-messages 10 --wait-time-seconds 10"
    
    monitor_queue_depth = "aws cloudwatch get-metric-statistics --namespace AWS/SQS --metric-name ApproximateNumberOfVisibleMessages --dimensions Name=QueueName,Value=${aws_sqs_queue.primary_queues["inventory"].name} --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) --end-time $(date -u +%Y-%m-%dT%H:%M:%S) --period 300 --statistics Average"
  }
}

# ==========================================
# RESOURCE SUMMARY
# ==========================================

output "resource_summary" {
  description = "Summary of all created resources"
  value = {
    sns_topics = 1
    sqs_queues = length(local.queue_configs) * 2  # Primary + DLQ
    sns_subscriptions = length(local.queue_configs)
    cloudwatch_alarms = var.enable_enhanced_monitoring ? length(local.queue_configs) + 1 : 0
    cloudwatch_dashboards = var.enable_enhanced_monitoring ? 1 : 0
    iam_roles = 1
    total_resources = 1 + (length(local.queue_configs) * 2) + length(local.queue_configs) + (var.enable_enhanced_monitoring ? length(local.queue_configs) + 1 : 0) + (var.enable_enhanced_monitoring ? 1 : 0) + 1
  }
}