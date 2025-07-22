# Main Terraform configuration for real-time analytics dashboards
# Creates a complete streaming analytics pipeline with Kinesis, Flink, S3, and QuickSight integration

# Get current AWS account ID and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Common naming convention for all resources
  name_prefix = "${var.project_name}-${var.environment}"
  name_suffix = random_id.suffix.hex
  
  # Common tags applied to all resources
  common_tags = merge(
    {
      Environment = var.environment
      Project     = var.project_name
      ManagedBy   = "terraform"
      Purpose     = "streaming-analytics"
    },
    var.additional_tags
  )
}

# S3 bucket for storing processed analytics data
# This bucket receives aggregated data from the Flink application
resource "aws_s3_bucket" "analytics_results" {
  bucket = "${local.name_prefix}-results-${local.name_suffix}"
  
  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-results-${local.name_suffix}"
    Purpose     = "analytics-data-storage"
    Component   = "storage"
  })
}

# S3 bucket versioning for analytics data
resource "aws_s3_bucket_versioning" "analytics_results" {
  bucket = aws_s3_bucket.analytics_results.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "analytics_results" {
  count  = var.enable_server_side_encryption ? 1 : 0
  bucket = aws_s3_bucket.analytics_results.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# S3 bucket public access block for security
resource "aws_s3_bucket_public_access_block" "analytics_results" {
  bucket = aws_s3_bucket.analytics_results.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 lifecycle configuration for cost optimization
resource "aws_s3_bucket_lifecycle_configuration" "analytics_results" {
  count      = var.s3_lifecycle_enabled ? 1 : 0
  bucket     = aws_s3_bucket.analytics_results.id
  depends_on = [aws_s3_bucket_versioning.analytics_results]

  rule {
    id     = "analytics_data_lifecycle"
    status = "Enabled"

    # Transition to Infrequent Access
    transition {
      days          = var.s3_transition_to_ia_days
      storage_class = "STANDARD_IA"
    }

    # Transition to Glacier
    transition {
      days          = var.s3_transition_to_glacier_days
      storage_class = "GLACIER"
    }

    # Expire objects if expiration is enabled
    dynamic "expiration" {
      for_each = var.s3_expiration_days > 0 ? [1] : []
      content {
        days = var.s3_expiration_days
      }
    }

    # Clean up incomplete multipart uploads
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# S3 bucket for storing Flink application code
resource "aws_s3_bucket" "flink_code" {
  bucket = "${local.name_prefix}-flink-code-${local.name_suffix}"
  
  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-flink-code-${local.name_suffix}"
    Purpose     = "flink-application-code"
    Component   = "storage"
  })
}

# S3 bucket versioning for Flink code
resource "aws_s3_bucket_versioning" "flink_code" {
  bucket = aws_s3_bucket.flink_code.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket server-side encryption for Flink code
resource "aws_s3_bucket_server_side_encryption_configuration" "flink_code" {
  count  = var.enable_server_side_encryption ? 1 : 0
  bucket = aws_s3_bucket.flink_code.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# S3 bucket public access block for Flink code bucket
resource "aws_s3_bucket_public_access_block" "flink_code" {
  bucket = aws_s3_bucket.flink_code.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Kinesis Data Stream for ingesting streaming data
# Multiple shards enable parallel processing and higher throughput
resource "aws_kinesis_stream" "analytics_stream" {
  name                = "${local.name_prefix}-stream-${local.name_suffix}"
  shard_count         = var.kinesis_shard_count
  retention_period    = var.kinesis_retention_period
  shard_level_metrics = var.enable_enhanced_monitoring ? ["IncomingRecords", "OutgoingRecords"] : []

  # Enable server-side encryption
  dynamic "encryption_type" {
    for_each = var.enable_server_side_encryption ? [1] : []
    content {
      encryption_type = "KMS"
      key_id          = "alias/aws/kinesis"
    }
  }

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-stream-${local.name_suffix}"
    Purpose     = "data-ingestion"
    Component   = "streaming"
  })
}

# IAM role for Managed Service for Apache Flink
# This role allows the Flink application to access Kinesis, S3, and CloudWatch
resource "aws_iam_role" "flink_analytics_role" {
  name = "${local.name_prefix}-flink-role-${local.name_suffix}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "kinesisanalytics.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-flink-role-${local.name_suffix}"
    Purpose     = "flink-execution"
    Component   = "iam"
  })
}

# IAM policy for Flink application permissions
# Grants necessary permissions for stream processing operations
resource "aws_iam_role_policy" "flink_analytics_policy" {
  name = "FlinkAnalyticsPolicy"
  role = aws_iam_role.flink_analytics_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kinesis:DescribeStream",
          "kinesis:GetShardIterator",
          "kinesis:GetRecords",
          "kinesis:ListShards"
        ]
        Resource = aws_kinesis_stream.analytics_stream.arn
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = [
          "${aws_s3_bucket.analytics_results.arn}/*",
          "${aws_s3_bucket.flink_code.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.analytics_results.arn,
          aws_s3_bucket.flink_code.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
      }
    ]
  })
}

# CloudWatch Log Group for Flink application logs
resource "aws_cloudwatch_log_group" "flink_application" {
  name              = "/aws/kinesis-analytics/${local.name_prefix}-app-${local.name_suffix}"
  retention_in_days = var.cloudwatch_log_retention_days

  tags = merge(local.common_tags, {
    Name        = "/aws/kinesis-analytics/${local.name_prefix}-app-${local.name_suffix}"
    Purpose     = "flink-application-logs"
    Component   = "monitoring"
  })
}

