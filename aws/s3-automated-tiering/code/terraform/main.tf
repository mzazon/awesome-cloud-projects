# S3 Intelligent Tiering and Lifecycle Management Infrastructure
# This configuration implements automated storage optimization using S3 Intelligent Tiering
# and lifecycle policies for comprehensive cost optimization

# Data sources for current AWS context
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

# Generate random suffix for unique resource naming
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# Locals for computed values and tags
locals {
  bucket_name = "${var.bucket_name_prefix}-${random_id.bucket_suffix.hex}"
  
  # Merge default tags with additional tags
  common_tags = merge(
    {
      Project     = "S3 Intelligent Tiering Demo"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Recipe      = "intelligent-tiering-lifecycle-management-s3"
    },
    var.additional_tags
  )
}

# S3 Bucket for access logging (if enabled)
resource "aws_s3_bucket" "access_logs" {
  count  = var.enable_access_logging ? 1 : 0
  bucket = "${local.bucket_name}-access-logs"
  
  tags = merge(local.common_tags, {
    Name = "${local.bucket_name}-access-logs"
    Type = "AccessLogs"
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

# Main S3 Bucket with Intelligent Tiering
resource "aws_s3_bucket" "main" {
  bucket        = local.bucket_name
  force_destroy = true # Allow Terraform to destroy bucket with objects for demo purposes
  
  # Enable Object Lock if specified
  object_lock_enabled = var.enable_object_lock
  
  tags = merge(local.common_tags, {
    Name = local.bucket_name
    Type = "Main"
  })
}

# Block all public access to the main bucket
resource "aws_s3_bucket_public_access_block" "main" {
  bucket = aws_s3_bucket.main.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Configure bucket versioning for data protection
resource "aws_s3_bucket_versioning" "main" {
  bucket = aws_s3_bucket.main.id
  
  versioning_configuration {
    status     = var.enable_versioning ? "Enabled" : "Suspended"
    mfa_delete = var.enable_mfa_delete ? "Enabled" : "Disabled"
  }
}

# Server-side encryption configuration
resource "aws_s3_bucket_server_side_encryption_configuration" "main" {
  bucket = aws_s3_bucket.main.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# Object Lock configuration (if enabled)
resource "aws_s3_bucket_object_lock_configuration" "main" {
  count  = var.enable_object_lock ? 1 : 0
  bucket = aws_s3_bucket.main.id

  rule {
    default_retention {
      mode  = var.object_lock_mode
      years = var.object_lock_retention_years
    }
  }
}

# S3 Access Logging configuration
resource "aws_s3_bucket_logging" "main" {
  count  = var.enable_access_logging ? 1 : 0
  bucket = aws_s3_bucket.main.id

  target_bucket = aws_s3_bucket.access_logs[0].id
  target_prefix = "access-logs/"
}

# S3 Intelligent Tiering Configuration
# This automatically optimizes storage costs by moving objects between access tiers
resource "aws_s3_bucket_intelligent_tiering_configuration" "main" {
  bucket = aws_s3_bucket.main.id
  name   = "EntireBucketConfig"
  status = "Enabled"

  # Apply to all objects in the bucket
  filter {
    prefix = ""
  }

  # Configure tiering for Archive Access (minimum 90 days)
  tiering {
    access_tier = "ARCHIVE_ACCESS"
    days        = var.intelligent_tiering_archive_days
  }

  # Configure tiering for Deep Archive Access (minimum 180 days)
  tiering {
    access_tier = "DEEP_ARCHIVE_ACCESS"
    days        = var.intelligent_tiering_deep_archive_days
  }
}

# S3 Lifecycle Policy for comprehensive storage optimization
resource "aws_s3_bucket_lifecycle_configuration" "main" {
  bucket = aws_s3_bucket.main.id

  # Depends on versioning configuration to ensure proper setup
  depends_on = [aws_s3_bucket_versioning.main]

  rule {
    id     = "OptimizeStorage"
    status = "Enabled"

    # Apply to all objects
    filter {
      prefix = ""
    }

    # Transition current objects to Intelligent Tiering
    transition {
      days          = var.lifecycle_transition_to_intelligent_tiering_days
      storage_class = "INTELLIGENT_TIERING"
    }

    # Clean up incomplete multipart uploads
    abort_incomplete_multipart_upload {
      days_after_initiation = var.lifecycle_abort_incomplete_multipart_days
    }

    # Manage noncurrent object versions (when versioning is enabled)
    dynamic "noncurrent_version_transition" {
      for_each = var.enable_versioning ? [1] : []
      content {
        noncurrent_days = var.noncurrent_version_transition_ia_days
        storage_class   = "STANDARD_IA"
      }
    }

    dynamic "noncurrent_version_transition" {
      for_each = var.enable_versioning ? [1] : []
      content {
        noncurrent_days = var.noncurrent_version_transition_glacier_days
        storage_class   = "GLACIER"
      }
    }

    # Delete old noncurrent versions to manage costs
    dynamic "noncurrent_version_expiration" {
      for_each = var.enable_versioning ? [1] : []
      content {
        noncurrent_days = var.noncurrent_version_expiration_days
      }
    }
  }
}

# S3 Bucket Metrics Configuration for CloudWatch monitoring
resource "aws_s3_bucket_metric" "main" {
  bucket = aws_s3_bucket.main.id
  name   = "EntireBucket"

  filter {
    prefix = ""
  }
}

# CloudWatch Dashboard for Storage Optimization Monitoring
resource "aws_cloudwatch_dashboard" "storage_optimization" {
  count          = var.enable_cloudwatch_dashboard ? 1 : 0
  dashboard_name = "S3-Storage-Optimization-${random_id.bucket_suffix.hex}"

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
            ["AWS/S3", "BucketSizeBytes", "BucketName", aws_s3_bucket.main.id, "StorageType", "StandardStorage"],
            [".", ".", ".", ".", ".", "IntelligentTieringIAStorage"],
            [".", ".", ".", ".", ".", "IntelligentTieringAAStorage"],
            [".", ".", ".", ".", ".", "IntelligentTieringDAStorage"]
          ]
          period = 86400
          stat   = "Average"
          region = var.aws_region
          title  = "S3 Storage Distribution by Class"
          view   = "timeSeries"
          stacked = false
          yAxis = {
            left = {
              min = 0
            }
          }
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
            ["AWS/S3", "NumberOfObjects", "BucketName", aws_s3_bucket.main.id, "StorageType", "AllStorageTypes"]
          ]
          period = 86400
          stat   = "Average"
          region = var.aws_region
          title  = "Total Number of Objects"
          view   = "timeSeries"
          yAxis = {
            left = {
              min = 0
            }
          }
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 12
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["AWS/S3", "AllRequests", "BucketName", aws_s3_bucket.main.id],
            [".", "GetRequests", ".", "."],
            [".", "PutRequests", ".", "."]
          ]
          period = 3600
          stat   = "Sum"
          region = var.aws_region
          title  = "S3 Request Metrics"
          view   = "timeSeries"
          yAxis = {
            left = {
              min = 0
            }
          }
        }
      }
    ]
  })
}

