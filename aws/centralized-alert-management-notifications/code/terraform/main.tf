# =============================================================================
# Centralized Alert Management with User Notifications and CloudWatch
# =============================================================================
# This Terraform configuration deploys a complete centralized alert management
# system using AWS User Notifications, CloudWatch alarms, and S3 monitoring.
# The solution consolidates alerts from multiple AWS services into a unified
# notification hub with configurable delivery channels.
# =============================================================================

# Data sources for current AWS context
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Resource naming with consistent prefix and random suffix
  name_prefix = var.name_prefix
  bucket_name = "${local.name_prefix}-monitoring-demo-${random_id.suffix.hex}"
  
  # Common tags applied to all resources
  common_tags = merge(var.common_tags, {
    Project     = "Centralized Alert Management"
    Environment = var.environment
    ManagedBy   = "Terraform"
    Region      = data.aws_region.current.name
  })
}

# =============================================================================
# S3 BUCKET AND MONITORING CONFIGURATION
# =============================================================================

# Primary S3 bucket for monitoring demonstration
resource "aws_s3_bucket" "monitoring_bucket" {
  bucket = local.bucket_name

  tags = merge(local.common_tags, {
    Name        = local.bucket_name
    Purpose     = "Monitoring and alerting demonstration"
    MonitoringEnabled = "true"
  })
}

# Enable versioning for better object tracking and recovery
resource "aws_s3_bucket_versioning" "monitoring_bucket_versioning" {
  bucket = aws_s3_bucket.monitoring_bucket.id
  
  versioning_configuration {
    status = "Enabled"
  }
}

# Configure server-side encryption for data security
resource "aws_s3_bucket_server_side_encryption_configuration" "monitoring_bucket_encryption" {
  bucket = aws_s3_bucket.monitoring_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# Block public access for security compliance
resource "aws_s3_bucket_public_access_block" "monitoring_bucket_pab" {
  bucket = aws_s3_bucket.monitoring_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Enable CloudWatch metrics for the entire bucket
# This provides daily storage metrics at no additional cost
resource "aws_s3_bucket_metric" "entire_bucket_metrics" {
  bucket = aws_s3_bucket.monitoring_bucket.id
  name   = "EntireBucketMetrics"

  # Monitor the entire bucket without filtering
  # For production, consider filtering by prefix or tags to reduce costs
}

# Optional: Enable request metrics for detailed access patterns
# Note: This incurs additional CloudWatch charges
resource "aws_s3_bucket_metric" "request_metrics" {
  count  = var.enable_request_metrics ? 1 : 0
  bucket = aws_s3_bucket.monitoring_bucket.id
  name   = "BucketRequestMetrics"

  filter {
    # Monitor all objects - adjust prefix for specific monitoring
    prefix = var.request_metrics_prefix
  }
}

# =============================================================================
# CLOUDWATCH ALARMS FOR S3 MONITORING
# =============================================================================

# Primary alarm: Monitor S3 bucket size growth
# Triggers when bucket exceeds the configured threshold
resource "aws_cloudwatch_metric_alarm" "s3_bucket_size_alarm" {
  alarm_name          = "${local.name_prefix}-s3-bucket-size-alarm-${random_id.suffix.hex}"
  alarm_description   = "Monitor S3 bucket size growth for ${aws_s3_bucket.monitoring_bucket.id}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.bucket_size_alarm_evaluation_periods
  metric_name         = "BucketSizeBytes"
  namespace           = "AWS/S3"
  period              = 86400  # Daily evaluation (S3 storage metrics are daily)
  statistic           = "Average"
  threshold           = var.bucket_size_threshold_bytes
  treat_missing_data  = "notBreaching"
  
  # S3 bucket size dimensions
  dimensions = {
    BucketName  = aws_s3_bucket.monitoring_bucket.id
    StorageType = "StandardStorage"
  }

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-s3-bucket-size-alarm"
    Purpose     = "Monitor S3 storage growth"
    AlarmType   = "Storage"
  })
}

# Secondary alarm: Monitor object count growth
# Helps identify rapid object creation patterns
resource "aws_cloudwatch_metric_alarm" "s3_object_count_alarm" {
  alarm_name          = "${local.name_prefix}-s3-object-count-alarm-${random_id.suffix.hex}"
  alarm_description   = "Monitor S3 object count for ${aws_s3_bucket.monitoring_bucket.id}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.object_count_alarm_evaluation_periods
  metric_name         = "NumberOfObjects"
  namespace           = "AWS/S3"
  period              = 86400  # Daily evaluation
  statistic           = "Average"
  threshold           = var.object_count_threshold
  treat_missing_data  = "notBreaching"
  
  # S3 object count dimensions
  dimensions = {
    BucketName  = aws_s3_bucket.monitoring_bucket.id
    StorageType = "AllStorageTypes"
  }

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-s3-object-count-alarm"
    Purpose     = "Monitor S3 object proliferation"
    AlarmType   = "ObjectCount"
  })
}

