# Main Terraform configuration for Simple File Backup Notifications
# This creates an S3 bucket with SNS notifications for backup monitoring

# Get current AWS account ID and caller identity
data "aws_caller_identity" "current" {}

# Get current AWS region
data "aws_region" "current" {}

# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}

# Merge default and custom tags
locals {
  common_tags = merge(
    {
      Project     = "Simple File Backup Notifications"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Recipe      = "simple-file-backup-notifications-s3-sns"
    },
    var.tags
  )
  
  # Generate unique resource names
  bucket_name    = "${var.s3_bucket_prefix}-${random_string.suffix.result}"
  sns_topic_name = "${var.sns_topic_name}-${random_string.suffix.result}"
}

# SNS Topic for backup notifications
# This topic receives S3 events and distributes them to email subscribers
resource "aws_sns_topic" "backup_notifications" {
  name         = local.sns_topic_name
  display_name = var.sns_display_name

  # Enable message delivery status logging
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

  tags = local.common_tags
}

# SNS Topic Policy to allow S3 to publish messages
# This policy grants S3 the necessary permissions to send notifications
resource "aws_sns_topic_policy" "backup_notifications_policy" {
  arn = aws_sns_topic.backup_notifications.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowS3ToPublish"
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.backup_notifications.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
          StringLike = {
            "aws:SourceArn" = "arn:aws:s3:::${local.bucket_name}"
          }
        }
      }
    ]
  })
}

# Email subscriptions to SNS topic
# Creates email subscriptions for each provided email address
resource "aws_sns_topic_subscription" "email_notifications" {
  count = length(var.email_addresses)

  topic_arn = aws_sns_topic.backup_notifications.arn
  protocol  = "email"
  endpoint  = var.email_addresses[count.index]

  # Prevent Terraform from trying to confirm subscriptions
  confirmation_timeout_in_minutes = 1
}

# S3 Bucket for backup file storage
# This bucket stores backup files and triggers notifications on object creation
resource "aws_s3_bucket" "backup_bucket" {
  bucket = local.bucket_name

  # Prevent accidental deletion of bucket
  lifecycle {
    prevent_destroy = false
  }

  tags = merge(local.common_tags, {
    Name = "Backup Storage Bucket"
    Type = "Storage"
  })
}

# S3 Bucket Versioning Configuration
# Enables versioning for data protection and recovery
resource "aws_s3_bucket_versioning" "backup_bucket_versioning" {
  count = var.enable_s3_versioning ? 1 : 0

  bucket = aws_s3_bucket.backup_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 Bucket Server-Side Encryption Configuration
# Encrypts objects at rest for security compliance
resource "aws_s3_bucket_server_side_encryption_configuration" "backup_bucket_encryption" {
  count = var.enable_s3_encryption ? 1 : 0

  bucket = aws_s3_bucket.backup_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = var.s3_encryption_algorithm
    }
    bucket_key_enabled = var.s3_encryption_algorithm == "aws:kms" ? true : false
  }
}

# S3 Bucket Public Access Block
# Prevents accidental public exposure of backup files
resource "aws_s3_bucket_public_access_block" "backup_bucket_pab" {
  bucket = aws_s3_bucket.backup_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 Bucket Lifecycle Configuration
# Automatically manages object lifecycle for cost optimization
resource "aws_s3_bucket_lifecycle_configuration" "backup_bucket_lifecycle" {
  count = var.s3_lifecycle_expiration_days > 0 ? 1 : 0

  bucket = aws_s3_bucket.backup_bucket.id

  rule {
    id     = "backup_file_expiration"
    status = "Enabled"

    expiration {
      days = var.s3_lifecycle_expiration_days
    }

    # Also clean up incomplete multipart uploads
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }

    # Handle versioned objects if versioning is enabled
    dynamic "noncurrent_version_expiration" {
      for_each = var.enable_s3_versioning ? [1] : []
      content {
        noncurrent_days = var.s3_lifecycle_expiration_days
      }
    }
  }
}

# S3 Bucket Notification Configuration
# Configures S3 to send events to SNS topic when objects are created
resource "aws_s3_bucket_notification" "backup_notifications" {
  bucket = aws_s3_bucket.backup_bucket.id

  # Wait for SNS topic policy to be applied
  depends_on = [aws_sns_topic_policy.backup_notifications_policy]

  topic {
    topic_arn = aws_sns_topic.backup_notifications.arn
    events    = var.notification_event_types
    id        = "BackupNotification"

    # Optional: Add prefix and suffix filters for notifications
    dynamic "filter_prefix" {
      for_each = var.s3_object_prefix_filter != "" ? [var.s3_object_prefix_filter] : []
      content {
        filter_prefix = filter_prefix.value
      }
    }

    dynamic "filter_suffix" {
      for_each = var.s3_object_suffix_filter != "" ? [var.s3_object_suffix_filter] : []
      content {
        filter_suffix = filter_suffix.value
      }
    }
  }
}

# Optional: CloudTrail for S3 bucket access logging
# Creates a CloudTrail to log all API calls to the S3 bucket
resource "aws_cloudtrail" "s3_access_trail" {
  count = var.enable_cloudtrail_logging ? 1 : 0

  name                          = "${local.bucket_name}-access-trail"
  s3_bucket_name                = aws_s3_bucket.cloudtrail_logs[0].bucket
  s3_key_prefix                 = "cloudtrail-logs/"
  include_global_service_events = false
  is_multi_region_trail         = false
  enable_logging                = true

  event_selector {
    read_write_type                 = "All"
    include_management_events       = false
    exclude_management_event_sources = []

    data_resource {
      type   = "AWS::S3::Object"
      values = ["${aws_s3_bucket.backup_bucket.arn}/*"]
    }

    data_resource {
      type   = "AWS::S3::Bucket"
      values = [aws_s3_bucket.backup_bucket.arn]
    }
  }

  tags = merge(local.common_tags, {
    Name = "S3 Backup Bucket Access Trail"
    Type = "Logging"
  })
}

# CloudTrail logs bucket (only created if CloudTrail is enabled)
resource "aws_s3_bucket" "cloudtrail_logs" {
  count = var.enable_cloudtrail_logging ? 1 : 0

  bucket = "${local.bucket_name}-cloudtrail-logs"

  tags = merge(local.common_tags, {
    Name = "CloudTrail Logs Bucket"
    Type = "Logging"
  })
}

# CloudTrail logs bucket policy
resource "aws_s3_bucket_policy" "cloudtrail_logs_policy" {
  count = var.enable_cloudtrail_logging ? 1 : 0

  bucket = aws_s3_bucket.cloudtrail_logs[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSCloudTrailAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.cloudtrail_logs[0].arn
        Condition = {
          StringEquals = {
            "aws:SourceArn" = "arn:aws:cloudtrail:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:trail/${local.bucket_name}-access-trail"
          }
        }
      },
      {
        Sid    = "AWSCloudTrailWrite"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.cloudtrail_logs[0].arn}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
            "aws:SourceArn" = "arn:aws:cloudtrail:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:trail/${local.bucket_name}-access-trail"
          }
        }
      }
    ]
  })
}

# CloudTrail logs bucket public access block
resource "aws_s3_bucket_public_access_block" "cloudtrail_logs_pab" {
  count = var.enable_cloudtrail_logging ? 1 : 0

  bucket = aws_s3_bucket.cloudtrail_logs[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}