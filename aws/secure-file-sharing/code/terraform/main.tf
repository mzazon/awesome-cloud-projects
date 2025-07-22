# Main Terraform Configuration for S3 Presigned URLs File Sharing Solution
# This file creates all the infrastructure components needed for secure file sharing

# Generate random suffix for unique bucket naming
resource "random_string" "bucket_suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local values for consistent naming and configuration
locals {
  bucket_name = var.bucket_name_suffix != "" ? "${var.project_name}-${var.bucket_name_suffix}" : "${var.project_name}-${random_string.bucket_suffix.result}"
  
  # Access logging bucket name
  access_log_bucket_name = "${local.bucket_name}-access-logs"
  
  # Common tags for all resources
  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Recipe      = "s3-presigned-urls"
    },
    var.additional_tags
  )
}

# S3 bucket for access logs (if access logging is enabled)
resource "aws_s3_bucket" "access_logs" {
  count  = var.enable_access_logging ? 1 : 0
  bucket = local.access_log_bucket_name

  tags = merge(local.common_tags, {
    Name        = "Access Logs Bucket"
    Description = "Stores access logs for the main file sharing bucket"
  })
}

# Block public access for access logs bucket
resource "aws_s3_bucket_public_access_block" "access_logs" {
  count  = var.enable_access_logging ? 1 : 0
  bucket = aws_s3_bucket.access_logs[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Server-side encryption for access logs bucket
resource "aws_s3_bucket_server_side_encryption_configuration" "access_logs" {
  count  = var.enable_access_logging ? 1 : 0
  bucket = aws_s3_bucket.access_logs[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# Main S3 bucket for file sharing
resource "aws_s3_bucket" "file_sharing" {
  bucket = local.bucket_name

  tags = merge(local.common_tags, {
    Name        = "File Sharing Bucket"
    Description = "Main bucket for secure file sharing using presigned URLs"
  })
}

# Block all public access to the file sharing bucket
# This is critical for security - files should only be accessible via presigned URLs
resource "aws_s3_bucket_public_access_block" "file_sharing" {
  bucket = aws_s3_bucket.file_sharing.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Enable versioning for better file management and recovery
resource "aws_s3_bucket_versioning" "file_sharing" {
  bucket = aws_s3_bucket.file_sharing.id
  
  versioning_configuration {
    status = var.enable_versioning ? "Enabled" : "Suspended"
  }
}

# Server-side encryption configuration
resource "aws_s3_bucket_server_side_encryption_configuration" "file_sharing" {
  count  = var.enable_encryption ? 1 : 0
  bucket = aws_s3_bucket.file_sharing.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# Access logging configuration (if enabled)
resource "aws_s3_bucket_logging" "file_sharing" {
  count  = var.enable_access_logging ? 1 : 0
  bucket = aws_s3_bucket.file_sharing.id

  target_bucket = aws_s3_bucket.access_logs[0].id
  target_prefix = "access-logs/"
}

# CORS configuration to enable web browser access to presigned URLs
resource "aws_s3_bucket_cors_configuration" "file_sharing" {
  bucket = aws_s3_bucket.file_sharing.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = var.cors_allowed_methods
    allowed_origins = var.cors_allowed_origins
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}

# Lifecycle configuration for automatic file management
resource "aws_s3_bucket_lifecycle_configuration" "file_sharing" {
  bucket = aws_s3_bucket.file_sharing.id

  # Rule for documents folder - transition to cheaper storage classes
  dynamic "rule" {
    for_each = var.lifecycle_rules.enable_documents_transition ? [1] : []
    content {
      id     = "documents-lifecycle"
      status = "Enabled"

      filter {
        prefix = "documents/"
      }

      transition {
        days          = var.lifecycle_rules.documents_ia_days
        storage_class = "STANDARD_IA"
      }

      transition {
        days          = var.lifecycle_rules.documents_glacier_days
        storage_class = "GLACIER"
      }

      noncurrent_version_transition {
        noncurrent_days = 30
        storage_class   = "STANDARD_IA"
      }

      noncurrent_version_transition {
        noncurrent_days = 60
        storage_class   = "GLACIER"
      }
    }
  }

  # Rule for uploads folder - automatic cleanup of temporary uploads
  dynamic "rule" {
    for_each = var.lifecycle_rules.enable_uploads_cleanup ? [1] : []
    content {
      id     = "uploads-cleanup"
      status = "Enabled"

      filter {
        prefix = "uploads/"
      }

      expiration {
        days = var.lifecycle_rules.uploads_expiry_days
      }

      noncurrent_version_expiration {
        noncurrent_days = var.lifecycle_rules.uploads_expiry_days
      }

      abort_incomplete_multipart_upload {
        days_after_initiation = 1
      }
    }
  }
}

# IAM role for presigned URL generation (for applications/services)
resource "aws_iam_role" "presigned_url_generator" {
  name = "${var.project_name}-presigned-url-generator"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = [
            "lambda.amazonaws.com",
            "ec2.amazonaws.com"
          ]
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name        = "Presigned URL Generator Role"
    Description = "IAM role for generating presigned URLs"
  })
}

# IAM policy for presigned URL generation
resource "aws_iam_role_policy" "presigned_url_generator" {
  name = "${var.project_name}-presigned-url-policy"
  role = aws_iam_role.presigned_url_generator.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:GetObjectVersion",
          "s3:PutObjectAcl"
        ]
        Resource = [
          "${aws_s3_bucket.file_sharing.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetBucketLocation",
          "s3:GetBucketVersioning"
        ]
        Resource = aws_s3_bucket.file_sharing.arn
      }
    ]
  })
}

