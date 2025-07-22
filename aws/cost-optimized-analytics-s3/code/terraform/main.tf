# Data sources for current AWS account and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for computed names and configurations
locals {
  bucket_name           = var.bucket_name_suffix != "" ? "${var.project_name}-${var.bucket_name_suffix}-${random_id.suffix.hex}" : "${var.project_name}-${random_id.suffix.hex}"
  glue_database_name    = var.glue_database_name != "" ? var.glue_database_name : "analytics_database_${random_id.suffix.hex}"
  athena_workgroup_name = var.athena_workgroup_name != "" ? var.athena_workgroup_name : "cost-optimized-workgroup-${random_id.suffix.hex}"
  
  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Recipe      = "cost-optimized-analytics-s3-intelligent-tiering"
    },
    var.additional_tags
  )
}

# S3 bucket for analytics data with intelligent tiering
resource "aws_s3_bucket" "analytics_bucket" {
  bucket = local.bucket_name

  tags = merge(local.common_tags, {
    Name        = local.bucket_name
    Description = "S3 bucket for cost-optimized analytics with intelligent tiering"
  })
}

# S3 bucket versioning configuration
resource "aws_s3_bucket_versioning" "analytics_bucket_versioning" {
  count  = var.enable_versioning ? 1 : 0
  bucket = aws_s3_bucket.analytics_bucket.id
  
  versioning_configuration {
    status     = "Enabled"
    mfa_delete = var.enable_mfa_delete ? "Enabled" : "Disabled"
  }
}

# S3 bucket server-side encryption configuration
resource "aws_s3_bucket_server_side_encryption_configuration" "analytics_bucket_encryption" {
  bucket = aws_s3_bucket.analytics_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# S3 bucket public access block (security best practice)
resource "aws_s3_bucket_public_access_block" "analytics_bucket_pab" {
  bucket = aws_s3_bucket.analytics_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 Intelligent-Tiering configuration with archive access tiers
resource "aws_s3_bucket_intelligent_tiering_configuration" "analytics_intelligent_tiering" {
  bucket = aws_s3_bucket.analytics_bucket.id
  name   = "cost-optimization-config"
  status = "Enabled"

  # Filter to apply intelligent tiering to specific prefix
  filter {
    prefix = var.intelligent_tiering_prefix
  }

  # Archive Access tier (after 90+ days of no access)
  tiering {
    access_tier = "ARCHIVE_ACCESS"
    days        = var.archive_access_days
  }

  # Deep Archive Access tier (after 180+ days of no access)
  tiering {
    access_tier = "DEEP_ARCHIVE_ACCESS"
    days        = var.deep_archive_access_days
  }
}

# S3 bucket lifecycle configuration for automatic transitions
resource "aws_s3_bucket_lifecycle_configuration" "analytics_lifecycle" {
  depends_on = [aws_s3_bucket_versioning.analytics_bucket_versioning]
  bucket     = aws_s3_bucket.analytics_bucket.id

  rule {
    id     = "intelligent-tiering-transition"
    status = "Enabled"

    filter {
      prefix = var.intelligent_tiering_prefix
    }

    # Transition to Intelligent-Tiering immediately
    transition {
      days          = 0
      storage_class = "INTELLIGENT_TIERING"
    }

    # Clean up incomplete multipart uploads
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  # Handle non-current versions (if versioning is enabled)
  dynamic "rule" {
    for_each = var.enable_versioning ? [1] : []
    
    content {
      id     = "cleanup-old-versions"
      status = "Enabled"

      noncurrent_version_transition {
        noncurrent_days = 30
        storage_class   = "STANDARD_IA"
      }

      noncurrent_version_transition {
        noncurrent_days = 60
        storage_class   = "GLACIER"
      }

      noncurrent_version_expiration {
        noncurrent_days = 365
      }
    }
  }
}

# AWS Glue Database for analytics metadata
resource "aws_glue_catalog_database" "analytics_database" {
  name        = local.glue_database_name
  description = "Cost-optimized analytics database for S3 data"

  tags = merge(local.common_tags, {
    Name        = local.glue_database_name
    Description = "Glue catalog database for analytics data"
  })
}

# AWS Glue Table for transaction logs
resource "aws_glue_catalog_table" "transaction_logs" {
  name          = var.glue_table_name
  database_name = aws_glue_catalog_database.analytics_database.name
  description   = "Table for transaction log analytics data"

  table_type = "EXTERNAL_TABLE"

  parameters = {
    "classification"                   = "csv"
    "delimiter"                       = ","
    "skip.header.line.count"          = "0"
    "serialization.format"            = ","
    "field.delim"                     = ","
    "projection.enabled"              = "false"
    "storage.location.template"       = "s3://${aws_s3_bucket.analytics_bucket.bucket}/${var.intelligent_tiering_prefix}"
  }

  storage_descriptor {
    location      = "s3://${aws_s3_bucket.analytics_bucket.bucket}/${var.intelligent_tiering_prefix}"
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"

    ser_de_info {
      serialization_library = "org.apache.hadoop.hive.serde2.lazy.LazySimpleSerDe"
      parameters = {
        "field.delim" = ","
      }
    }

    columns {
      name = "timestamp"
      type = "string"
    }

    columns {
      name = "user_id"
      type = "string"
    }

    columns {
      name = "transaction_id"
      type = "string"
    }

    columns {
      name = "amount"
      type = "string"
    }
  }
}

# S3 bucket for Athena query results
resource "aws_s3_bucket" "athena_results" {
  bucket = "${local.bucket_name}-athena-results"

  tags = merge(local.common_tags, {
    Name        = "${local.bucket_name}-athena-results"
    Description = "S3 bucket for Athena query results"
  })
}

# Athena query results bucket encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "athena_results_encryption" {
  bucket = aws_s3_bucket.athena_results.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# Athena query results bucket public access block
resource "aws_s3_bucket_public_access_block" "athena_results_pab" {
  bucket = aws_s3_bucket.athena_results.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Athena workgroup with cost controls
resource "aws_athena_workgroup" "analytics_workgroup" {
  name        = local.athena_workgroup_name
  description = "Cost-optimized workgroup for analytics queries"
  state       = "ENABLED"

  configuration {
    enforce_workgroup_configuration    = var.athena_enforce_workgroup_config
    publish_cloudwatch_metrics         = true
    bytes_scanned_cutoff_per_query     = var.athena_query_limit_bytes

    result_configuration {
      output_location = "s3://${aws_s3_bucket.athena_results.bucket}/"
      
      encryption_configuration {
        encryption_option = "SSE_S3"
      }
    }

    engine_version {
      selected_engine_version = "AUTO"
    }
  }

  tags = merge(local.common_tags, {
    Name        = local.athena_workgroup_name
    Description = "Athena workgroup for cost-optimized analytics"
  })
}

# CloudWatch Dashboard for S3 cost monitoring
resource "aws_cloudwatch_dashboard" "s3_cost_optimization" {
  count          = var.enable_cloudwatch_dashboard ? 1 : 0
  dashboard_name = "S3-Cost-Optimization-${random_id.suffix.hex}"

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
            ["AWS/S3", "BucketSizeBytes", "BucketName", aws_s3_bucket.analytics_bucket.bucket, "StorageType", "IntelligentTieringFAStorage"],
            [".", ".", ".", ".", ".", "IntelligentTieringIAStorage"],
            [".", ".", ".", ".", ".", "IntelligentTieringAAStorage"],
            [".", ".", ".", ".", ".", "IntelligentTieringAIAStorage"],
            [".", ".", ".", ".", ".", "IntelligentTieringDAAStorage"]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "S3 Intelligent-Tiering Storage Distribution"
          period  = 300
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
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["AWS/Athena", "DataScannedInBytes", "WorkGroup", aws_athena_workgroup.analytics_workgroup.name],
            [".", "QueryExecutionTime", ".", "."],
            [".", "ProcessedBytes", ".", "."]
          ]
          view   = "timeSeries"
          region = data.aws_region.current.name
          title  = "Athena Query Performance Metrics"
          period = 300
          stat   = "Sum"
        }
      }
    ]
  })
}

