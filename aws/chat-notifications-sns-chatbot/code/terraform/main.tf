# Chat Notifications with SNS and Chatbot Infrastructure
# This Terraform configuration creates a complete notification system that integrates
# Amazon SNS with AWS Chatbot to deliver real-time alerts to Slack or Microsoft Teams.
# The infrastructure follows AWS Well-Architected Framework principles for security,
# reliability, and operational excellence.

# ============================================================================
# DATA SOURCES AND LOCAL VALUES
# ============================================================================

# Data sources for current AWS account and region information
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Random suffix generator for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for consistent naming and tagging across all resources
locals {
  # Naming convention components
  name_prefix = "${var.project_name}-${var.environment}"
  name_suffix = random_id.suffix.hex
  
  # Common tags applied to all resources for cost tracking and management
  common_tags = merge(var.tags, {
    Project     = "Chat Notifications with SNS and Chatbot"
    Environment = var.environment
    CreatedBy   = "Terraform"
    Repository  = "recipes/aws/chat-notifications-sns-chatbot"
    LastUpdated = timestamp()
  })
  
  # Configuration flags for conditional resource creation
  chatbot_slack_enabled = var.slack_channel_id != "" && var.slack_team_id != ""
  chatbot_teams_enabled = var.teams_channel_id != "" && var.teams_tenant_id != "" && var.teams_team_id != ""
}

# ============================================================================
# SNS TOPIC CONFIGURATION
# ============================================================================

# Main SNS topic for team notifications
# This serves as the central messaging hub for all alerts and notifications
# The topic is configured with encryption and proper access policies
resource "aws_sns_topic" "team_notifications" {
  name         = "${local.name_prefix}-${local.name_suffix}"
  display_name = var.sns_topic_display_name

  # Enable server-side encryption using AWS managed KMS key for data protection
  kms_master_key_id = var.enable_sns_encryption ? "alias/aws/sns" : null

  # Optional delivery policy for retry behavior and throttling configuration
  delivery_policy = var.sns_delivery_policy

  # Enable message tracing for debugging and monitoring (optional)
  tracing_config = var.enable_detailed_monitoring ? "Active" : "PassThrough"

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-${local.name_suffix}"
    Description = "SNS topic for team chat notifications"
    Service     = "SNS"
  })
}

# SNS topic policy to allow CloudWatch and other AWS services to publish messages
# This policy follows the principle of least privilege while enabling necessary access
resource "aws_sns_topic_policy" "team_notifications_policy" {
  arn = aws_sns_topic.team_notifications.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Id      = "${local.name_prefix}-notifications-policy-${local.name_suffix}"
    Statement = [
      {
        Sid    = "AllowCloudWatchAlarmsToPublish"
        Effect = "Allow"
        Principal = {
          Service = "cloudwatch.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.team_notifications.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      },
      {
        Sid    = "AllowEventBridgeToPublish"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.team_notifications.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      },
      {
        Sid    = "AllowLambdaToPublish"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.team_notifications.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

# Additional SNS subscriptions for multiple notification channels
# Supports email, SMS, HTTP endpoints, Lambda functions, and SQS queues
resource "aws_sns_topic_subscription" "additional_subscriptions" {
  for_each = var.additional_sns_subscriptions

  topic_arn = aws_sns_topic.team_notifications.arn
  protocol  = each.value.protocol
  endpoint  = each.value.endpoint

  # Configure message filtering if specified
  filter_policy = each.value.filter_policy

  # Configure delivery policy for email confirmations and retry behavior
  confirmation_timeout_in_minutes = each.value.protocol == "email" ? 5 : null
  
  # Enable raw message delivery for HTTP/HTTPS endpoints
  raw_message_delivery = contains(["http", "https", "lambda", "sqs"], each.value.protocol) ? true : false
}

# ============================================================================
# IAM ROLE AND POLICIES FOR AWS CHATBOT
# ============================================================================

# IAM role for AWS Chatbot to access SNS and other AWS services
# This role defines the permissions Chatbot has when executing commands in chat
resource "aws_iam_role" "chatbot_role" {
  name = "${local.name_prefix}-chatbot-role-${local.name_suffix}"
  path = "/service-roles/"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "chatbot.amazonaws.com"
        }
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })

  # Limit session duration for security
  max_session_duration = 3600

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-chatbot-role-${local.name_suffix}"
    Description = "IAM role for AWS Chatbot service"
    Service     = "IAM"
  })
}