# =============================================================================
# USER NOTIFICATIONS INFRASTRUCTURE
# =============================================================================

# Register notification hub for centralized alert management
# This creates the regional hub for processing all notifications
resource "aws_notifications_notification_hub" "central_hub" {
  notification_hub_region = data.aws_region.current.name

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-notification-hub"
    Purpose = "Centralized notification processing"
  })
}

# Email contact for alert delivery
# This contact will receive all notifications from the configured alarms
resource "aws_notificationscontacts_email_contact" "monitoring_contact" {
  name          = "${local.name_prefix}-monitoring-contact-${random_id.suffix.hex}"
  email_address = var.notification_email

  tags = merge(local.common_tags, {
    Name     = "${local.name_prefix}-monitoring-email"
    Purpose  = "Primary monitoring contact"
    Team     = var.contact_team
  })
}

# Primary notification configuration
# Aggregates alerts over 5-minute windows to prevent notification flooding
resource "aws_notifications_notification_configuration" "s3_monitoring_config" {
  name                 = "${local.name_prefix}-s3-monitoring-config-${random_id.suffix.hex}"
  description          = "Centralized S3 monitoring notification configuration"
  aggregation_duration = var.notification_aggregation_duration

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-s3-monitoring-config"
    Purpose     = "S3 monitoring notifications"
    ServiceType = "Monitoring"
  })

  depends_on = [aws_notifications_notification_hub.central_hub]
}

# Associate email contact with notification configuration
# This connects the email delivery channel to the notification processing
resource "aws_notifications_channel_association" "email_association" {
  arn                            = aws_notificationscontacts_email_contact.monitoring_contact.arn
  notification_configuration_arn = aws_notifications_notification_configuration.s3_monitoring_config.arn

  depends_on = [
    aws_notificationscontacts_email_contact.monitoring_contact,
    aws_notifications_notification_configuration.s3_monitoring_config
  ]
}

# Event rule for CloudWatch alarm state changes
# Filters and routes CloudWatch alarm events to User Notifications
resource "aws_notifications_event_rule" "cloudwatch_alarm_rule" {
  name        = "${local.name_prefix}-cloudwatch-alarm-rule-${random_id.suffix.hex}"
  description = "Route CloudWatch alarm state changes for S3 monitoring"
  
  # EventBridge pattern to match CloudWatch alarm state changes
  event_pattern = jsonencode({
    source      = ["aws.cloudwatch"]
    detail-type = ["CloudWatch Alarm State Change"]
    detail = {
      alarmName = [
        aws_cloudwatch_metric_alarm.s3_bucket_size_alarm.alarm_name,
        aws_cloudwatch_metric_alarm.s3_object_count_alarm.alarm_name
      ]
      state = {
        value = ["ALARM", "OK"]
      }
    }
  })
  
  event_type                     = "CloudWatch Alarm State Change"
  notification_configuration_arn = aws_notifications_notification_configuration.s3_monitoring_config.arn
  regions                        = [data.aws_region.current.name]
  source                         = "aws.cloudwatch"

  depends_on = [aws_notifications_notification_configuration.s3_monitoring_config]
}

# =============================================================================
# SAMPLE DATA FOR TESTING (OPTIONAL)
# =============================================================================

# Create sample objects in S3 bucket for metric generation
# These objects help establish baseline metrics for alarm testing
resource "aws_s3_object" "sample_data" {
  count = var.create_sample_data ? 3 : 0
  
  bucket = aws_s3_bucket.monitoring_bucket.id
  key    = "sample-data/sample-file-${count.index + 1}.txt"
  
  content = jsonencode({
    timestamp     = formatdate("RFC3339", timestamp())
    file_number   = count.index + 1
    purpose       = "CloudWatch metrics generation"
    environment   = var.environment
    generated_by  = "terraform"
  })
  
  content_type = "application/json"

  tags = merge(local.common_tags, {
    Name    = "sample-file-${count.index + 1}"
    Purpose = "Metrics generation"
    Type    = "TestData"
  })
}

# Create a larger sample file to trigger size-based alarms if threshold is low
resource "aws_s3_object" "large_sample_data" {
  count = var.create_sample_data ? 1 : 0
  
  bucket = aws_s3_bucket.monitoring_bucket.id
  key    = "archive/large-sample-file.json"
  
  # Generate larger content for size monitoring
  content = jsonencode({
    timestamp    = formatdate("RFC3339", timestamp())
    purpose      = "Large file for size monitoring demonstration"
    environment  = var.environment
    generated_by = "terraform"
    data = [for i in range(100) : {
      record_id = i
      data      = "Sample data content for monitoring and alerting demonstration purposes"
      metadata  = {
        created_at = formatdate("RFC3339", timestamp())
        size_test  = true
      }
    }]
  })
  
  content_type = "application/json"

  tags = merge(local.common_tags, {
    Name    = "large-sample-file"
    Purpose = "Size threshold testing"
    Type    = "TestData"
    Size    = "Large"
  })
}