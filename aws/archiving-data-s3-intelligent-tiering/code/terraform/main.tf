# Sustainable Data Archiving Solution with S3 Intelligent-Tiering
# This Terraform configuration creates a complete sustainable data archiving solution
# including S3 buckets with Intelligent-Tiering, lifecycle policies, Storage Lens analytics,
# and automated sustainability monitoring with Lambda functions.

# Data sources for current AWS account and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random string for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local values for consistent naming and configuration
locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.name
  
  # Generate unique bucket names
  archive_bucket_name   = "${var.project_name}-${random_string.suffix.result}${var.bucket_name_suffix != "" ? "-${var.bucket_name_suffix}" : ""}"
  analytics_bucket_name = "${var.project_name}-analytics-${random_string.suffix.result}${var.bucket_name_suffix != "" ? "-${var.bucket_name_suffix}" : ""}"
  
  # Common tags to be applied to all resources
  common_tags = merge(
    {
      Project             = "SustainableArchive"
      Environment         = var.environment
      Purpose             = "SustainableArchive"
      CostOptimization    = "Enabled"
      SustainabilityGoal  = "CarbonNeutral"
      ManagedBy          = "Terraform"
    },
    var.additional_tags
  )
}

# S3 Bucket for main archive storage with Intelligent-Tiering
resource "aws_s3_bucket" "archive" {
  bucket = local.archive_bucket_name

  tags = merge(local.common_tags, {
    Name = "Sustainable Archive Bucket"
    Type = "Primary Storage"
  })
}

# Enable versioning on the archive bucket for data protection
resource "aws_s3_bucket_versioning" "archive" {
  count  = var.enable_versioning ? 1 : 0
  bucket = aws_s3_bucket.archive.id
  
  versioning_configuration {
    status = "Enabled"
  }
}

