# Mobile Push Notifications with Pinpoint Infrastructure
# This Terraform configuration creates a comprehensive mobile engagement platform
# using AWS End User Messaging Push (formerly Amazon Pinpoint) for targeted
# push notifications across iOS and Android platforms.

# Data sources for current AWS account and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  resource_suffix = random_id.suffix.hex
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
    Recipe      = "mobile-push-notifications-pinpoint"
  }
}

# ===================================
# IAM Role for Pinpoint Service
# ===================================

# IAM role for Pinpoint to access other AWS services
resource "aws_iam_role" "pinpoint_service_role" {
  name = "PinpointServiceRole-${local.resource_suffix}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "pinpoint.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "PinpointServiceRole-${local.resource_suffix}"
  })
}

# Attach the AWS managed policy for Pinpoint service role
resource "aws_iam_role_policy_attachment" "pinpoint_service_role_policy" {
  role       = aws_iam_role.pinpoint_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonPinpointServiceRole"
}

# Additional policy for Kinesis event streaming (if enabled)
resource "aws_iam_role_policy" "pinpoint_kinesis_policy" {
  count = var.enable_event_streaming ? 1 : 0
  name  = "PinpointKinesisPolicy-${local.resource_suffix}"
  role  = aws_iam_role.pinpoint_service_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kinesis:PutRecord",
          "kinesis:PutRecords"
        ]
        Resource = var.enable_event_streaming ? aws_kinesis_stream.pinpoint_events[0].arn : ""
      }
    ]
  })
}

# ===================================
# Pinpoint Application
# ===================================

# Main Pinpoint application for mobile engagement
resource "aws_pinpoint_app" "mobile_app" {
  name = "${var.application_name}-${local.resource_suffix}"

  # Campaign hook configuration for advanced event handling
  campaign_hook {
    lambda_function_name = ""  # Can be configured later for custom logic
    mode                 = "DELIVERY"
  }

  # Limits to prevent abuse and control costs
  limits {
    daily               = 1000    # Daily message limit
    maximum_duration    = 600     # Maximum campaign duration in seconds
    messages_per_second = 50      # Rate limiting
    total               = 10000   # Total messages per campaign
  }

  # Enable quiet time by default
  quiet_time {
    start = var.quiet_time_start
    end   = var.quiet_time_end
  }

  tags = merge(local.common_tags, {
    Name = "${var.application_name}-${local.resource_suffix}"
  })
}

# ===================================
# Push Notification Channels
# ===================================

# Apple Push Notification Service (APNs) channel for iOS
resource "aws_pinpoint_apns_channel" "ios_channel" {
  count          = var.enable_apns ? 1 : 0
  application_id = aws_pinpoint_app.mobile_app.application_id

  # Certificate-based authentication (recommended for production)
  certificate = var.apns_certificate_file != "" ? file(var.apns_certificate_file) : ""
  private_key = var.apns_private_key_file != "" ? file(var.apns_private_key_file) : ""

  # Bundle ID for iOS application
  bundle_id = var.apns_bundle_id

  # Use sandbox environment for development, production for live apps
  default_authentication_method = "CERTIFICATE"
  enabled                       = true

  depends_on = [aws_pinpoint_app.mobile_app]
}

# Firebase Cloud Messaging (FCM) channel for Android
resource "aws_pinpoint_gcm_channel" "android_channel" {
  count          = var.enable_fcm ? 1 : 0
  application_id = aws_pinpoint_app.mobile_app.application_id

  # FCM server key for authentication
  api_key = var.fcm_server_key
  enabled = true

  depends_on = [aws_pinpoint_app.mobile_app]
}

# ===================================
# Push Notification Template
# ===================================

# Reusable push notification template for consistent messaging
resource "aws_pinpoint_push_template" "notification_template" {
  count         = var.create_push_template ? 1 : 0
  template_name = var.template_name

  # Android/Amazon Device Messaging configuration
  adm {
    action = "OPEN_APP"
    body   = var.notification_body
    title  = var.notification_title
    sound  = "default"
  }

  # Apple Push Notification Service configuration
  apns {
    action = "OPEN_APP"
    body   = var.notification_body
    title  = var.notification_title
    sound  = "default"
  }

  # Google Cloud Messaging/Firebase configuration
  gcm {
    action = "OPEN_APP"
    body   = var.notification_body
    title  = var.notification_title
    sound  = "default"
  }

  # Default fallback configuration
  default {
    action = "OPEN_APP"
    body   = var.notification_body
    title  = var.notification_title
  }

  tags = merge(local.common_tags, {
    Name = var.template_name
  })
}

