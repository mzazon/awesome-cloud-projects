# AWS Health Notifications Infrastructure
# This Terraform configuration creates an automated notification system for AWS Health events
# using SNS, EventBridge, and IAM to deliver real-time service health alerts

# Data sources for current AWS account and region information
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource naming if not provided
resource "random_id" "suffix" {
  count       = var.resource_name_suffix == "" ? 1 : 0
  byte_length = 3
}

locals {
  # Determine the suffix to use for resource naming
  name_suffix = var.resource_name_suffix != "" ? var.resource_name_suffix : (
    length(random_id.suffix) > 0 ? random_id.suffix[0].hex : ""
  )
  
  # Base name for all resources
  base_name = var.project_name
  
  # Full resource names with optional suffix
  sns_topic_name = local.name_suffix != "" ? "${local.base_name}-${local.name_suffix}" : local.base_name
  eventbridge_rule_name = local.name_suffix != "" ? "aws-health-events-rule-${local.name_suffix}" : "aws-health-events-rule"
  iam_role_name = local.name_suffix != "" ? "HealthNotificationRole-${local.name_suffix}" : "HealthNotificationRole"
  
  # Combine primary email with additional emails for subscriptions
  all_email_addresses = var.create_email_subscription ? concat([var.notification_email], var.additional_email_addresses) : var.additional_email_addresses
  
  # Build event pattern based on optional filters
  event_pattern = {
    source       = ["aws.health"]
    detail-type  = ["AWS Health Event"]
    detail = merge(
      length(var.health_event_categories) > 0 ? { eventTypeCategory = var.health_event_categories } : {},
      length(var.health_event_status_codes) > 0 ? { statusCode = var.health_event_status_codes } : {}
    )
  }
}

# SNS Topic for AWS Health Notifications
# This topic serves as the central hub for distributing health notifications
resource "aws_sns_topic" "health_notifications" {
  name         = local.sns_topic_name
  display_name = var.sns_display_name

  # Enable server-side encryption for message security
  kms_master_key_id = "alias/aws/sns"

  # Delivery policy for improved reliability
  delivery_policy = jsonencode({
    "http" : {
      "defaultHealthyRetryPolicy" : {
        "minDelayTarget" : 20,
        "maxDelayTarget" : 20,
        "numRetries" : 3,
        "numMaxDelayRetries" : 0,
        "numMinDelayRetries" : 0,
        "numNoDelayRetries" : 0,
        "backoffFunction" : "linear"
      },
      "disableSubscriptionOverrides" : false
    }
  })

  tags = {
    Name        = local.sns_topic_name
    Description = "SNS topic for AWS Health event notifications"
  }
}

# SNS Topic Policy to allow EventBridge to publish messages
# This policy enables EventBridge service to send health events to the SNS topic
resource "aws_sns_topic_policy" "health_notifications_policy" {
  arn = aws_sns_topic.health_notifications.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Id      = "HealthNotificationTopicPolicy"
    Statement = [
      {
        Sid    = "AllowEventBridgePublish"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action   = "sns:Publish"
        Resource = aws_sns_topic.health_notifications.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

# Email subscriptions to the SNS topic
# Creates email subscriptions for all specified email addresses
resource "aws_sns_topic_subscription" "email_notifications" {
  count     = length(local.all_email_addresses)
  topic_arn = aws_sns_topic.health_notifications.arn
  protocol  = "email"
  endpoint  = local.all_email_addresses[count.index]

  # Prevent Terraform from waiting for subscription confirmation
  # Users must manually confirm email subscriptions
  confirmation_timeout_in_minutes = 1

  depends_on = [aws_sns_topic_policy.health_notifications_policy]
}

# IAM Role for EventBridge to publish to SNS
# This role allows EventBridge service to assume permissions for SNS publishing
resource "aws_iam_role" "eventbridge_sns_role" {
  name = local.iam_role_name
  path = "/service-role/"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = local.iam_role_name
    Description = "Service role for EventBridge to publish health notifications to SNS"
  }
}

# IAM Policy for SNS publishing permissions
# Grants the EventBridge role permission to publish messages to the health notification topic
resource "aws_iam_role_policy" "eventbridge_sns_policy" {
  name = "SNSPublishPolicy"
  role = aws_iam_role.eventbridge_sns_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.health_notifications.arn
      }
    ]
  })
}

# EventBridge Rule for AWS Health Events
# This rule captures AWS Health events and triggers notifications
resource "aws_cloudwatch_event_rule" "health_events" {
  name        = local.eventbridge_rule_name
  description = var.eventbridge_rule_description
  
  # Enable or disable the rule based on variable
  is_enabled = var.enable_eventbridge_rule

  # Event pattern to match AWS Health events
  # Filters events based on source and detail-type, with optional category/status filters
  event_pattern = jsonencode(local.event_pattern)

  tags = {
    Name        = local.eventbridge_rule_name
    Description = "EventBridge rule for monitoring AWS Health events"
  }
}

# EventBridge Target: SNS Topic
# Configures the SNS topic as a target for the health events rule
resource "aws_cloudwatch_event_target" "sns_target" {
  rule      = aws_cloudwatch_event_rule.health_events.name
  target_id = "HealthNotificationSNSTarget"
  arn       = aws_sns_topic.health_notifications.arn

  # Use the IAM role for permissions to publish to SNS
  role_arn = aws_iam_role.eventbridge_sns_role.arn

  # Input transformer to format the message sent to SNS
  # This creates a user-friendly message format for health events
  input_transformer {
    input_paths = {
      account     = "$.account"
      region      = "$.region"
      time        = "$.time"
      source      = "$.source"
      detail-type = "$.detail-type"
      service     = "$.detail.service"
      event-type  = "$.detail.eventTypeCategory"
      status      = "$.detail.statusCode"
      start-time  = "$.detail.startTime"
      end-time    = "$.detail.endTime"
      description = "$.detail.eventDescription[0].latestDescription"
    }

    input_template = jsonencode({
      "AWS Health Event Alert"
      ""
      "Event Details:"
      "- Service: <service>"
      "- Event Type: <event-type>"
      "- Status: <status>"
      "- Region: <region>"
      "- Account: <account>"
      ""
      "Timing:"
      "- Event Time: <time>"
      "- Start Time: <start-time>"
      "- End Time: <end-time>"
      ""
      "Description:"
      "<description>"
      ""
      "Please check the AWS Personal Health Dashboard for more details and recommended actions."
    })
  }

  depends_on = [
    aws_sns_topic_policy.health_notifications_policy,
    aws_iam_role_policy.eventbridge_sns_policy
  ]
}