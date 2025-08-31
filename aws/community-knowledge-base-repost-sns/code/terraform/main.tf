# Main Terraform configuration for Community Knowledge Base with re:Post Private and SNS
# This creates the SNS notification infrastructure for enterprise knowledge management
# Note: re:Post Private must be configured manually as it lacks Terraform provider support

# Data sources for current AWS context
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  # Common naming convention
  name_prefix = "${var.project_name}-${var.environment}"
  
  # Resource names with random suffix for uniqueness
  sns_topic_name = "${local.name_prefix}-${var.sns_topic_name}-${random_id.suffix.hex}"
  
  # Common tags for all resources
  common_tags = merge(
    {
      Name        = local.name_prefix
      Project     = var.project_name
      Environment = var.environment
      Purpose     = "Knowledge Base Notifications"
      Organization = var.organization_name
    },
    var.additional_tags
  )
}

#
# SNS Topic for Knowledge Base Notifications
#

# Primary SNS topic for knowledge base notifications
resource "aws_sns_topic" "knowledge_notifications" {
  name         = local.sns_topic_name
  display_name = var.sns_display_name

  # Enable server-side encryption with AWS managed KMS key
  kms_master_key_id = var.enable_sns_encryption ? "alias/aws/sns" : null

  # Configure message delivery retry policy
  delivery_policy = jsonencode({
    http = {
      defaultHealthyRetryPolicy = {
        minDelayTarget     = var.email_delivery_retry_policy.min_delay_target
        maxDelayTarget     = var.email_delivery_retry_policy.max_delay_target
        numRetries         = var.email_delivery_retry_policy.num_retries
        backoffFunction    = var.email_delivery_retry_policy.backoff_function
      }
      disableSubscriptionOverrides = false
      defaultThrottlePolicy = {
        maxReceivesPerSecond = 10
      }
    }
  })

  # Message retention policy
  message_retention_seconds = var.sns_message_retention_seconds

  tags = merge(
    local.common_tags,
    {
      Name = local.sns_topic_name
      Type = "SNS Topic"
    }
  )
}

#
# Email Subscriptions for Team Notifications
#

# Create email subscriptions for each provided email address
resource "aws_sns_topic_subscription" "email_notifications" {
  count     = length(var.notification_email_addresses)
  topic_arn = aws_sns_topic.knowledge_notifications.arn
  protocol  = "email"
  endpoint  = var.notification_email_addresses[count.index]

  # Apply filter policy if provided
  filter_policy = var.notification_filter_policy

  # Email subscriptions require manual confirmation
  # The subscription will remain in "PendingConfirmation" state until confirmed
  depends_on = [aws_sns_topic.knowledge_notifications]
}

#
# Dead Letter Queue (Optional)
#

# SQS Dead Letter Queue for failed message deliveries (optional)
resource "aws_sqs_queue" "dlq" {
  count = var.enable_dead_letter_queue ? 1 : 0
  
  name = "${local.name_prefix}-knowledge-dlq-${random_id.suffix.hex}"

  # Configure message retention and visibility
  message_retention_seconds = 1209600 # 14 days
  visibility_timeout_seconds = 30

  # Enable server-side encryption
  kms_master_key_id = "alias/aws/sqs"

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-knowledge-dlq-${random_id.suffix.hex}"
      Type = "SQS Dead Letter Queue"
    }
  )
}

# IAM policy to allow SNS to send messages to the dead letter queue
data "aws_iam_policy_document" "dlq_policy" {
  count = var.enable_dead_letter_queue ? 1 : 0

  statement {
    effect = "Allow"
    
    principals {
      type        = "Service"
      identifiers = ["sns.amazonaws.com"]
    }
    
    actions = [
      "sqs:SendMessage"
    ]
    
    resources = [aws_sqs_queue.dlq[0].arn]
    
    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_sns_topic.knowledge_notifications.arn]
    }
  }
}

# Attach the policy to the dead letter queue
resource "aws_sqs_queue_policy" "dlq_policy" {
  count     = var.enable_dead_letter_queue ? 1 : 0
  queue_url = aws_sqs_queue.dlq[0].id
  policy    = data.aws_iam_policy_document.dlq_policy[0].json
}

