# S3 Glacier Automated Archiving Infrastructure
# This file creates the complete infrastructure for automated data archiving
# including S3 bucket, lifecycle policies, SNS notifications, and monitoring

# Data source to get current AWS account ID
data "aws_caller_identity" "current" {}

# Data source to get current AWS region
data "aws_region" "current" {}

# Generate random suffix for bucket name to ensure uniqueness
resource "random_string" "bucket_suffix" {
  length  = 8
  special = false
  upper   = false
}

# Create S3 bucket for automated archiving
resource "aws_s3_bucket" "archive_bucket" {
  bucket = "${var.bucket_name_prefix}-${random_string.bucket_suffix.result}"
  
  # Enable object lock if specified (requires versioning)
  object_lock_enabled = var.enable_object_lock
  
  tags = merge(var.tags, {
    Name        = "Archive Bucket"
    Purpose     = "Automated Data Archiving"
    StorageType = "Multi-tier (Standard/Glacier/Deep Archive)"
  })
}

# Configure bucket versioning
resource "aws_s3_bucket_versioning" "archive_bucket_versioning" {
  bucket = aws_s3_bucket.archive_bucket.id
  
  versioning_configuration {
    status     = var.enable_versioning ? "Enabled" : "Disabled"
    mfa_delete = var.enable_mfa_delete ? "Enabled" : "Disabled"
  }
}

# Configure server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "archive_bucket_encryption" {
  count  = var.enable_server_side_encryption ? 1 : 0
  bucket = aws_s3_bucket.archive_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# Configure public access block
resource "aws_s3_bucket_public_access_block" "archive_bucket_pab" {
  count  = var.enable_public_access_block ? 1 : 0
  bucket = aws_s3_bucket.archive_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Configure object lock configuration if enabled
resource "aws_s3_bucket_object_lock_configuration" "archive_bucket_object_lock" {
  count  = var.enable_object_lock ? 1 : 0
  bucket = aws_s3_bucket.archive_bucket.id

  rule {
    default_retention {
      mode = var.retention_mode
      days = var.lifecycle_glacier_transition_days
    }
  }
  
  depends_on = [aws_s3_bucket_versioning.archive_bucket_versioning]
}

# Create lifecycle policy for automated archiving
resource "aws_s3_bucket_lifecycle_configuration" "archive_lifecycle" {
  bucket = aws_s3_bucket.archive_bucket.id

  rule {
    id     = "ArchiveRule"
    status = "Enabled"
    
    # Apply to objects with specified prefix
    filter {
      prefix = var.archive_prefix
    }
    
    # Transition to Glacier Flexible Retrieval after specified days
    transition {
      days          = var.lifecycle_glacier_transition_days
      storage_class = "GLACIER"
    }
    
    # Transition to Glacier Deep Archive after specified days
    transition {
      days          = var.lifecycle_deep_archive_transition_days
      storage_class = "DEEP_ARCHIVE"
    }
    
    # Clean up incomplete multipart uploads after 7 days
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
  
  # Optional: Add rule for managing versioned objects
  dynamic "rule" {
    for_each = var.enable_versioning ? [1] : []
    content {
      id     = "VersionedObjectsRule"
      status = "Enabled"
      
      filter {
        prefix = var.archive_prefix
      }
      
      # Manage non-current versions
      noncurrent_version_transition {
        noncurrent_days = var.lifecycle_glacier_transition_days
        storage_class   = "GLACIER"
      }
      
      noncurrent_version_transition {
        noncurrent_days = var.lifecycle_deep_archive_transition_days
        storage_class   = "DEEP_ARCHIVE"
      }
      
      # Delete old versions after 2 years
      noncurrent_version_expiration {
        noncurrent_days = 730
      }
    }
  }
  
  depends_on = [aws_s3_bucket_versioning.archive_bucket_versioning]
}

# Create SNS topic for archive notifications
resource "aws_sns_topic" "archive_notifications" {
  name = "archive-notifications-${random_string.bucket_suffix.result}"
  
  tags = merge(var.tags, {
    Name    = "Archive Notifications"
    Purpose = "S3 Glacier restore notifications"
  })
}

# Create SNS topic policy to allow S3 to publish messages
resource "aws_sns_topic_policy" "archive_notifications_policy" {
  arn = aws_sns_topic.archive_notifications.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
        Action = "SNS:Publish"
        Resource = aws_sns_topic.archive_notifications.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
          StringLike = {
            "aws:SourceArn" = aws_s3_bucket.archive_bucket.arn
          }
        }
      }
    ]
  })
}

