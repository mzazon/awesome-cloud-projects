# Data sources for AWS account information
data "aws_caller_identity" "current" {}

data "aws_region" "primary" {}

data "aws_region" "dr" {
  provider = aws.dr
}

# Random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 4
}

# Local values for resource naming and configuration
locals {
  # Generate unique resource suffix
  resource_suffix = var.resource_name_suffix != "" ? var.resource_name_suffix : random_id.suffix.hex
  
  # Generate bucket names
  source_bucket_name = var.source_bucket_name != "" ? var.source_bucket_name : "${var.bucket_prefix}-source-${local.resource_suffix}"
  dest_bucket_name   = var.destination_bucket_name != "" ? var.destination_bucket_name : "${var.bucket_prefix}-destination-${local.resource_suffix}"
  
  # Resource naming
  replication_role_name = "s3-replication-role-${local.resource_suffix}"
  cloudtrail_name      = "s3-replication-trail-${local.resource_suffix}"
  sns_topic_name       = "s3-replication-alerts-${local.resource_suffix}"
  
  # Common tags
  common_tags = merge(
    {
      Project     = "S3-Disaster-Recovery"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Recipe      = "disaster-recovery-s3-cross-region-replication"
    },
    var.additional_tags
  )
}

# ==========================================
# S3 BUCKETS
# ==========================================

# Source S3 bucket in primary region
resource "aws_s3_bucket" "source" {
  bucket        = local.source_bucket_name
  force_destroy = true # WARNING: This will delete all objects when destroying the bucket
  
  tags = merge(local.common_tags, {
    Name = local.source_bucket_name
    Type = "Source"
    Region = var.primary_region
  })
}

# Destination S3 bucket in DR region
resource "aws_s3_bucket" "destination" {
  provider      = aws.dr
  bucket        = local.dest_bucket_name
  force_destroy = true # WARNING: This will delete all objects when destroying the bucket
  
  tags = merge(local.common_tags, {
    Name = local.dest_bucket_name
    Type = "Destination"
    Region = var.dr_region
  })
}

# ==========================================
# S3 BUCKET VERSIONING
# ==========================================

# Enable versioning on source bucket (required for replication)
resource "aws_s3_bucket_versioning" "source" {
  bucket = aws_s3_bucket.source.id
  
  versioning_configuration {
    status = "Enabled"
  }
  
  depends_on = [aws_s3_bucket.source]
}

# Enable versioning on destination bucket (required for replication)
resource "aws_s3_bucket_versioning" "destination" {
  provider = aws.dr
  bucket   = aws_s3_bucket.destination.id
  
  versioning_configuration {
    status = "Enabled"
  }
  
  depends_on = [aws_s3_bucket.destination]
}

# ==========================================
# S3 BUCKET ENCRYPTION
# ==========================================

# Server-side encryption for source bucket
resource "aws_s3_bucket_server_side_encryption_configuration" "source" {
  count  = var.enable_bucket_encryption ? 1 : 0
  bucket = aws_s3_bucket.source.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.kms_key_id != "" ? "aws:kms" : "AES256"
      kms_master_key_id = var.kms_key_id != "" ? var.kms_key_id : null
    }
    bucket_key_enabled = var.kms_key_id != "" ? true : false
  }
}

# Server-side encryption for destination bucket
resource "aws_s3_bucket_server_side_encryption_configuration" "destination" {
  count    = var.enable_bucket_encryption ? 1 : 0
  provider = aws.dr
  bucket   = aws_s3_bucket.destination.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.kms_key_id != "" ? "aws:kms" : "AES256"
      kms_master_key_id = var.kms_key_id != "" ? var.kms_key_id : null
    }
    bucket_key_enabled = var.kms_key_id != "" ? true : false
  }
}

# ==========================================
# S3 PUBLIC ACCESS BLOCK
# ==========================================

