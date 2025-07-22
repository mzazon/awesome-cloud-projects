# Main infrastructure configuration for message fan-out with SNS and SQS

# Data source for current AWS account ID
data "aws_caller_identity" "current" {}

# Data source for current AWS region
data "aws_region" "current" {}

# Random string for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local values for consistent naming
locals {
  resource_prefix = "${var.project_name}-${var.environment}"
  unique_suffix   = random_string.suffix.result
  
  # Common tags for all resources
  common_tags = merge(var.additional_tags, {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  })
  
  # Queue configurations
  queue_configs = {
    inventory = {
      name          = "${local.resource_prefix}-inventory-processing-${local.unique_suffix}"
      alarm_threshold = var.queue_depth_alarm_threshold.inventory
      filter_policy = var.message_filter_policies.inventory
    }
    payment = {
      name          = "${local.resource_prefix}-payment-processing-${local.unique_suffix}"
      alarm_threshold = var.queue_depth_alarm_threshold.payment
      filter_policy = var.message_filter_policies.payment
    }
    shipping = {
      name          = "${local.resource_prefix}-shipping-notifications-${local.unique_suffix}"
      alarm_threshold = var.queue_depth_alarm_threshold.shipping
      filter_policy = var.message_filter_policies.shipping
    }
    analytics = {
      name          = "${local.resource_prefix}-analytics-reporting-${local.unique_suffix}"
      alarm_threshold = var.queue_depth_alarm_threshold.analytics
      filter_policy = null  # Analytics queue receives all messages
    }
  }
}

# ==========================================
# DEAD LETTER QUEUES (DLQ)
# ==========================================

# Dead letter queues for error handling
resource "aws_sqs_queue" "dlq" {
  for_each = local.queue_configs
  
  name = "${each.value.name}-dlq"
  
  message_retention_seconds = var.message_retention_period
  visibility_timeout_seconds = 60
  
  tags = merge(local.common_tags, {
    Name = "${each.value.name}-dlq"
    Type = "DeadLetterQueue"
    Service = title(each.key)
  })
}

# ==========================================
# PRIMARY SQS QUEUES
# ==========================================

# Primary SQS queues with DLQ redrive policy
resource "aws_sqs_queue" "primary_queues" {
  for_each = local.queue_configs
  
  name = each.value.name
  
  message_retention_seconds = var.message_retention_period
  visibility_timeout_seconds = var.visibility_timeout_seconds
  
  # Redrive policy to send failed messages to DLQ
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq[each.key].arn
    maxReceiveCount     = var.dlq_max_receive_count
  })
  
  tags = merge(local.common_tags, {
    Name = each.value.name
    Type = "PrimaryQueue"
    Service = title(each.key)
  })
}

# ==========================================
# SNS TOPIC
# ==========================================

# SNS topic for order events
resource "aws_sns_topic" "order_events" {
  name = "${local.resource_prefix}-order-events-${local.unique_suffix}"
  
  # Delivery policy for retry configuration
  delivery_policy = jsonencode({
    http = {
      defaultHealthyRetryPolicy = {
        numRetries         = var.sns_delivery_retry_policy.num_retries
        numNoDelayRetries  = var.sns_delivery_retry_policy.num_no_delay_retries
        minDelayTarget     = var.sns_delivery_retry_policy.min_delay_target
        maxDelayTarget     = var.sns_delivery_retry_policy.max_delay_target
        numMinDelayRetries = 0
        numMaxDelayRetries = 0
        backoffFunction    = var.sns_delivery_retry_policy.backoff_function
      }
    }
  })
  
  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-order-events-${local.unique_suffix}"
    Type = "SNSTopic"
  })
}

# ==========================================
# SQS QUEUE POLICIES
# ==========================================

# Queue policies to allow SNS to send messages
resource "aws_sqs_queue_policy" "queue_policies" {
  for_each = local.queue_configs
  
  queue_url = aws_sqs_queue.primary_queues[each.key].id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = "*"
        Action = "sqs:SendMessage"
        Resource = aws_sqs_queue.primary_queues[each.key].arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = aws_sns_topic.order_events.arn
          }
        }
      }
    ]
  })
}

# ==========================================
# SNS SUBSCRIPTIONS
# ==========================================