# Cost Anomaly Detection for S3 services
resource "aws_ce_anomaly_detector" "s3_cost_anomaly" {
  count        = var.enable_cost_anomaly_detection ? 1 : 0
  name         = "S3-Cost-Anomaly-${random_id.suffix.hex}"
  monitor_type = "DIMENSIONAL"

  specification = jsonencode({
    Dimension = "SERVICE"
    Values    = ["Amazon Simple Storage Service"]
  })

  tags = merge(local.common_tags, {
    Name        = "S3-Cost-Anomaly-${random_id.suffix.hex}"
    Description = "Cost anomaly detection for S3 services"
  })
}

# Cost Anomaly Detection Subscription (optional email notifications)
resource "aws_ce_anomaly_subscription" "s3_cost_anomaly_subscription" {
  count     = var.enable_cost_anomaly_detection ? 1 : 0
  name      = "S3-Cost-Anomaly-Subscription-${random_id.suffix.hex}"
  frequency = "DAILY"
  
  monitor_arn_list = [
    aws_ce_anomaly_detector.s3_cost_anomaly[0].arn
  ]

  threshold_expression {
    and {
      dimension {
        key           = "ANOMALY_TOTAL_IMPACT_ABSOLUTE"
        values        = [tostring(var.anomaly_detection_threshold)]
        match_options = ["GREATER_THAN_OR_EQUAL"]
      }
    }
  }

  subscriber {
    type    = "EMAIL"
    address = "admin@example.com"  # Replace with actual email address
  }

  tags = merge(local.common_tags, {
    Name        = "S3-Cost-Anomaly-Subscription-${random_id.suffix.hex}"
    Description = "Email subscription for S3 cost anomaly alerts"
  })

  depends_on = [aws_ce_anomaly_detector.s3_cost_anomaly]
}