# Optional: Subscribe email to SNS topic if provided
resource "aws_sns_topic_subscription" "email_notification" {
  count     = var.notification_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.archive_notifications.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# Configure S3 bucket notifications for restore events
resource "aws_s3_bucket_notification" "archive_bucket_notification" {
  bucket = aws_s3_bucket.archive_bucket.id

  topic {
    topic_arn = aws_sns_topic.archive_notifications.arn
    events = [
      "s3:ObjectRestore:Completed",
      "s3:ObjectRestore:Post"
    ]
    
    filter_prefix = var.archive_prefix
  }
  
  depends_on = [aws_sns_topic_policy.archive_notifications_policy]
}

# Create IAM role for S3 access (useful for applications)
resource "aws_iam_role" "s3_archive_role" {
  name = "S3ArchiveRole-${random_string.bucket_suffix.result}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
  
  tags = merge(var.tags, {
    Name    = "S3 Archive Role"
    Purpose = "Access to S3 archive bucket"
  })
}

# Create IAM policy for S3 archive operations
resource "aws_iam_policy" "s3_archive_policy" {
  name        = "S3ArchivePolicy-${random_string.bucket_suffix.result}"
  description = "Policy for S3 archive operations including restore requests"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetObjectVersion",
          "s3:RestoreObject"
        ]
        Resource = [
          aws_s3_bucket.archive_bucket.arn,
          "${aws_s3_bucket.archive_bucket.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetBucketLocation",
          "s3:GetBucketVersioning",
          "s3:GetBucketLifecycleConfiguration"
        ]
        Resource = aws_s3_bucket.archive_bucket.arn
      }
    ]
  })
  
  tags = merge(var.tags, {
    Name    = "S3 Archive Policy"
    Purpose = "S3 archive operations"
  })
}

# Attach policy to role
resource "aws_iam_role_policy_attachment" "s3_archive_role_policy" {
  role       = aws_iam_role.s3_archive_role.name
  policy_arn = aws_iam_policy.s3_archive_policy.arn
}

# Create instance profile for EC2 instances
resource "aws_iam_instance_profile" "s3_archive_instance_profile" {
  name = "S3ArchiveInstanceProfile-${random_string.bucket_suffix.result}"
  role = aws_iam_role.s3_archive_role.name
  
  tags = merge(var.tags, {
    Name    = "S3 Archive Instance Profile"
    Purpose = "EC2 instance access to S3 archive"
  })
}

# Create CloudWatch log group for archiving operations
resource "aws_cloudwatch_log_group" "archive_logs" {
  name              = "/aws/s3/archive-${random_string.bucket_suffix.result}"
  retention_in_days = 30
  
  tags = merge(var.tags, {
    Name    = "S3 Archive Logs"
    Purpose = "Logging for S3 archive operations"
  })
}

# Create CloudWatch metric filter for monitoring transitions
resource "aws_cloudwatch_metric_filter" "glacier_transitions" {
  name           = "GlacierTransitions-${random_string.bucket_suffix.result}"
  log_group_name = aws_cloudwatch_log_group.archive_logs.name
  
  pattern = "[timestamp, request_id, account_id, bucket_name, operation = \"TRANSITION\", ...]"
  
  metric_transformation {
    name      = "GlacierTransitionCount"
    namespace = "S3Archive"
    value     = "1"
  }
}

# Create CloudWatch alarm for failed restore operations
resource "aws_cloudwatch_metric_alarm" "restore_failures" {
  alarm_name          = "S3-Restore-Failures-${random_string.bucket_suffix.result}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "RestoreFailures"
  namespace           = "S3Archive"
  period              = "300"
  statistic           = "Sum"
  threshold           = "1"
  alarm_description   = "This metric monitors failed S3 restore operations"
  alarm_actions       = [aws_sns_topic.archive_notifications.arn]
  
  tags = merge(var.tags, {
    Name    = "S3 Restore Failures Alarm"
    Purpose = "Monitor S3 restore operation failures"
  })
}

# Create sample data for demonstration (optional)
resource "aws_s3_object" "sample_data" {
  bucket = aws_s3_bucket.archive_bucket.id
  key    = "${var.archive_prefix}sample-data.txt"
  content = "This is a sample file for S3 Glacier archiving demonstration.\nCreated on: ${timestamp()}\nBucket: ${aws_s3_bucket.archive_bucket.id}\nLifecycle: Objects in this prefix will be archived to Glacier after ${var.lifecycle_glacier_transition_days} days and Deep Archive after ${var.lifecycle_deep_archive_transition_days} days."
  
  tags = merge(var.tags, {
    Name         = "Sample Archive Data"
    Purpose      = "Demonstration file for archiving"
    ArchiveAfter = "${var.lifecycle_glacier_transition_days} days"
  })
}

# Create additional sample files for testing
resource "aws_s3_object" "test_files" {
  count  = 3
  bucket = aws_s3_bucket.archive_bucket.id
  key    = "${var.archive_prefix}test-file-${count.index + 1}.txt"
  content = "Test file ${count.index + 1} created on ${timestamp()}\nThis file will be automatically archived according to the lifecycle policy."
  
  tags = merge(var.tags, {
    Name         = "Test File ${count.index + 1}"
    Purpose      = "Test file for archiving demonstration"
    ArchiveAfter = "${var.lifecycle_glacier_transition_days} days"
  })
}