# CloudWatch Log Group for monitoring S3 access (if CloudTrail is enabled)
resource "aws_cloudwatch_log_group" "s3_access_logs" {
  count             = var.enable_cloudtrail_logging ? 1 : 0
  name              = "/aws/cloudtrail/${var.project_name}-s3-access"
  retention_in_days = 30

  tags = merge(local.common_tags, {
    Name        = "S3 Access Logs"
    Description = "CloudWatch logs for S3 API access"
  })
}

# CloudTrail for S3 API logging (if enabled)
resource "aws_cloudtrail" "s3_access" {
  count                         = var.enable_cloudtrail_logging ? 1 : 0
  name                         = "${var.project_name}-s3-cloudtrail"
  s3_bucket_name               = aws_s3_bucket.file_sharing.bucket
  include_global_service_events = false
  is_multi_region_trail        = false
  enable_logging              = true

  cloud_watch_logs_group_arn = "${aws_cloudwatch_log_group.s3_access_logs[0].arn}:*"
  cloud_watch_logs_role_arn  = aws_iam_role.cloudtrail_logs[0].arn

  event_selector {
    read_write_type                 = "All"
    include_management_events       = false
    exclude_management_event_sources = []

    data_resource {
      type   = "AWS::S3::Object"
      values = ["${aws_s3_bucket.file_sharing.arn}/*"]
    }

    data_resource {
      type   = "AWS::S3::Bucket"
      values = [aws_s3_bucket.file_sharing.arn]
    }
  }

  tags = merge(local.common_tags, {
    Name        = "S3 CloudTrail"
    Description = "CloudTrail for S3 API access logging"
  })
}

# IAM role for CloudTrail logs
resource "aws_iam_role" "cloudtrail_logs" {
  count = var.enable_cloudtrail_logging ? 1 : 0
  name  = "${var.project_name}-cloudtrail-logs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
      }
    ]
  })

  tags = local.common_tags
}

# IAM policy for CloudTrail to write to CloudWatch Logs
resource "aws_iam_role_policy" "cloudtrail_logs" {
  count = var.enable_cloudtrail_logging ? 1 : 0
  name  = "${var.project_name}-cloudtrail-logs-policy"
  role  = aws_iam_role.cloudtrail_logs[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.s3_access_logs[0].arn}:*"
      }
    ]
  })
}

# SNS topic for notifications (if email is provided)
resource "aws_sns_topic" "file_sharing_alerts" {
  count = var.notification_email != "" ? 1 : 0
  name  = "${var.project_name}-file-sharing-alerts"

  tags = merge(local.common_tags, {
    Name        = "File Sharing Alerts"
    Description = "SNS topic for file sharing system alerts"
  })
}

# SNS subscription for email notifications
resource "aws_sns_topic_subscription" "email_alerts" {
  count     = var.notification_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.file_sharing_alerts[0].arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# CloudWatch metric alarm for unusual S3 access patterns
resource "aws_cloudwatch_metric_alarm" "high_s3_requests" {
  count               = var.notification_email != "" ? 1 : 0
  alarm_name          = "${var.project_name}-high-s3-requests"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "NumberOfObjects"
  namespace           = "AWS/S3"
  period              = "300"
  statistic           = "Average"
  threshold           = "1000"
  alarm_description   = "This metric monitors S3 request volume"
  alarm_actions       = [aws_sns_topic.file_sharing_alerts[0].arn]

  dimensions = {
    BucketName = aws_s3_bucket.file_sharing.bucket
  }

  tags = merge(local.common_tags, {
    Name        = "High S3 Requests Alarm"
    Description = "Monitors for unusual S3 access patterns"
  })
}

# Data source for current AWS caller identity
data "aws_caller_identity" "current" {}

# Data source for current AWS region
data "aws_region" "current" {}