# Configure server-side encryption for the archive bucket
resource "aws_s3_bucket_server_side_encryption_configuration" "archive" {
  bucket = aws_s3_bucket.archive.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# Block public access to the archive bucket
resource "aws_s3_bucket_public_access_block" "archive" {
  bucket = aws_s3_bucket.archive.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Primary S3 Intelligent-Tiering configuration for cost optimization
resource "aws_s3_bucket_intelligent_tiering_configuration" "primary" {
  bucket = aws_s3_bucket.archive.id
  name   = "SustainableArchiveConfig"

  status = "Enabled"

  # Apply to all objects in the bucket
  filter {
    prefix = ""
  }

  # Configure tiering behavior - objects transition automatically based on access patterns
  tiering {
    access_tier = "ARCHIVE_ACCESS"
    days        = 90
  }

  tiering {
    access_tier = "DEEP_ARCHIVE_ACCESS"
    days        = 180
  }
}

# Advanced Intelligent-Tiering configuration for long-term data
resource "aws_s3_bucket_intelligent_tiering_configuration" "advanced" {
  count  = var.enable_advanced_intelligent_tiering ? 1 : 0
  bucket = aws_s3_bucket.archive.id
  name   = "AdvancedSustainableConfig"

  status = "Enabled"

  # Apply only to objects with long-term prefix for deeper archiving
  filter {
    prefix = var.long_term_prefix
  }

  # More aggressive archiving for long-term data
  tiering {
    access_tier = "ARCHIVE_ACCESS"
    days        = 90
  }

  tiering {
    access_tier = "DEEP_ARCHIVE_ACCESS"
    days        = 180
  }
}

# Comprehensive lifecycle policy for sustainability optimization
resource "aws_s3_bucket_lifecycle_configuration" "archive" {
  bucket = aws_s3_bucket.archive.id

  # Primary lifecycle rule for sustainability optimization
  rule {
    id     = "SustainabilityOptimization"
    status = "Enabled"

    # Transition all new objects to Intelligent-Tiering immediately
    transition {
      days          = 0
      storage_class = "INTELLIGENT_TIERING"
    }

    # Manage non-current versions for cost optimization
    noncurrent_version_transition {
      noncurrent_days = var.lifecycle_noncurrent_version_glacier_days
      storage_class   = "GLACIER"
    }

    noncurrent_version_transition {
      noncurrent_days = var.lifecycle_noncurrent_version_deep_archive_days
      storage_class   = "DEEP_ARCHIVE"
    }

    # Clean up incomplete multipart uploads to reduce storage waste
    abort_incomplete_multipart_upload {
      days_after_initiation = var.multipart_upload_cleanup_days
    }
  }

  # Rule to delete old versions after retention period
  rule {
    id     = "DeleteOldVersions"
    status = "Enabled"

    noncurrent_version_expiration {
      noncurrent_days = var.lifecycle_noncurrent_version_expiration_days
    }
  }

  depends_on = [aws_s3_bucket_versioning.archive]
}

# S3 bucket for Storage Lens analytics and reports
resource "aws_s3_bucket" "analytics" {
  count  = var.enable_storage_lens ? 1 : 0
  bucket = local.analytics_bucket_name

  tags = merge(local.common_tags, {
    Name = "Storage Analytics Bucket"
    Type = "Analytics Storage"
  })
}

# Configure encryption for analytics bucket
resource "aws_s3_bucket_server_side_encryption_configuration" "analytics" {
  count  = var.enable_storage_lens ? 1 : 0
  bucket = aws_s3_bucket.analytics[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# Block public access to analytics bucket
resource "aws_s3_bucket_public_access_block" "analytics" {
  count  = var.enable_storage_lens ? 1 : 0
  bucket = aws_s3_bucket.analytics[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 Storage Lens configuration for comprehensive sustainability analytics
resource "aws_s3control_storage_lens_configuration" "sustainability" {
  count     = var.enable_storage_lens ? 1 : 0
  config_id = "SustainabilityMetrics"

  storage_lens_configuration {
    enabled = true

    # Account-level metrics with activity tracking
    account_level {
      activity_metrics {
        enabled = true
      }

      bucket_level {
        activity_metrics {
          enabled = true
        }

        prefix_level {
          storage_metrics {
            enabled = true
          }
        }
      }
    }

    # Include only our archive bucket for focused analysis
    include {
      buckets = [aws_s3_bucket.archive.arn]
    }

    # Export detailed reports to analytics bucket
    data_export {
      s3_bucket_destination {
        account_id                = local.account_id
        arn                      = aws_s3_bucket.analytics[0].arn
        format                   = "CSV"
        output_schema_version    = "V_1"
        prefix                   = var.storage_lens_export_prefix
      }
    }
  }
}

# IAM role for Lambda sustainability monitoring function
resource "aws_iam_role" "sustainability_monitor" {
  count = var.enable_sustainability_monitoring ? 1 : 0
  name  = "SustainabilityMonitorRole-${random_string.suffix.result}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "Sustainability Monitor Role"
    Type = "Lambda Execution Role"
  })
}

# IAM policy for Lambda sustainability monitoring function
resource "aws_iam_role_policy" "sustainability_monitor" {
  count = var.enable_sustainability_monitoring ? 1 : 0
  name  = "SustainabilityPermissions"
  role  = aws_iam_role.sustainability_monitor[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${local.region}:${local.account_id}:*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetBucketTagging",
          "s3:GetBucketLocation",
          "s3:ListBucket",
          "s3:GetObject",
          "s3:GetStorageLensConfiguration",
          "s3:ListStorageLensConfigurations",
          "s3control:GetStorageLensConfiguration",
          "s3control:ListStorageLensConfigurations"
        ]
        Resource = [
          aws_s3_bucket.archive.arn,
          "${aws_s3_bucket.archive.arn}/*",
          "arn:aws:s3:${local.region}:${local.account_id}:storage-lens/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:ListMetrics",
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
      }
    ]
  })
}

# Archive Lambda function code for sustainability monitoring
data "archive_file" "sustainability_monitor" {
  count       = var.enable_sustainability_monitoring ? 1 : 0
  type        = "zip"
  output_path = "${path.module}/sustainability_monitor.zip"
  
  source {
    content = templatefile("${path.module}/lambda_function.py", {
      archive_bucket = aws_s3_bucket.archive.bucket
    })
    filename = "lambda_function.py"
  }
}

# Lambda function for sustainability monitoring and carbon footprint calculation
resource "aws_lambda_function" "sustainability_monitor" {
  count            = var.enable_sustainability_monitoring ? 1 : 0
  filename         = data.archive_file.sustainability_monitor[0].output_path
  function_name    = "sustainability-archive-monitor-${random_string.suffix.result}"
  role            = aws_iam_role.sustainability_monitor[0].arn
  handler         = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.sustainability_monitor[0].output_base64sha256
  runtime         = "python3.9"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size

  environment {
    variables = {
      ARCHIVE_BUCKET = aws_s3_bucket.archive.bucket
      AWS_REGION     = local.region
    }
  }

  tags = merge(local.common_tags, {
    Name = "Sustainability Monitor Function"
    Type = "Monitoring Function"
  })
}

# CloudWatch Log Group for Lambda function
resource "aws_cloudwatch_log_group" "sustainability_monitor" {
  count             = var.enable_sustainability_monitoring ? 1 : 0
  name              = "/aws/lambda/${aws_lambda_function.sustainability_monitor[0].function_name}"
  retention_in_days = 14

  tags = merge(local.common_tags, {
    Name = "Sustainability Monitor Logs"
    Type = "Log Group"
  })
}

# EventBridge rule for scheduled sustainability monitoring
resource "aws_cloudwatch_event_rule" "sustainability_daily_check" {
  count               = var.enable_sustainability_monitoring ? 1 : 0
  name                = "sustainability-daily-check-${random_string.suffix.result}"
  description         = "Daily sustainability metrics collection"
  schedule_expression = var.monitoring_schedule

  tags = merge(local.common_tags, {
    Name = "Sustainability Daily Check"
    Type = "EventBridge Rule"
  })
}

# EventBridge target to invoke Lambda function
resource "aws_cloudwatch_event_target" "sustainability_lambda" {
  count     = var.enable_sustainability_monitoring ? 1 : 0
  rule      = aws_cloudwatch_event_rule.sustainability_daily_check[0].name
  target_id = "SustainabilityMonitorTarget"
  arn       = aws_lambda_function.sustainability_monitor[0].arn
}

# Lambda permission to allow EventBridge to invoke the function
resource "aws_lambda_permission" "allow_eventbridge" {
  count         = var.enable_sustainability_monitoring ? 1 : 0
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.sustainability_monitor[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.sustainability_daily_check[0].arn
}

# CloudWatch Dashboard for sustainability metrics visualization
resource "aws_cloudwatch_dashboard" "sustainability" {
  count          = var.enable_cloudwatch_dashboard ? 1 : 0
  dashboard_name = "SustainableArchive-${random_string.suffix.result}"

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
            ["SustainableArchive", "TotalStorageGB"],
            [".", "EstimatedMonthlyCarbonKg"]
          ]
          period = 3600
          stat   = "Average"
          region = local.region
          title  = "Storage & Carbon Metrics"
          view   = "timeSeries"
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
            ["SustainableArchive", "CarbonReductionPercentage"]
          ]
          period = 3600
          stat   = "Average"
          region = local.region
          title  = "Carbon Footprint Reduction"
          view   = "timeSeries"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "Sustainability Dashboard"
    Type = "CloudWatch Dashboard"
  })
}