# Sample objects to demonstrate Intelligent Tiering (optional for demo)
# These would typically be created by applications, not Terraform
resource "aws_s3_object" "sample_frequent" {
  bucket       = aws_s3_bucket.main.id
  key          = "active/frequent-data.txt"
  content      = "Frequently accessed data - Created by Terraform at ${timestamp()}"
  content_type = "text/plain"

  tags = {
    AccessPattern = "Frequent"
    Department    = "Operations"
    CreatedBy     = "Terraform"
  }
}

resource "aws_s3_object" "sample_archive" {
  bucket       = aws_s3_bucket.main.id
  key          = "archive/archive-data.txt"
  content      = "Archive data created by Terraform at ${timestamp()}"
  content_type = "text/plain"

  tags = {
    AccessPattern = "Archive"
    Department    = "Compliance"
    CreatedBy     = "Terraform"
  }
}

# Create a larger sample file for demonstration
resource "aws_s3_object" "sample_large" {
  bucket       = aws_s3_bucket.main.id
  key          = "data/large-sample.dat"
  content      = base64encode(random_id.bucket_suffix.hex)
  content_type = "application/octet-stream"

  tags = {
    AccessPattern = "Mixed"
    Department    = "Engineering"
    CreatedBy     = "Terraform"
    FileType      = "Binary"
  }
}