# ===================================
# Test User Endpoints
# ===================================

# Test iOS endpoint for validation
resource "aws_pinpoint_endpoint" "ios_test_endpoint" {
  count          = var.create_test_endpoints ? 1 : 0
  application_id = aws_pinpoint_app.mobile_app.application_id
  endpoint_id    = "ios-user-001"

  # iOS-specific configuration
  channel_type = "APNS"
  address      = var.test_ios_device_token

  # Device and app attributes
  attributes = {
    PlatformType = ["iOS"]
    AppVersion   = ["1.0.0"]
  }

  # Demographic information
  demographic {
    platform         = "iOS"
    platform_version = "15.0"
  }

  # Location data for geo-targeting
  location {
    country = "US"
    city    = "Seattle"
  }

  # User attributes for segmentation
  user {
    user_id = "user-001"
    user_attributes = {
      PurchaseHistory = ["high-value"]
      Category        = ["electronics"]
    }
  }

  depends_on = [aws_pinpoint_app.mobile_app]
}

# Test Android endpoint for validation
resource "aws_pinpoint_endpoint" "android_test_endpoint" {
  count          = var.create_test_endpoints ? 1 : 0
  application_id = aws_pinpoint_app.mobile_app.application_id
  endpoint_id    = "android-user-002"

  # Android-specific configuration
  channel_type = "GCM"
  address      = var.test_android_device_token

  # Device and app attributes
  attributes = {
    PlatformType = ["Android"]
    AppVersion   = ["1.0.0"]
  }

  # Demographic information
  demographic {
    platform         = "Android"
    platform_version = "12.0"
  }

  # Location data for geo-targeting
  location {
    country = "US"
    city    = "San Francisco"
  }

  # User attributes for segmentation
  user {
    user_id = "user-002"
    user_attributes = {
      PurchaseHistory = ["medium-value"]
      Category        = ["clothing"]
    }
  }

  depends_on = [aws_pinpoint_app.mobile_app]
}

# ===================================
# User Segmentation
# ===================================

# Dynamic user segment for targeted campaigns
resource "aws_pinpoint_segment" "high_value_customers" {
  application_id = aws_pinpoint_app.mobile_app.application_id
  name           = var.segment_name

  # Segment criteria based on user attributes
  dimensions {
    # User attribute-based filtering
    user_attributes = {
      (var.segment_criteria_attribute) = {
        attribute_type = "INCLUSIVE"
        values         = var.segment_criteria_values
      }
    }

    # Platform-based filtering (include both iOS and Android)
    demographic {
      platform {
        dimension_type = "INCLUSIVE"
        values         = ["iOS", "Android"]
      }
    }
  }

  tags = merge(local.common_tags, {
    Name = var.segment_name
  })

  depends_on = [aws_pinpoint_app.mobile_app]
}

# ===================================
# Event Streaming for Analytics
# ===================================

# Kinesis stream for real-time event processing
resource "aws_kinesis_stream" "pinpoint_events" {
  count           = var.enable_event_streaming ? 1 : 0
  name            = "pinpoint-events-${local.resource_suffix}"
  shard_count     = var.kinesis_shard_count
  retention_period = 24  # 24 hours retention

  # Enable encryption at rest
  encryption_type = "KMS"
  kms_key_id      = "alias/aws/kinesis"

  # Enable enhanced fan-out for real-time processing
  shard_level_metrics = [
    "IncomingRecords",
    "OutgoingRecords",
  ]

  tags = merge(local.common_tags, {
    Name = "pinpoint-events-${local.resource_suffix}"
  })
}

# Configure event streaming from Pinpoint to Kinesis
resource "aws_pinpoint_event_stream" "events" {
  count                    = var.enable_event_streaming ? 1 : 0
  application_id           = aws_pinpoint_app.mobile_app.application_id
  destination_stream_arn   = aws_kinesis_stream.pinpoint_events[0].arn
  role_arn                = aws_iam_role.pinpoint_service_role.arn

  depends_on = [
    aws_kinesis_stream.pinpoint_events,
    aws_iam_role_policy.pinpoint_kinesis_policy
  ]
}