# Attach ReadOnlyAccess policy for secure chat operations
# This managed policy allows Chatbot to read AWS resources but not modify them
resource "aws_iam_role_policy_attachment" "chatbot_readonly" {
  role       = aws_iam_role.chatbot_role.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# Custom policy for enhanced CloudWatch and SNS operations
# This policy enables Chatbot to provide detailed information about alarms and topics
resource "aws_iam_role_policy" "chatbot_enhanced_policy" {
  name = "${local.name_prefix}-chatbot-enhanced-policy-${local.name_suffix}"
  role = aws_iam_role.chatbot_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CloudWatchEnhancedPermissions"
        Effect = "Allow"
        Action = [
          "cloudwatch:DescribeAlarms",
          "cloudwatch:DescribeAlarmsForMetric",
          "cloudwatch:DescribeAlarmHistory",
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:GetMetricData",
          "cloudwatch:ListMetrics",
          "cloudwatch:GetDashboard",
          "cloudwatch:ListDashboards"
        ]
        Resource = "*"
      },
      {
        Sid    = "SNSEnhancedPermissions"
        Effect = "Allow"
        Action = [
          "sns:ListTopics",
          "sns:ListSubscriptionsByTopic",
          "sns:GetTopicAttributes",
          "sns:GetSubscriptionAttributes"
        ]
        Resource = "*"
      },
      {
        Sid    = "LogsPermissions"
        Effect = "Allow"
        Action = [
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams",
          "logs:GetLogEvents",
          "logs:FilterLogEvents"
        ]
        Resource = "*"
      },
      {
        Sid    = "EC2BasicPermissions"
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceStatus",
          "ec2:DescribeImages",
          "ec2:DescribeSnapshots",
          "ec2:DescribeVolumes"
        ]
        Resource = "*"
      }
    ]
  })
}

# Attach custom guardrail policies specified in variables
resource "aws_iam_role_policy_attachment" "chatbot_custom_guardrails" {
  for_each = toset(var.chatbot_custom_guardrail_policies)
  
  role       = aws_iam_role.chatbot_role.name
  policy_arn = each.value
}

# ============================================================================
# AWS CHATBOT SLACK CONFIGURATION
# ============================================================================

# AWS Chatbot Slack channel configuration
# This resource creates the integration between SNS and Slack channels
# Note: Slack workspace must be pre-authorized in AWS Chatbot console
resource "aws_chatbot_slack_channel_configuration" "team_alerts" {
  count = local.chatbot_slack_enabled ? 1 : 0

  configuration_name = "${local.name_prefix}-slack-alerts-${local.name_suffix}"
  iam_role_arn       = aws_iam_role.chatbot_role.arn
  slack_channel_id   = var.slack_channel_id
  slack_team_id      = var.slack_team_id

  # Subscribe to our SNS topic for notifications
  sns_topic_arns = [aws_sns_topic.team_notifications.arn]

  # Configure logging and security settings
  logging_level               = var.chatbot_logging_level
  user_authorization_required = var.chatbot_user_authorization_required

  # Apply guardrail policies to prevent unauthorized actions
  guardrail_policy_arns = concat([
    "arn:aws:iam::aws:policy/ReadOnlyAccess"
  ], var.chatbot_custom_guardrail_policies)

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-slack-alerts-${local.name_suffix}"
    Description = "AWS Chatbot configuration for Slack notifications"
    Service     = "Chatbot"
    ChatPlatform = "Slack"
  })
}