# SNS subscriptions for queues with message filtering
resource "aws_sns_topic_subscription" "queue_subscriptions" {
  for_each = local.queue_configs
  
  topic_arn = aws_sns_topic.order_events.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.primary_queues[each.key].arn
  
  # Apply message filtering policy if defined
  filter_policy = each.value.filter_policy != null ? jsonencode({
    eventType = each.value.filter_policy.event_types
    priority  = each.value.filter_policy.priorities
  }) : null
  
  depends_on = [aws_sqs_queue_policy.queue_policies]
}

# ==========================================
# CLOUDWATCH ALARMS
# ==========================================

# CloudWatch alarms for queue depth monitoring
resource "aws_cloudwatch_metric_alarm" "queue_depth_alarms" {
  for_each = var.enable_enhanced_monitoring ? local.queue_configs : {}
  
  alarm_name          = "${each.value.name}-queue-depth"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "ApproximateNumberOfVisibleMessages"
  namespace           = "AWS/SQS"
  period              = 300
  statistic           = "Average"
  threshold           = each.value.alarm_threshold
  alarm_description   = "This metric monitors ${each.key} queue depth"
  alarm_actions       = [] # Add SNS topic ARN for notifications if needed
  
  dimensions = {
    QueueName = aws_sqs_queue.primary_queues[each.key].name
  }
  
  tags = merge(local.common_tags, {
    Name = "${each.value.name}-queue-depth-alarm"
    Type = "CloudWatchAlarm"
    Service = title(each.key)
  })
}

# CloudWatch alarm for SNS failed deliveries
resource "aws_cloudwatch_metric_alarm" "sns_failed_deliveries" {
  count = var.enable_enhanced_monitoring ? 1 : 0
  
  alarm_name          = "${local.resource_prefix}-sns-failed-deliveries-${local.unique_suffix}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "NumberOfNotificationsFailed"
  namespace           = "AWS/SNS"
  period              = 300
  statistic           = "Sum"
  threshold           = 5
  alarm_description   = "This metric monitors SNS failed deliveries"
  alarm_actions       = [] # Add SNS topic ARN for notifications if needed
  
  dimensions = {
    TopicName = aws_sns_topic.order_events.name
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-sns-failed-deliveries-alarm"
    Type = "CloudWatchAlarm"
  })
}

# ==========================================
# CLOUDWATCH DASHBOARD
# ==========================================

# CloudWatch dashboard for monitoring
resource "aws_cloudwatch_dashboard" "fanout_dashboard" {
  count = var.enable_enhanced_monitoring ? 1 : 0
  
  dashboard_name = "${local.resource_prefix}-fanout-dashboard-${local.unique_suffix}"
  
  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        
        properties = {
          metrics = [
            ["AWS/SNS", "NumberOfMessagesPublished", "TopicName", aws_sns_topic.order_events.name],
            [".", "NumberOfNotificationsFailed", ".", "."]
          ]
          period = 300
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "SNS Message Publishing"
          yAxis = {
            left = {
              min = 0
            }
          }
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        
        properties = {
          metrics = [
            for queue_name, config in local.queue_configs : 
            ["AWS/SQS", "ApproximateNumberOfVisibleMessages", "QueueName", aws_sqs_queue.primary_queues[queue_name].name]
          ]
          period = 300
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "SQS Queue Depths"
          yAxis = {
            left = {
              min = 0
            }
          }
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 12
        width  = 12
        height = 6
        
        properties = {
          metrics = [
            for queue_name, config in local.queue_configs : 
            ["AWS/SQS", "NumberOfMessagesSent", "QueueName", aws_sqs_queue.primary_queues[queue_name].name]
          ]
          period = 300
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "SQS Messages Sent"
          yAxis = {
            left = {
              min = 0
            }
          }
        }
      }
    ]
  })
  
  depends_on = [
    aws_sqs_queue.primary_queues,
    aws_sns_topic.order_events
  ]
}

# ==========================================
# IAM ROLE FOR SNS-SQS INTEGRATION
# ==========================================

# IAM role for SNS to SQS delivery (if additional permissions needed)
resource "aws_iam_role" "sns_sqs_fanout_role" {
  name = "${local.resource_prefix}-sns-sqs-fanout-role-${local.unique_suffix}"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "sns.amazonaws.com"
        }
      }
    ]
  })
  
  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-sns-sqs-fanout-role"
    Type = "IAMRole"
  })
}

# IAM policy for SNS to write to CloudWatch Logs (optional)
resource "aws_iam_role_policy" "sns_logging_policy" {
  name = "${local.resource_prefix}-sns-logging-policy-${local.unique_suffix}"
  role = aws_iam_role.sns_sqs_fanout_role.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
      }
    ]
  })
}