# ===================================
# CloudWatch Monitoring
# ===================================

# SNS topic for alarm notifications (optional)
resource "aws_sns_topic" "alarm_notifications" {
  count = var.enable_cloudwatch_alarms && var.alarm_notification_email != "" ? 1 : 0
  name  = "pinpoint-alarms-${local.resource_suffix}"

  tags = merge(local.common_tags, {
    Name = "pinpoint-alarms-${local.resource_suffix}"
  })
}

# SNS topic subscription for email notifications
resource "aws_sns_topic_subscription" "alarm_email" {
  count     = var.enable_cloudwatch_alarms && var.alarm_notification_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.alarm_notifications[0].arn
  protocol  = "email"
  endpoint  = var.alarm_notification_email
}

# CloudWatch alarm for push notification failures
resource "aws_cloudwatch_metric_alarm" "push_failures" {
  count               = var.enable_cloudwatch_alarms ? 1 : 0
  alarm_name          = "PinpointPushFailures-${local.resource_suffix}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "DirectSendMessagePermanentFailure"
  namespace           = "AWS/Pinpoint"
  period              = "300"
  statistic           = "Sum"
  threshold           = var.failure_threshold
  alarm_description   = "Alert when push notification failures exceed threshold"
  alarm_actions       = var.alarm_notification_email != "" ? [aws_sns_topic.alarm_notifications[0].arn] : []

  dimensions = {
    ApplicationId = aws_pinpoint_app.mobile_app.application_id
  }

  tags = merge(local.common_tags, {
    Name = "PinpointPushFailures-${local.resource_suffix}"
  })
}

# CloudWatch alarm for delivery rate monitoring
resource "aws_cloudwatch_metric_alarm" "delivery_rate" {
  count               = var.enable_cloudwatch_alarms ? 1 : 0
  alarm_name          = "PinpointDeliveryRate-${local.resource_suffix}"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "DirectSendMessageDeliveryRate"
  namespace           = "AWS/Pinpoint"
  period              = "300"
  statistic           = "Average"
  threshold           = var.delivery_rate_threshold
  alarm_description   = "Alert when delivery rate falls below acceptable threshold"
  alarm_actions       = var.alarm_notification_email != "" ? [aws_sns_topic.alarm_notifications[0].arn] : []

  dimensions = {
    ApplicationId = aws_pinpoint_app.mobile_app.application_id
  }

  tags = merge(local.common_tags, {
    Name = "PinpointDeliveryRate-${local.resource_suffix}"
  })
}

# CloudWatch Log Group for Pinpoint application logs
resource "aws_cloudwatch_log_group" "pinpoint_logs" {
  name              = "/aws/pinpoint/${aws_pinpoint_app.mobile_app.application_id}"
  retention_in_days = 14

  tags = merge(local.common_tags, {
    Name = "pinpoint-logs-${local.resource_suffix}"
  })
}

# ===================================
# Sample Campaign (Optional)
# ===================================

# Sample push notification campaign for demonstration
resource "aws_pinpoint_campaign" "flash_sale" {
  count          = var.create_test_endpoints ? 1 : 0
  application_id = aws_pinpoint_app.mobile_app.application_id
  name           = var.campaign_name
  description    = var.campaign_description

  # Message configuration for different platforms
  message_configuration {
    # Apple Push Notification configuration
    apns_message {
      action = "OPEN_APP"
      body   = var.notification_body
      title  = var.notification_title
      sound  = "default"
    }

    # Google Cloud Messaging configuration
    gcm_message {
      action = "OPEN_APP"
      body   = var.notification_body
      title  = var.notification_title
      sound  = "default"
    }

    # Default message configuration
    default_message {
      body = var.notification_body
    }
  }

  # Campaign schedule with quiet time respect
  schedule {
    is_local_time = true
    quiet_time {
      start = var.quiet_time_start
      end   = var.quiet_time_end
    }
    start_time = "IMMEDIATE"
    timezone   = var.campaign_timezone
  }

  # Target the high-value customer segment
  segment_id      = aws_pinpoint_segment.high_value_customers.segment_id
  segment_version = 1

  tags = merge(local.common_tags, {
    Name = var.campaign_name
  })

  depends_on = [
    aws_pinpoint_segment.high_value_customers,
    aws_pinpoint_endpoint.ios_test_endpoint,
    aws_pinpoint_endpoint.android_test_endpoint
  ]
}