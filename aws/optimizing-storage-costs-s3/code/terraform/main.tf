# =============================================================================
# S3 Storage Cost Optimization with Storage Classes
# =============================================================================
# This Terraform configuration creates a comprehensive S3 cost optimization
# solution that demonstrates lifecycle policies, intelligent tiering, and
# cost monitoring capabilities.

# Local values for resource naming and configuration
locals {
  # Generate a random suffix for unique resource names
  random_suffix = random_string.suffix.result
  
  # Common tags applied to all resources
  common_tags = {
    Project     = "S3-Storage-Cost-Optimization"
    Environment = var.environment
    ManagedBy   = "Terraform"
    Recipe      = "storage-cost-optimization-s3-storage-classes"
  }
  
  # Storage lifecycle configuration for different data types
  lifecycle_rules = {
    frequently_accessed = {
      prefix = "data/frequently-accessed/"
      transitions = [
        {
          days          = 30
          storage_class = "STANDARD_IA"
        },
        {
          days          = 90
          storage_class = "GLACIER"
        }
      ]
    }
    infrequently_accessed = {
      prefix = "data/infrequently-accessed/"
      transitions = [
        {
          days          = 1
          storage_class = "STANDARD_IA"
        },
        {
          days          = 30
          storage_class = "GLACIER"
        },
        {
          days          = 180
          storage_class = "DEEP_ARCHIVE"
        }
      ]
    }
    archive = {
      prefix = "data/archive/"
      transitions = [
        {
          days          = 1
          storage_class = "GLACIER"
        },
        {
          days          = 30
          storage_class = "DEEP_ARCHIVE"
        }
      ]
    }
  }
}

# =============================================================================
# Random String Generation
# =============================================================================
# Generate a random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# =============================================================================
# Data Sources
# =============================================================================
# Get current AWS caller identity for account ID
data "aws_caller_identity" "current" {}

# Get AWS region
data "aws_region" "current" {}

# =============================================================================
# S3 Bucket Configuration
# =============================================================================
# Main S3 bucket for cost optimization demonstration
resource "aws_s3_bucket" "storage_optimization" {
  bucket = "${var.bucket_name_prefix}-${local.random_suffix}"
  
  tags = merge(local.common_tags, {
    Name        = "${var.bucket_name_prefix}-${local.random_suffix}"
    Description = "S3 bucket for demonstrating storage cost optimization"
  })
}

# Configure bucket versioning (optional but recommended)
resource "aws_s3_bucket_versioning" "storage_optimization" {
  bucket = aws_s3_bucket.storage_optimization.id
  versioning_configuration {
    status = var.enable_versioning ? "Enabled" : "Disabled"
  }
}

# Configure bucket encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "storage_optimization" {
  bucket = aws_s3_bucket.storage_optimization.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# Block public access to the bucket
