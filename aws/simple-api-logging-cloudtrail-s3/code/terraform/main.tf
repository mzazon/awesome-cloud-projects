# Simple API Logging with CloudTrail and S3 - Main Terraform Configuration
# This configuration creates a comprehensive CloudTrail logging solution with:
# - S3 bucket for long-term log storage with security controls
# - CloudWatch Logs for real-time monitoring and alerting
# - IAM roles and policies following least privilege principles
# - CloudWatch alarms for security monitoring (root account usage)
# - SNS topic for alarm notifications

# Data sources for current AWS account and region information
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  # Local values for consistent naming and configuration
  account_id      = data.aws_caller_identity.current.account_id
  region          = data.aws_region.current.name
  partition       = data.aws_partition.current.partition
  random_suffix   = random_id.suffix.hex
  
  # Resource names with unique suffixes
  bucket_name     = "cloudtrail-logs-${local.account_id}-${local.random_suffix}"
  trail_name      = "${var.trail_name}-${local.random_suffix}"
  log_group_name  = "/aws/cloudtrail/${local.trail_name}"
  role_name       = "CloudTrailLogsRole-${local.random_suffix}"
  topic_name      = "cloudtrail-alerts-${local.random_suffix}"
  
  # Trail ARN for use in bucket policy
  trail_arn = "arn:${local.partition}:cloudtrail:${local.region}:${local.account_id}:trail/${local.trail_name}"
  
  # Merged tags combining default and additional tags
  common_tags = merge(
    {
      Name        = "CloudTrail API Logging Infrastructure"
      Purpose     = "Security audit logging and compliance"
      CreatedBy   = "Terraform"
      RandomSuffix = local.random_suffix
    },
    var.additional_tags
  )
}

# S3 Bucket for CloudTrail Logs
# This bucket stores audit logs with security controls and encryption
resource "aws_s3_bucket" "cloudtrail_logs" {
  bucket        = local.bucket_name
  force_destroy = var.s3_bucket_force_destroy

  tags = merge(local.common_tags, {
    Description = "S3 bucket for storing CloudTrail API audit logs"
    Service     = "S3"
  })
}

# Enable S3 bucket versioning for audit trail protection
resource "aws_s3_bucket_versioning" "cloudtrail_logs" {
  count  = var.enable_s3_versioning ? 1 : 0
  bucket = aws_s3_bucket.cloudtrail_logs.id
  
  versioning_configuration {
    status = "Enabled"
  }
}

# Configure server-side encryption for the S3 bucket
resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail_logs" {
  count  = var.enable_s3_encryption ? 1 : 0
  bucket = aws_s3_bucket.cloudtrail_logs.id

  rule {
    apply_server_side_encryption_by_default {
      # Use KMS encryption if key provided, otherwise use AES256
      sse_algorithm     = var.kms_key_id != "" ? "aws:kms" : "AES256"
      kms_master_key_id = var.kms_key_id != "" ? var.kms_key_id : null
    }
    
    bucket_key_enabled = var.kms_key_id != "" ? true : null
  }
}

# Block all public access to the S3 bucket for security
resource "aws_s3_bucket_public_access_block" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket policy for CloudTrail access with source ARN conditions
resource "aws_s3_bucket_policy" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id
  policy = data.aws_iam_policy_document.s3_bucket_policy.json

  # Ensure bucket policy is applied after public access block
  depends_on = [aws_s3_bucket_public_access_block.cloudtrail_logs]
}