# Block public access for source bucket
resource "aws_s3_bucket_public_access_block" "source" {
  count  = var.enable_public_access_block ? 1 : 0
  bucket = aws_s3_bucket.source.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Block public access for destination bucket
resource "aws_s3_bucket_public_access_block" "destination" {
  count    = var.enable_public_access_block ? 1 : 0
  provider = aws.dr
  bucket   = aws_s3_bucket.destination.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ==========================================
# S3 LIFECYCLE POLICIES
# ==========================================

# Lifecycle policy for source bucket
resource "aws_s3_bucket_lifecycle_configuration" "source" {
  count  = var.enable_lifecycle_policies ? 1 : 0
  bucket = aws_s3_bucket.source.id

  rule {
    id     = "cost_optimization"
    status = "Enabled"

    # Transition current versions
    transition {
      days          = var.transition_to_ia_days
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = var.transition_to_glacier_days
      storage_class = "GLACIER"
    }

    # Transition non-current versions
    noncurrent_version_transition {
      noncurrent_days = var.transition_to_ia_days
      storage_class   = "STANDARD_IA"
    }

    noncurrent_version_transition {
      noncurrent_days = var.transition_to_glacier_days
      storage_class   = "GLACIER"
    }

    # Delete non-current versions after 1 year
    noncurrent_version_expiration {
      noncurrent_days = 365
    }

    # Clean up incomplete multipart uploads
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.source]
}

# Lifecycle policy for destination bucket
resource "aws_s3_bucket_lifecycle_configuration" "destination" {
  count    = var.enable_lifecycle_policies ? 1 : 0
  provider = aws.dr
  bucket   = aws_s3_bucket.destination.id

  rule {
    id     = "dr_cost_optimization"
    status = "Enabled"

    # Transition current versions
    transition {
      days          = var.transition_to_ia_days
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = var.transition_to_glacier_days
      storage_class = "GLACIER"
    }

    # Transition non-current versions
    noncurrent_version_transition {
      noncurrent_days = var.transition_to_ia_days
      storage_class   = "STANDARD_IA"
    }

    noncurrent_version_transition {
      noncurrent_days = var.transition_to_glacier_days
      storage_class   = "GLACIER"
    }

    # Delete non-current versions after 1 year
    noncurrent_version_expiration {
      noncurrent_days = 365
    }

    # Clean up incomplete multipart uploads
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.destination]
}

# ==========================================
# IAM ROLE FOR REPLICATION
# ==========================================

# Trust policy document for S3 replication role
data "aws_iam_policy_document" "replication_trust" {
  statement {
    effect = "Allow"
    
    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }
    
    actions = ["sts:AssumeRole"]
  }
}

# IAM role for S3 cross-region replication
resource "aws_iam_role" "replication" {
  name               = local.replication_role_name
  assume_role_policy = data.aws_iam_policy_document.replication_trust.json
  
  tags = merge(local.common_tags, {
    Name = local.replication_role_name
    Type = "ReplicationRole"
  })
}

# Policy document for replication permissions
data "aws_iam_policy_document" "replication_policy" {
  # Permissions to read from source bucket
  statement {
    effect = "Allow"
    
    actions = [
      "s3:GetObjectVersionForReplication",
      "s3:GetObjectVersionAcl",
      "s3:GetObjectVersionTagging"
    ]
    
    resources = ["${aws_s3_bucket.source.arn}/*"]
  }
  
  # Permissions to list source bucket
  statement {
    effect = "Allow"
    
    actions = ["s3:ListBucket"]
    
    resources = [aws_s3_bucket.source.arn]
  }
  
  # Permissions to write to destination bucket
  statement {
    effect = "Allow"
    
    actions = [
      "s3:ReplicateObject",
      "s3:ReplicateDelete",
      "s3:ReplicateTags"
    ]
    
    resources = ["${aws_s3_bucket.destination.arn}/*"]
  }
}

# Attach replication policy to IAM role
resource "aws_iam_role_policy" "replication" {
  name   = "ReplicationPolicy"
  role   = aws_iam_role.replication.id
  policy = data.aws_iam_policy_document.replication_policy.json
}

# ==========================================
# S3 CROSS-REGION REPLICATION
# ==========================================

# Cross-region replication configuration
resource "aws_s3_bucket_replication_configuration" "replication" {
  # Replication role
  role   = aws_iam_role.replication.arn
  bucket = aws_s3_bucket.source.id

  # Replication rule
  rule {
    id     = "disaster-recovery-replication"
    status = "Enabled"

    # Apply to all objects or filtered objects
    dynamic "filter" {
      for_each = var.replication_prefix != "" ? [1] : []
      content {
        prefix = var.replication_prefix
      }
    }

    # Delete marker replication
    delete_marker_replication {
      status = "Enabled"
    }

    # Destination configuration
    destination {
      bucket        = aws_s3_bucket.destination.arn
      storage_class = var.replication_storage_class

      # Encryption configuration for destination
      dynamic "encryption_configuration" {
        for_each = var.enable_bucket_encryption && var.kms_key_id != "" ? [1] : []
        content {
          replica_kms_key_id = var.kms_key_id
        }
      }
    }
  }

  # Dependencies to ensure buckets are properly configured
  depends_on = [
    aws_s3_bucket_versioning.source,
    aws_s3_bucket_versioning.destination,
    aws_iam_role_policy.replication
  ]
}

# ==========================================
# SNS TOPIC FOR ALERTS (OPTIONAL)
# ==========================================

# SNS topic for CloudWatch alarm notifications
resource "aws_sns_topic" "alerts" {
  count = var.notification_email != "" ? 1 : 0
  name  = local.sns_topic_name
  
  tags = merge(local.common_tags, {
    Name = local.sns_topic_name
    Type = "AlertTopic"
  })
}

# SNS topic subscription for email notifications
resource "aws_sns_topic_subscription" "email" {
  count     = var.notification_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.alerts[0].arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# ==========================================
# CLOUDWATCH ALARMS
# ==========================================

# CloudWatch alarm for replication latency
resource "aws_cloudwatch_metric_alarm" "replication_latency" {
  count = var.enable_cloudwatch_alarms ? 1 : 0
  
  alarm_name          = "S3-Replication-Latency-${local.resource_suffix}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "ReplicationLatency"
  namespace           = "AWS/S3"
  period              = "300"
  statistic           = "Average"
  threshold           = var.replication_latency_threshold
  alarm_description   = "This metric monitors S3 cross-region replication latency"
  alarm_actions       = var.notification_email != "" ? [aws_sns_topic.alerts[0].arn] : []

  dimensions = {
    SourceBucket = aws_s3_bucket.source.bucket
  }

  tags = merge(local.common_tags, {
    Name = "S3-Replication-Latency-${local.resource_suffix}"
    Type = "ReplicationAlarm"
  })
}

# CloudWatch alarm for replication failures
resource "aws_cloudwatch_metric_alarm" "replication_failures" {
  count = var.enable_cloudwatch_alarms ? 1 : 0
  
  alarm_name          = "S3-Replication-Failures-${local.resource_suffix}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "ReplicationFailures"
  namespace           = "AWS/S3"
  period              = "300"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "This metric monitors S3 cross-region replication failures"
  alarm_actions       = var.notification_email != "" ? [aws_sns_topic.alerts[0].arn] : []
  treat_missing_data  = "notBreaching"

  dimensions = {
    SourceBucket = aws_s3_bucket.source.bucket
  }

  tags = merge(local.common_tags, {
    Name = "S3-Replication-Failures-${local.resource_suffix}"
    Type = "ReplicationAlarm"
  })
}

# ==========================================
# CLOUDTRAIL (OPTIONAL)
# ==========================================

# CloudTrail for S3 API logging
resource "aws_cloudtrail" "s3_trail" {
  count = var.enable_cloudtrail ? 1 : 0
  
  name           = local.cloudtrail_name
  s3_bucket_name = aws_s3_bucket.source.bucket
  s3_key_prefix  = var.cloudtrail_log_prefix

  event_selector {
    read_write_type                 = "All"
    include_management_events       = true
    exclude_management_event_sources = []

    # Monitor S3 bucket operations
    data_resource {
      type   = "AWS::S3::Object"
      values = ["${aws_s3_bucket.source.arn}/*"]
    }

    data_resource {
      type   = "AWS::S3::Bucket"
      values = [aws_s3_bucket.source.arn]
    }
  }

  depends_on = [aws_s3_bucket_policy.cloudtrail_policy]

  tags = merge(local.common_tags, {
    Name = local.cloudtrail_name
    Type = "AuditTrail"
  })
}

# S3 bucket policy for CloudTrail
resource "aws_s3_bucket_policy" "cloudtrail_policy" {
  count  = var.enable_cloudtrail ? 1 : 0
  bucket = aws_s3_bucket.source.id

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
        Resource = aws_s3_bucket.source.arn
      },
      {
        Sid    = "AWSCloudTrailWrite"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.source.arn}/${var.cloudtrail_log_prefix}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      }
    ]
  })
}