resource "aws_s3_bucket_public_access_block" "storage_optimization" {
  bucket = aws_s3_bucket.storage_optimization.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# =============================================================================
# S3 Storage Analytics Configuration
# =============================================================================
# Configure storage analytics to analyze access patterns
resource "aws_s3_bucket_analytics_configuration" "storage_analytics" {
  bucket = aws_s3_bucket.storage_optimization.id
  name   = "storage-analytics-${local.random_suffix}"

  filter {
    prefix = "data/"
  }

  storage_class_analysis {
    data_export {
      output_schema_version = "V_1"
      destination {
        s3_bucket_destination {
          bucket_arn = aws_s3_bucket.storage_optimization.arn
          prefix     = "analytics-reports/"
          format     = "CSV"
        }
      }
    }
  }
}

# =============================================================================
# S3 Intelligent Tiering Configuration
# =============================================================================
# Configure intelligent tiering for automatic cost optimization
resource "aws_s3_bucket_intelligent_tiering_configuration" "storage_optimization" {
  bucket = aws_s3_bucket.storage_optimization.id
  name   = "EntireBucketIntelligentTiering"

  filter {
    prefix = "data/"
  }

  tiering {
    access_tier = "ARCHIVE_ACCESS"
    days        = 1
  }

  tiering {
    access_tier = "DEEP_ARCHIVE_ACCESS"
    days        = 90
  }

  status = "Enabled"
}

# =============================================================================
# S3 Lifecycle Policies
# =============================================================================
# Create lifecycle policy for cost optimization
resource "aws_s3_bucket_lifecycle_configuration" "storage_optimization" {
  bucket = aws_s3_bucket.storage_optimization.id

  # Lifecycle rule for frequently accessed data
  rule {
    id     = "FrequentlyAccessedData"
    status = "Enabled"

    filter {
      prefix = local.lifecycle_rules.frequently_accessed.prefix
    }

    dynamic "transition" {
      for_each = local.lifecycle_rules.frequently_accessed.transitions
      content {
        days          = transition.value.days
        storage_class = transition.value.storage_class
      }
    }
  }

  # Lifecycle rule for infrequently accessed data
  rule {
    id     = "InfrequentlyAccessedData"
    status = "Enabled"

    filter {
      prefix = local.lifecycle_rules.infrequently_accessed.prefix
    }

    dynamic "transition" {
      for_each = local.lifecycle_rules.infrequently_accessed.transitions
      content {
        days          = transition.value.days
        storage_class = transition.value.storage_class
      }
    }
  }

  # Lifecycle rule for archive data
  rule {
    id     = "ArchiveData"
    status = "Enabled"

    filter {
      prefix = local.lifecycle_rules.archive.prefix
    }

    dynamic "transition" {
      for_each = local.lifecycle_rules.archive.transitions
      content {
        days          = transition.value.days
        storage_class = transition.value.storage_class
      }
    }
  }

  # Optional: Clean up incomplete multipart uploads
  rule {
    id     = "CleanupIncompleteUploads"
    status = "Enabled"

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# =============================================================================
# CloudWatch Dashboard
# =============================================================================
# Create CloudWatch dashboard for storage cost monitoring
resource "aws_cloudwatch_dashboard" "storage_optimization" {
  dashboard_name = "S3-Storage-Cost-Optimization-${local.random_suffix}"

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
            ["AWS/S3", "BucketSizeBytes", "BucketName", aws_s3_bucket.storage_optimization.id, "StorageType", "StandardStorage"],
            ["...", "StandardIAStorage"],
            ["...", "GlacierStorage"],
            ["...", "DeepArchiveStorage"]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "S3 Storage by Class - ${aws_s3_bucket.storage_optimization.id}"
          period  = 86400
          stat    = "Average"
          yAxis = {
            left = {
              min = 0
            }
          }
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["AWS/S3", "NumberOfObjects", "BucketName", aws_s3_bucket.storage_optimization.id, "StorageType", "AllStorageTypes"]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "Total Objects in ${aws_s3_bucket.storage_optimization.id}"
          period  = 86400
          stat    = "Average"
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
        width  = 24
        height = 6

        properties = {
          metrics = [
            ["AWS/S3", "BucketSizeBytes", "BucketName", aws_s3_bucket.storage_optimization.id, "StorageType", "StandardStorage"],
            ["...", "StandardIAStorage"],
            ["...", "GlacierStorage"],
            ["...", "DeepArchiveStorage"]
          ]
          view    = "pie"
          region  = data.aws_region.current.name
          title   = "Storage Distribution by Class"
          period  = 86400
          stat    = "Average"
        }
      }
    ]
  })
}

# =============================================================================
# AWS Budgets Configuration
# =============================================================================
# Create budget for S3 storage cost monitoring
resource "aws_budgets_budget" "s3_storage_cost" {
  name         = "S3-Storage-Cost-Budget-${local.random_suffix}"
  budget_type  = "COST"
  limit_amount = var.budget_limit_amount
  limit_unit   = "USD"
  time_unit    = "MONTHLY"
  time_period_start = formatdate("YYYY-MM-01_00:00", timestamp())

  cost_filters {
    service = ["Amazon Simple Storage Service"]
  }

  # Configure budget alerts
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                 = var.budget_alert_threshold
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_email_addresses = var.budget_alert_emails
  }

  # Optional: Add forecasted alert
  dynamic "notification" {
    for_each = var.enable_forecasted_alerts ? [1] : []
    content {
      comparison_operator        = "GREATER_THAN"
      threshold                 = var.budget_alert_threshold
      threshold_type            = "PERCENTAGE"
      notification_type         = "FORECASTED"
      subscriber_email_addresses = var.budget_alert_emails
    }
  }
}