# ============================================================================
# AWS CHATBOT TEAMS CONFIGURATION
# ============================================================================

# AWS Chatbot Microsoft Teams channel configuration
# This resource creates the integration between SNS and Microsoft Teams channels
# Note: Teams workspace must be pre-authorized in AWS Chatbot console
resource "aws_chatbot_teams_channel_configuration" "team_alerts_teams" {
  count = local.chatbot_teams_enabled ? 1 : 0

  configuration_name = "${local.name_prefix}-teams-alerts-${local.name_suffix}"
  iam_role_arn       = aws_iam_role.chatbot_role.arn
  channel_id         = var.teams_channel_id
  tenant_id          = var.teams_tenant_id
  team_id            = var.teams_team_id

  # Subscribe to our SNS topic for notifications
  sns_topic_arns = [aws_sns_topic.team_notifications.arn]

  # Configure logging and security settings
  logging_level               = var.chatbot_logging_level
  user_authorization_required = var.chatbot_user_authorization_required

  # Apply guardrail policies to prevent unauthorized actions
  guardrail_policy_arns = concat([
    "arn:aws:iam::aws:policy/ReadOnlyAccess"
  ], var.chatbot_custom_guardrail_policies)

  tags = merge(local.common_tags, {
    Name         = "${local.name_prefix}-teams-alerts-${local.name_suffix}"
    Description  = "AWS Chatbot configuration for Microsoft Teams notifications"
    Service      = "Chatbot"
    ChatPlatform = "Teams"
  })
}

# ============================================================================
# CLOUDWATCH ALARMS FOR TESTING AND MONITORING
# ============================================================================

# Demo CloudWatch alarm for testing the notification pipeline
# This alarm triggers when EC2 CPU utilization is below the specified threshold
resource "aws_cloudwatch_metric_alarm" "demo_cpu_alarm" {
  count = var.cloudwatch_alarm_enabled ? 1 : 0

  alarm_name          = "${local.name_prefix}-demo-cpu-alarm-${local.name_suffix}"
  alarm_description   = "Demo CPU alarm for testing chat notifications - triggers when CPU < ${var.cloudwatch_alarm_threshold}%"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = var.cloudwatch_alarm_evaluation_periods
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = var.cloudwatch_alarm_period
  statistic           = "Average"
  threshold           = var.cloudwatch_alarm_threshold

  # Configure datapoints to alarm for more precise triggering
  datapoints_to_alarm = var.cloudwatch_alarm_datapoints_to_alarm

  # Configure alarm actions to send notifications to SNS
  alarm_actions = [aws_sns_topic.team_notifications.arn]
  ok_actions    = [aws_sns_topic.team_notifications.arn]

  # Treat missing data as not breaching (useful for testing environments)
  treat_missing_data = "notBreaching"

  # Enable detailed monitoring if requested
  actions_enabled = true

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-demo-cpu-alarm-${local.name_suffix}"
    Description = "Demo CloudWatch alarm for testing notifications"
    Purpose     = "Testing"
    Service     = "CloudWatch"
  })
}

# High memory utilization alarm for production monitoring
# This demonstrates monitoring of custom CloudWatch metrics
resource "aws_cloudwatch_metric_alarm" "high_memory_alarm" {
  count = var.cloudwatch_alarm_enabled ? 1 : 0

  alarm_name          = "${local.name_prefix}-high-memory-alarm-${local.name_suffix}"
  alarm_description   = "Alarm when memory utilization exceeds 85% for ${var.cloudwatch_alarm_evaluation_periods} consecutive periods"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.cloudwatch_alarm_evaluation_periods
  metric_name         = "MemoryUtilization"
  namespace           = "CWAgent"
  period              = var.cloudwatch_alarm_period
  statistic           = "Average"
  threshold           = 85

  # Require all datapoints to be breaching for more reliable alerting
  datapoints_to_alarm = var.cloudwatch_alarm_evaluation_periods

  alarm_actions = [aws_sns_topic.team_notifications.arn]
  ok_actions    = [aws_sns_topic.team_notifications.arn]

  # Treat missing data as missing (don't assume breach)
  treat_missing_data = "missing"

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-high-memory-alarm-${local.name_suffix}"
    Description = "High memory utilization alarm"
    Severity    = "Warning"
    Service     = "CloudWatch"
  })
}