#
# CloudWatch Monitoring and Alarms
#

# CloudWatch alarm for failed message deliveries
resource "aws_cloudwatch_metric_alarm" "failed_messages" {
  count = var.enable_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${local.name_prefix}-sns-failed-messages"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "2"
  metric_name         = "NumberOfMessagesFailed"
  namespace           = "AWS/SNS"
  period              = "300"
  statistic           = "Sum"
  threshold           = var.failed_message_alarm_threshold
  alarm_description   = "This alarm monitors failed message deliveries for knowledge base notifications"
  
  dimensions = {
    TopicName = aws_sns_topic.knowledge_notifications.name
  }

  # Optional: Send alarm notifications to a separate email
  alarm_actions = var.cloudwatch_alarm_email != null ? [aws_sns_topic.alarm_notifications[0].arn] : []

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-sns-failed-messages"
      Type = "CloudWatch Alarm"
    }
  )
}

# Separate SNS topic for CloudWatch alarms (optional)
resource "aws_sns_topic" "alarm_notifications" {
  count = var.enable_cloudwatch_alarms && var.cloudwatch_alarm_email != null ? 1 : 0

  name         = "${local.name_prefix}-alarm-notifications-${random_id.suffix.hex}"
  display_name = "Knowledge Base System Alarms"

  kms_master_key_id = var.enable_sns_encryption ? "alias/aws/sns" : null

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-alarm-notifications-${random_id.suffix.hex}"
      Type = "SNS Alarm Topic"
    }
  )
}

# Email subscription for alarm notifications
resource "aws_sns_topic_subscription" "alarm_email" {
  count     = var.enable_cloudwatch_alarms && var.cloudwatch_alarm_email != null ? 1 : 0
  topic_arn = aws_sns_topic.alarm_notifications[0].arn
  protocol  = "email"
  endpoint  = var.cloudwatch_alarm_email
}

#
# SSM Parameters for Configuration Storage
#

# Store SNS topic ARN in Systems Manager Parameter Store for external access
resource "aws_ssm_parameter" "sns_topic_arn" {
  name  = "/${var.project_name}/${var.environment}/sns/knowledge-notifications/topic-arn"
  type  = "String"
  value = aws_sns_topic.knowledge_notifications.arn
  
  description = "ARN of the SNS topic for knowledge base notifications"

  tags = merge(
    local.common_tags,
    {
      Name = "SNS Topic ARN Parameter"
      Type = "SSM Parameter"
    }
  )
}

# Store topic name for easier reference
resource "aws_ssm_parameter" "sns_topic_name" {
  name  = "/${var.project_name}/${var.environment}/sns/knowledge-notifications/topic-name"
  type  = "String"
  value = aws_sns_topic.knowledge_notifications.name
  
  description = "Name of the SNS topic for knowledge base notifications"

  tags = merge(
    local.common_tags,
    {
      Name = "SNS Topic Name Parameter"
      Type = "SSM Parameter"
    }
  )
}

#
# Documentation and Setup Instructions
#

# Local file with re:Post Private setup instructions
resource "local_file" "repost_setup_instructions" {
  filename = "${path.module}/repost-private-setup-guide.md"
  content = templatefile("${path.module}/templates/repost-setup-instructions.tpl", {
    organization_name = var.organization_name
    sns_topic_arn     = aws_sns_topic.knowledge_notifications.arn
    sns_topic_name    = aws_sns_topic.knowledge_notifications.name
    aws_region        = data.aws_region.current.name
    aws_account_id    = data.aws_caller_identity.current.account_id
    project_name      = var.project_name
    environment       = var.environment
  })
}

# Local file with team onboarding checklist
resource "local_file" "team_onboarding_checklist" {
  filename = "${path.module}/team-onboarding-checklist.md"
  content = templatefile("${path.module}/templates/team-onboarding.tpl", {
    organization_name    = var.organization_name
    email_addresses      = var.notification_email_addresses
    sns_topic_name       = aws_sns_topic.knowledge_notifications.name
    cloudwatch_enabled   = var.enable_cloudwatch_alarms
    project_name         = var.project_name
  })
}