# =============================================================================
# Sample Data Objects (Optional)
# =============================================================================
# Create sample data objects to demonstrate lifecycle policies
resource "aws_s3_object" "sample_frequently_accessed" {
  for_each = var.create_sample_data ? {
    "app-logs" = {
      key     = "data/frequently-accessed/app-logs-${formatdate("YYYYMMDD", timestamp())}.log"
      content = "Sample application logs - frequently accessed data"
    }
    "user-data" = {
      key     = "data/frequently-accessed/user-data-${formatdate("YYYYMMDD", timestamp())}.json"
      content = jsonencode({
        type        = "user-data"
        created     = timestamp()
        description = "Sample user data for frequent access testing"
      })
    }
  } : {}

  bucket       = aws_s3_bucket.storage_optimization.id
  key          = each.value.key
  content      = each.value.content
  content_type = endswith(each.value.key, ".json") ? "application/json" : "text/plain"

  tags = merge(local.common_tags, {
    DataType    = "frequently-accessed"
    Description = "Sample data for testing lifecycle policies"
  })
}

resource "aws_s3_object" "sample_infrequently_accessed" {
  for_each = var.create_sample_data ? {
    "financial-report" = {
      key     = "data/infrequently-accessed/financial-report-${formatdate("YYYY-MM", timestamp())}.pdf"
      content = "Sample financial report - infrequently accessed data"
    }
    "monthly-backup" = {
      key     = "data/infrequently-accessed/monthly-backup-${formatdate("YYYY-MM", timestamp())}.zip"
      content = "Sample monthly backup - infrequently accessed data"
    }
  } : {}

  bucket       = aws_s3_bucket.storage_optimization.id
  key          = each.value.key
  content      = each.value.content
  content_type = "application/octet-stream"

  tags = merge(local.common_tags, {
    DataType    = "infrequently-accessed"
    Description = "Sample data for testing lifecycle policies"
  })
}

resource "aws_s3_object" "sample_archive" {
  for_each = var.create_sample_data ? {
    "compliance-archive" = {
      key     = "data/archive/compliance-archive-2023.zip"
      content = "Sample compliance archive - long-term storage data"
    }
    "historical-data" = {
      key     = "data/archive/historical-data-2023.db"
      content = "Sample historical database - long-term storage data"
    }
  } : {}

  bucket       = aws_s3_bucket.storage_optimization.id
  key          = each.value.key
  content      = each.value.content
  content_type = "application/octet-stream"

  tags = merge(local.common_tags, {
    DataType    = "archive"
    Description = "Sample data for testing lifecycle policies"
  })
}

# =============================================================================
# SNS Topic for Budget Alerts (Optional)
# =============================================================================
# Create SNS topic for enhanced budget notifications
resource "aws_sns_topic" "budget_alerts" {
  count = var.enable_enhanced_notifications ? 1 : 0
  name  = "s3-storage-cost-alerts-${local.random_suffix}"

  tags = merge(local.common_tags, {
    Description = "SNS topic for S3 storage cost budget alerts"
  })
}

# SNS topic subscription for email notifications
resource "aws_sns_topic_subscription" "budget_email_alerts" {
  count     = var.enable_enhanced_notifications ? length(var.budget_alert_emails) : 0
  topic_arn = aws_sns_topic.budget_alerts[0].arn
  protocol  = "email"
  endpoint  = var.budget_alert_emails[count.index]
}

# =============================================================================
# CloudWatch Alarms (Optional)
# =============================================================================
# Create CloudWatch alarm for storage size threshold
resource "aws_cloudwatch_metric_alarm" "storage_size_alarm" {
  count = var.enable_storage_alarms ? 1 : 0

  alarm_name          = "s3-storage-size-alarm-${local.random_suffix}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "BucketSizeBytes"
  namespace           = "AWS/S3"
  period              = "86400"
  statistic           = "Average"
  threshold           = var.storage_size_alarm_threshold
  alarm_description   = "This metric monitors S3 bucket size"
  alarm_actions       = var.enable_enhanced_notifications ? [aws_sns_topic.budget_alerts[0].arn] : []

  dimensions = {
    BucketName  = aws_s3_bucket.storage_optimization.id
    StorageType = "AllStorageTypes"
  }

  tags = merge(local.common_tags, {
    Description = "CloudWatch alarm for S3 storage size monitoring"
  })
}