# Application error rate alarm using metric math expressions
# This demonstrates advanced alarm configuration with multiple metrics
resource "aws_cloudwatch_metric_alarm" "application_error_rate" {
  count = var.cloudwatch_alarm_enabled ? 1 : 0

  alarm_name          = "${local.name_prefix}-app-error-rate-${local.name_suffix}"
  alarm_description   = "Alarm when application error rate exceeds 5% for consecutive periods"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  threshold           = 5
  treat_missing_data  = "notBreaching"

  # Use metric math to calculate error rate percentage
  metric_query {
    id          = "error_rate"
    expression  = "errors/requests*100"
    label       = "Application Error Rate (%)"
    return_data = true
  }

  metric_query {
    id = "errors"
    metric {
      metric_name = "HTTPCode_Target_5XX_Count"
      namespace   = "AWS/ApplicationELB"
      period      = var.cloudwatch_alarm_period
      stat        = "Sum"
      dimensions = {
        LoadBalancer = "app/example-app"
      }
    }
  }

  metric_query {
    id = "requests"
    metric {
      metric_name = "RequestCount"
      namespace   = "AWS/ApplicationELB"
      period      = var.cloudwatch_alarm_period
      stat        = "Sum"
      dimensions = {
        LoadBalancer = "app/example-app"
      }
    }
  }

  alarm_actions = [aws_sns_topic.team_notifications.arn]
  ok_actions    = [aws_sns_topic.team_notifications.arn]

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-app-error-rate-${local.name_suffix}"
    Description = "Application error rate alarm using metric math"
    Severity    = "Critical"
    Service     = "CloudWatch"
  })
}

# ============================================================================
# CROSS-REGION REPLICATION (OPTIONAL)
# ============================================================================

# Cross-region SNS topics for disaster recovery (if enabled)
resource "aws_sns_topic" "backup_notifications" {
  for_each = var.enable_cross_region_replication ? toset(var.backup_regions) : []

  provider = aws.backup_region

  name         = "${local.name_prefix}-backup-${each.key}-${local.name_suffix}"
  display_name = "${var.sns_topic_display_name} (Backup - ${each.key})"

  kms_master_key_id = var.enable_sns_encryption ? "alias/aws/sns" : null

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-backup-${each.key}-${local.name_suffix}"
    Description = "Backup SNS topic for disaster recovery"
    BackupRegion = each.key
    Service     = "SNS"
  })
}

# ============================================================================
# CLOUDWATCH DASHBOARD (OPTIONAL)
# ============================================================================

# CloudWatch dashboard for monitoring notification system health
resource "aws_cloudwatch_dashboard" "notification_dashboard" {
  count = var.enable_detailed_monitoring ? 1 : 0

  dashboard_name = "${local.name_prefix}-notifications-dashboard-${local.name_suffix}"

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
            ["AWS/SNS", "NumberOfMessagesPublished", "TopicName", aws_sns_topic.team_notifications.name],
            ["AWS/SNS", "NumberOfNotificationsFailed", "TopicName", aws_sns_topic.team_notifications.name],
            ["AWS/SNS", "NumberOfNotificationsDelivered", "TopicName", aws_sns_topic.team_notifications.name]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "SNS Topic Metrics"
          period  = 300
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
            ["AWS/CloudWatch", "MetricCount"]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "CloudWatch Metrics"
          period  = 300
        }
      }
    ]
  })
}