# Managed Service for Apache Flink Application
# This creates the streaming analytics application that processes data from Kinesis
resource "aws_kinesisanalyticsv2_application" "analytics_app" {
  name                   = "${local.name_prefix}-app-${local.name_suffix}"
  runtime_environment    = "FLINK-1_18"
  service_execution_role = aws_iam_role.flink_analytics_role.arn
  description            = "Real-time analytics application for streaming data processing"

  # Application code configuration
  # Points to the JAR file in S3 containing the Flink application
  application_configuration {
    application_code_configuration {
      code_content {
        s3_content_location {
          bucket_arn = aws_s3_bucket.flink_code.arn
          file_key   = var.flink_jar_key
        }
      }
      code_content_type = "ZIPFILE"
    }

    # Environment properties for the Flink application
    # These properties are passed to the application at runtime
    environment_properties {
      property_group {
        property_group_id = "kinesis.analytics.flink.run.options"
        property_map = {
          "input.stream.name" = aws_kinesis_stream.analytics_stream.name
          "aws.region"        = data.aws_region.current.name
          "s3.path"          = "s3://${aws_s3_bucket.analytics_results.bucket}/analytics-results/"
        }
      }
    }

    # Flink application configuration
    flink_application_configuration {
      # Checkpoint configuration for fault tolerance
      checkpoint_configuration {
        configuration_type = "DEFAULT"
      }

      # Monitoring configuration
      monitoring_configuration {
        configuration_type = "DEFAULT"
        log_level         = var.flink_log_level
        metrics_level     = var.flink_metrics_level
      }

      # Parallelism configuration for scaling
      parallelism_configuration {
        configuration_type   = "DEFAULT"
        parallelism         = var.flink_parallelism
        parallelism_per_kpu = var.flink_parallelism_per_kpu
        auto_scaling_enabled = var.flink_auto_scaling_enabled
      }
    }
  }

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-app-${local.name_suffix}"
    Purpose     = "stream-processing"
    Component   = "analytics"
  })

  depends_on = [
    aws_cloudwatch_log_group.flink_application,
    aws_iam_role_policy.flink_analytics_policy
  ]
}

# S3 object for QuickSight manifest file
# This manifest file helps QuickSight discover and process the analytics data
resource "aws_s3_object" "quicksight_manifest" {
  bucket = aws_s3_bucket.analytics_results.bucket
  key    = "quicksight-manifest.json"
  
  content = jsonencode({
    fileLocations = [
      {
        URIPrefixes = [
          "s3://${aws_s3_bucket.analytics_results.bucket}/analytics-results/"
        ]
      }
    ]
    globalUploadSettings = {
      format = "JSON"
    }
  })

  content_type = "application/json"

  tags = merge(local.common_tags, {
    Name        = "quicksight-manifest.json"
    Purpose     = "quicksight-configuration"
    Component   = "visualization"
  })
}

# CloudWatch Dashboard for monitoring the analytics pipeline
resource "aws_cloudwatch_dashboard" "analytics_dashboard" {
  dashboard_name = "${local.name_prefix}-monitoring-${local.name_suffix}"

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
            ["AWS/Kinesis", "IncomingRecords", "StreamName", aws_kinesis_stream.analytics_stream.name],
            [".", "OutgoingRecords", ".", "."],
            [".", "IncomingBytes", ".", "."],
            [".", "OutgoingBytes", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "Kinesis Stream Metrics"
          period  = 300
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
            ["AWS/KinesisAnalytics", "KPUs", "Application", aws_kinesisanalyticsv2_application.analytics_app.name],
            [".", "Uptime", ".", "."],
            [".", "downtime", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "Flink Application Metrics"
          period  = 300
        }
      }
    ]
  })
}

# SNS topic for alerts and notifications
resource "aws_sns_topic" "analytics_alerts" {
  name = "${local.name_prefix}-alerts-${local.name_suffix}"

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-alerts-${local.name_suffix}"
    Purpose     = "monitoring-alerts"
    Component   = "monitoring"
  })
}

# CloudWatch alarm for Kinesis stream errors
resource "aws_cloudwatch_metric_alarm" "kinesis_errors" {
  alarm_name          = "${local.name_prefix}-kinesis-errors-${local.name_suffix}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "PutRecord.Errors"
  namespace           = "AWS/Kinesis"
  period              = "300"
  statistic           = "Sum"
  threshold           = "10"
  alarm_description   = "This metric monitors kinesis errors"
  alarm_actions       = [aws_sns_topic.analytics_alerts.arn]

  dimensions = {
    StreamName = aws_kinesis_stream.analytics_stream.name
  }

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-kinesis-errors-${local.name_suffix}"
    Purpose     = "error-monitoring"
    Component   = "monitoring"
  })
}

# CloudWatch alarm for Flink application downtime
resource "aws_cloudwatch_metric_alarm" "flink_downtime" {
  alarm_name          = "${local.name_prefix}-flink-downtime-${local.name_suffix}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "downtime"
  namespace           = "AWS/KinesisAnalytics"
  period              = "300"
  statistic           = "Maximum"
  threshold           = "0"
  alarm_description   = "This metric monitors flink application downtime"
  alarm_actions       = [aws_sns_topic.analytics_alerts.arn]

  dimensions = {
    Application = aws_kinesisanalyticsv2_application.analytics_app.name
  }

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-flink-downtime-${local.name_suffix}"
    Purpose     = "availability-monitoring"
    Component   = "monitoring"
  })
}