# Sample data objects for testing intelligent tiering (optional)
resource "aws_s3_object" "sample_frequent" {
  count  = var.enable_sample_data ? 1 : 0
  bucket = aws_s3_bucket.archive.id
  key    = "active/frequent-data.txt"
  content = "Frequently accessed application data for testing intelligent tiering"
  content_type = "text/plain"

  tags = merge(local.common_tags, {
    Name        = "Sample Frequent Data"
    Type        = "Test Data"
    AccessType  = "Frequent"
  })
}

resource "aws_s3_object" "sample_archive" {
  count  = var.enable_sample_data ? 1 : 0
  bucket = aws_s3_bucket.archive.id
  key    = "documents/archive-doc-2023.pdf"
  content = "Document archive from 2023 for testing intelligent tiering"
  content_type = "application/pdf"

  tags = merge(local.common_tags, {
    Name        = "Sample Archive Document"
    Type        = "Test Data"
    AccessType  = "Archive"
  })
}

resource "aws_s3_object" "sample_long_term" {
  count  = var.enable_sample_data ? 1 : 0
  bucket = aws_s3_bucket.archive.id
  key    = "${var.long_term_prefix}backup-data.zip"
  content = "Long-term backup data for testing advanced intelligent tiering"
  content_type = "application/zip"

  tags = merge(local.common_tags, {
    Name        = "Sample Long-term Data"
    Type        = "Test Data"
    AccessType  = "LongTerm"
  })
}

# Lambda function source code for sustainability monitoring
resource "local_file" "lambda_source" {
  count    = var.enable_sustainability_monitoring ? 1 : 0
  filename = "${path.module}/lambda_function.py"
  content = templatefile("${path.module}/lambda_function.py.tpl", {
    archive_bucket = aws_s3_bucket.archive.bucket
  })
}