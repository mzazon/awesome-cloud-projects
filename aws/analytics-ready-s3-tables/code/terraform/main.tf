# ==============================================================================
# Analytics-Ready Data Storage with S3 Tables
# ==============================================================================
# This configuration creates an analytics-ready data storage solution using
# Amazon S3 Tables with Apache Iceberg format, integrated with AWS analytics
# services for high-performance query capabilities.

# ==============================================================================
# Data Sources
# ==============================================================================

# Get current AWS region
data "aws_region" "current" {}

# Get current AWS account ID
data "aws_caller_identity" "current" {}

# Generate random suffix for globally unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# ==============================================================================
# S3 Athena Results Bucket
# ==============================================================================

# Create S3 bucket for Athena query results with encryption
resource "aws_s3_bucket" "athena_results" {
  bucket = "athena-results-${random_string.suffix.result}"

  tags = merge(var.common_tags, {
    Name        = "athena-results-${random_string.suffix.result}"
    Description = "S3 bucket for Athena query results storage"
    Component   = "Analytics"
  })
}

# Configure server-side encryption for Athena results bucket
resource "aws_s3_bucket_server_side_encryption_configuration" "athena_results" {
  bucket = aws_s3_bucket.athena_results.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# Block public access to Athena results bucket
resource "aws_s3_bucket_public_access_block" "athena_results" {
  bucket = aws_s3_bucket.athena_results.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Configure versioning for Athena results bucket
resource "aws_s3_bucket_versioning" "athena_results" {
  bucket = aws_s3_bucket.athena_results.id
  versioning_configuration {
    status = "Enabled"
  }
}

# ==============================================================================
# S3 Tables Infrastructure
# ==============================================================================

# Create S3 Table Bucket for analytics storage
# Table buckets are purpose-built for Apache Iceberg tabular data with
# automatic optimization, metadata management, and maintenance capabilities
resource "aws_s3tables_table_bucket" "analytics" {
  name = "${var.table_bucket_prefix}-${random_string.suffix.result}"

  # Configure encryption with AES256 for cost-effective security
  encryption_configuration {
    sse_algorithm = "AES256"
  }

  # Enable automatic maintenance for optimal performance
  maintenance_configuration {
    iceberg_unreferenced_file_removal {
      status = "enabled"
      settings {
        unreferenced_days = var.unreferenced_file_cleanup_days
        non_current_days  = var.non_current_file_cleanup_days
      }
    }
  }

  tags = merge(var.common_tags, {
    Name        = "${var.table_bucket_prefix}-${random_string.suffix.result}"
    Description = "S3 Table Bucket for analytics-ready data storage"
    Component   = "Analytics"
    Format      = "Iceberg"
  })
}

# Create namespace for logical organization of analytics tables
# Namespaces provide database-like organization and access control
resource "aws_s3tables_namespace" "analytics_data" {
  namespace        = var.namespace_name
  table_bucket_arn = aws_s3tables_table_bucket.analytics.arn

  depends_on = [aws_s3tables_table_bucket.analytics]
}

# Create customer events table with optimized schema
# This Iceberg table supports ACID transactions, schema evolution, and time travel
resource "aws_s3tables_table" "customer_events" {
  name             = var.sample_table_name
  namespace        = aws_s3tables_namespace.analytics_data.namespace
  table_bucket_arn = aws_s3tables_table_bucket.analytics.arn
  format           = "ICEBERG"

  # Configure automatic maintenance for optimal query performance
  maintenance_configuration {
    # Enable automatic file compaction for better query performance
    iceberg_compaction {
      status = "enabled"
      settings {
        target_file_size_mb = var.target_file_size_mb
      }
    }

    # Enable snapshot management for data versioning and cleanup
    iceberg_snapshot_management {
      status = "enabled"
      settings {
        max_snapshot_age_hours = var.max_snapshot_age_hours
        min_snapshots_to_keep  = var.min_snapshots_to_keep
      }
    }
  }

  # Define optimized table schema for customer events analytics
  metadata {
    iceberg {
      schema {
        # Unique identifier for each event
        field {
          name     = "event_id"
          type     = "string"
          required = true
        }

        # Customer identifier for analytics grouping
        field {
          name     = "customer_id"
          type     = "string"
          required = true
        }

        # Type of customer event for categorization
        field {
          name     = "event_type"
          type     = "string"
          required = true
        }

        # Precise timestamp for temporal analytics
        field {
          name     = "event_timestamp"
          type     = "timestamp"
          required = true
        }

        # Product category for dimensional analysis
        field {
          name     = "product_category"
          type     = "string"
          required = false
        }

        # Monetary amount for financial analytics
        field {
          name     = "amount"
          type     = "decimal(10,2)"
          required = false
        }

        # Session identifier for user journey analytics
        field {
          name     = "session_id"
          type     = "string"
          required = false
        }

        # User agent for device/browser analytics
        field {
          name     = "user_agent"
          type     = "string"
          required = false
        }

        # Date partition for efficient query performance
        field {
          name     = "event_date"
          type     = "date"
          required = true
        }
      }
    }
  }

  depends_on = [aws_s3tables_namespace.analytics_data]
}

# ==============================================================================
# IAM Policy for Analytics Services Integration
# ==============================================================================

# Create IAM policy document for AWS Glue service access to S3 Tables
data "aws_iam_policy_document" "s3_tables_analytics_policy" {
  # Allow AWS Glue to read table metadata for catalog integration
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["glue.amazonaws.com"]
    }
    actions = [
      "s3tables:GetTable",
      "s3tables:GetTableMetadata",
      "s3tables:ListTables"
    ]
    resources = [
      aws_s3tables_table_bucket.analytics.arn,
      "${aws_s3tables_table_bucket.analytics.arn}/*"
    ]
  }

  # Allow other AWS analytics services access when needed
  dynamic "statement" {
    for_each = var.additional_analytics_services
    content {
      effect = "Allow"
      principals {
        type        = "Service"
        identifiers = [statement.value]
      }
      actions = [
        "s3tables:GetTable",
        "s3tables:GetTableMetadata"
      ]
      resources = [
        aws_s3tables_table_bucket.analytics.arn,
        "${aws_s3tables_table_bucket.analytics.arn}/*"
      ]
    }
  }
}