# IAM policy document for S3 bucket permissions
data "aws_iam_policy_document" "s3_bucket_policy" {
  # Allow CloudTrail to check bucket ACL
  statement {
    sid    = "AWSCloudTrailAclCheck"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.cloudtrail_logs.arn]
    
    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.trail_arn]
    }
  }

  # Allow CloudTrail to write log files to S3
  statement {
    sid    = "AWSCloudTrailWrite"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.cloudtrail_logs.arn}/${var.s3_key_prefix}/AWSLogs/${local.account_id}/*"]

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
    
    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.trail_arn]
    }
  }
}

# CloudWatch Log Group for real-time CloudTrail events
resource "aws_cloudwatch_log_group" "cloudtrail" {
  name              = local.log_group_name
  retention_in_days = var.cloudwatch_log_retention_days

  tags = merge(local.common_tags, {
    Description = "CloudWatch log group for CloudTrail real-time events"
    Service     = "CloudWatch Logs"
  })
}

# IAM role for CloudTrail to write to CloudWatch Logs
resource "aws_iam_role" "cloudtrail_logs" {
  name               = local.role_name
  assume_role_policy = data.aws_iam_policy_document.cloudtrail_assume_role.json

  tags = merge(local.common_tags, {
    Description = "IAM role for CloudTrail to write logs to CloudWatch"
    Service     = "IAM"
  })
}

# Trust policy allowing CloudTrail service to assume the role
data "aws_iam_policy_document" "cloudtrail_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

# IAM policy for CloudTrail CloudWatch Logs permissions
resource "aws_iam_role_policy" "cloudtrail_logs" {
  name   = "CloudTrailLogsPolicy"
  role   = aws_iam_role.cloudtrail_logs.id
  policy = data.aws_iam_policy_document.cloudtrail_logs_policy.json
}

# CloudWatch Logs permissions policy document
data "aws_iam_policy_document" "cloudtrail_logs_policy" {
  # Allow CloudTrail to create log streams
  statement {
    sid    = "AWSCloudTrailCreateLogStream"
    effect = "Allow"

    actions = [
      "logs:CreateLogStream"
    ]

    resources = [
      "arn:${local.partition}:logs:${local.region}:${local.account_id}:log-group:${local.log_group_name}:log-stream:*"
    ]
  }

  # Allow CloudTrail to put log events
  statement {
    sid    = "AWSCloudTrailPutLogEvents"
    effect = "Allow"

    actions = [
      "logs:PutLogEvents"
    ]

    resources = [
      "arn:${local.partition}:logs:${local.region}:${local.account_id}:log-group:${local.log_group_name}:log-stream:*"
    ]
  }
}

# CloudTrail configuration
resource "aws_cloudtrail" "main" {
  name           = local.trail_name
  s3_bucket_name = aws_s3_bucket.cloudtrail_logs.id
  s3_key_prefix  = var.s3_key_prefix

  # CloudWatch Logs integration for real-time monitoring
  cloud_watch_logs_group_arn = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
  cloud_watch_logs_role_arn  = aws_iam_role.cloudtrail_logs.arn

  # Security and compliance settings
  enable_log_file_validation    = var.enable_log_file_validation
  is_multi_region_trail        = var.is_multi_region_trail
  include_global_service_events = var.include_global_service_events
  
  # Enable logging by default
  enable_logging = true

  # KMS encryption if specified
  kms_key_id = var.kms_key_id != "" ? var.kms_key_id : null

  # Ensure dependencies are created first
  depends_on = [
    aws_s3_bucket_policy.cloudtrail_logs,
    aws_iam_role_policy.cloudtrail_logs
  ]

  tags = merge(local.common_tags, {
    Description = "CloudTrail for comprehensive API activity logging"
    Service     = "CloudTrail"
  })
}

# SNS topic for alarm notifications
resource "aws_sns_topic" "cloudtrail_alerts" {
  count = var.enable_cloudwatch_alarms ? 1 : 0
  name  = local.topic_name

  tags = merge(local.common_tags, {
    Description = "SNS topic for CloudTrail security alarm notifications"
    Service     = "SNS"
  })
}

# Optional email subscription for SNS notifications
resource "aws_sns_topic_subscription" "email_alerts" {
  count     = var.enable_cloudwatch_alarms && var.alarm_notification_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.cloudtrail_alerts[0].arn
  protocol  = "email"
  endpoint  = var.alarm_notification_email
}

# CloudWatch metric filter for root account usage detection
resource "aws_logs_metric_filter" "root_account_usage" {
  count          = var.enable_cloudwatch_alarms ? 1 : 0
  name           = "RootAccountUsage"
  log_group_name = aws_cloudwatch_log_group.cloudtrail.name
  
  # Pattern to detect root account API calls (excluding AWS service events)
  pattern = "{ $.userIdentity.type = \"Root\" && $.userIdentity.invokedBy NOT EXISTS && $.eventType != \"AwsServiceEvent\" }"

  metric_transformation {
    name      = "RootAccountUsageCount"
    namespace = "CloudTrailMetrics"
    value     = "1"
  }
}

# CloudWatch alarm for root account usage
resource "aws_cloudwatch_metric_alarm" "root_account_usage" {
  count               = var.enable_cloudwatch_alarms ? 1 : 0
  alarm_name          = "CloudTrail-RootAccountUsage-${local.random_suffix}"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "RootAccountUsageCount"
  namespace           = "CloudTrailMetrics"
  period              = "300"
  statistic           = "Sum"
  threshold           = "1"
  alarm_description   = "Alert when root account is used for API calls"
  alarm_actions       = [aws_sns_topic.cloudtrail_alerts[0].arn]

  tags = merge(local.common_tags, {
    Description = "CloudWatch alarm monitoring root account usage"
    Service     = "CloudWatch"
    Severity    = "High"
  })
}