# Apply the analytics services policy to the table bucket
resource "aws_s3tables_table_bucket_policy" "analytics_integration" {
  table_bucket_arn = aws_s3tables_table_bucket.analytics.arn
  resource_policy  = data.aws_iam_policy_document.s3_tables_analytics_policy.json

  depends_on = [aws_s3tables_table_bucket.analytics]
}

# ==============================================================================
# Amazon Athena Configuration
# ==============================================================================

# Create dedicated Athena workgroup for S3 Tables queries
# Workgroups provide query execution settings, cost controls, and result management
resource "aws_athena_workgroup" "s3_tables" {
  name        = var.athena_workgroup_name
  description = "Athena workgroup for S3 Tables analytics queries with optimized configuration"
  state       = "ENABLED"

  configuration {
    # Enforce workgroup settings for consistent query execution
    enforce_workgroup_configuration = true

    # Enable CloudWatch metrics for query monitoring
    publish_cloudwatch_metrics_enabled = true

    # Configure query result storage with encryption
    result_configuration {
      output_location = "s3://${aws_s3_bucket.athena_results.bucket}/query-results/"

      encryption_configuration {
        encryption_option = "SSE_S3"
      }
    }

    # Set data usage limits for cost control (1GB default)
    bytes_scanned_cutoff_per_query = var.athena_bytes_scanned_cutoff

    # Configure latest Athena engine for optimal S3 Tables performance
    engine_version {
      selected_engine_version = "Athena engine version 3"
    }
  }

  tags = merge(var.common_tags, {
    Name        = var.athena_workgroup_name
    Description = "Athena workgroup for S3 Tables analytics"
    Component   = "Analytics"
    Service     = "Athena"
  })

  depends_on = [
    aws_s3_bucket.athena_results,
    aws_s3_bucket_server_side_encryption_configuration.athena_results
  ]
}

# ==============================================================================
# AWS Glue Data Catalog Integration
# ==============================================================================

# Create Glue database for S3 Tables integration
# This enables automatic table discovery and unified metadata management
resource "aws_glue_catalog_database" "s3_tables" {
  name        = var.glue_database_name
  description = "Glue Data Catalog database for S3 Tables integration"

  # Configure S3 Tables integration parameters
  parameters = {
    "s3_tables_integration" = "enabled"
    "namespace"             = var.namespace_name
    "table_bucket_arn"      = aws_s3tables_table_bucket.analytics.arn
  }

  tags = merge(var.common_tags, {
    Name        = var.glue_database_name
    Description = "Glue database for S3 Tables analytics"
    Component   = "Analytics"
    Service     = "Glue"
  })

  depends_on = [
    aws_s3tables_table_bucket.analytics,
    aws_s3tables_namespace.analytics_data
  ]
}