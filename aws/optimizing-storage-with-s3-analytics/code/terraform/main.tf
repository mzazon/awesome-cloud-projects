# Main Terraform configuration for S3 Inventory and Storage Analytics Reporting

# Data sources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Common naming convention
  name_prefix = "${var.project_name}-${var.environment}"
  name_suffix = random_id.suffix.hex
  
  # Resource names
  source_bucket_name = var.source_bucket_name != "" ? var.source_bucket_name : "${local.name_prefix}-source-${local.name_suffix}"
  dest_bucket_name   = "${local.name_prefix}-reports-${local.name_suffix}"
  
  # Configuration IDs
  inventory_config_id = "daily-inventory-config"
  analytics_config_id = "storage-class-analysis"
  
  # Common tags
  common_tags = merge({
    Project         = var.project_name
    Environment     = var.environment
    Recipe          = "s3-inventory-storage-analytics-reporting"
    CreatedBy       = "Terraform"
    SourceBucket    = local.source_bucket_name
    DestBucket      = local.dest_bucket_name
  }, var.additional_tags)
}

# ========================================
# S3 Buckets
# ========================================

# Source bucket (only created if name not provided)
resource "aws_s3_bucket" "source" {
  count  = var.source_bucket_name == "" ? 1 : 0
  bucket = local.source_bucket_name

  tags = merge(local.common_tags, {
    Name = "Source Bucket"
    Type = "SourceBucket"
  })
}

# Source bucket versioning
resource "aws_s3_bucket_versioning" "source" {
  count  = var.source_bucket_name == "" ? 1 : 0
  bucket = aws_s3_bucket.source[0].id
  
  versioning_configuration {
    status = "Enabled"
  }
}

# Source bucket server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "source" {
  count  = var.source_bucket_name == "" ? 1 : 0
  bucket = aws_s3_bucket.source[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# Destination bucket for reports
resource "aws_s3_bucket" "destination" {
  bucket = local.dest_bucket_name

  tags = merge(local.common_tags, {
    Name = "Analytics Reports Bucket"
    Type = "DestinationBucket"
  })
}

# Destination bucket versioning
resource "aws_s3_bucket_versioning" "destination" {
  bucket = aws_s3_bucket.destination.id
  
  versioning_configuration {
    status = "Enabled"
  }
}

# Destination bucket server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "destination" {
  bucket = aws_s3_bucket.destination.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# Destination bucket lifecycle configuration
resource "aws_s3_bucket_lifecycle_configuration" "destination" {
  bucket = aws_s3_bucket.destination.id

  rule {
    id     = "inventory-reports-lifecycle"
    status = "Enabled"

    filter {
      prefix = "inventory-reports/"
    }

    expiration {
      days = var.retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }

  rule {
    id     = "analytics-reports-lifecycle"
    status = "Enabled"

    filter {
      prefix = "analytics-reports/"
    }

    expiration {
      days = var.retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }

  rule {
    id     = "athena-results-lifecycle"
    status = "Enabled"

    filter {
      prefix = "athena-results/"
    }

    expiration {
      days = 30
    }
  }
}

# Destination bucket policy for S3 inventory service
resource "aws_s3_bucket_policy" "destination" {
  bucket = aws_s3_bucket.destination.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "InventoryDestinationBucketPolicy"
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.destination.arn}/*"
        Condition = {
          ArnLike = {
            "aws:SourceArn" = "arn:aws:s3:::${local.source_bucket_name}"
          }
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
            "s3:x-amz-acl"     = "bucket-owner-full-control"
          }
        }
      }
    ]
  })
}

# ========================================
# S3 Inventory Configuration
# ========================================

resource "aws_s3_bucket_inventory" "main" {
  bucket = local.source_bucket_name
  name   = local.inventory_config_id

  included_object_versions = var.inventory_included_object_versions

  schedule {
    frequency = var.inventory_frequency
  }

  optional_fields = [
    "Size",
    "LastModifiedDate", 
    "StorageClass",
    "ETag",
    "ReplicationStatus",
    "EncryptionStatus"
  ]

  destination {
    bucket {
      account_id     = data.aws_caller_identity.current.account_id
      bucket_arn     = aws_s3_bucket.destination.arn
      format         = "CSV"
      prefix         = "inventory-reports/"
    }
  }

  depends_on = [
    aws_s3_bucket_policy.destination
  ]
}

# ========================================
# S3 Storage Analytics Configuration
# ========================================

resource "aws_s3_bucket_analytics_configuration" "main" {
  bucket = local.source_bucket_name
  name   = local.analytics_config_id

  filter {
    prefix = var.storage_analytics_prefix
  }

  storage_class_analysis {
    data_export {
      output_schema_version = "V_1"
      
      destination {
        s3_bucket_destination {
          bucket_account_id = data.aws_caller_identity.current.account_id
          bucket_arn        = aws_s3_bucket.destination.arn
          format            = "CSV"
          prefix            = "analytics-reports/"
        }
      }
    }
  }
}

# ========================================
# Sample Data (if enabled)
# ========================================

# Sample objects for testing (only if creating new source bucket)
resource "aws_s3_object" "sample_data" {
  count = var.create_sample_data && var.source_bucket_name == "" ? 3 : 0
  
  bucket = aws_s3_bucket.source[0].id
  key    = [
    "data/sample-file.txt",
    "logs/access-log.txt", 
    "archive/old-data.txt"
  ][count.index]
  
  content = "Sample data for storage analytics - ${[
    "data file",
    "log file",
    "archive file"
  ][count.index]}"
  
  storage_class = count.index == 2 ? "STANDARD_IA" : "STANDARD"

  tags = merge(local.common_tags, {
    Type = "SampleData"
    Category = [
      "data",
      "logs", 
      "archive"
    ][count.index]
  })
}

# ========================================
# AWS Glue Database for Athena
# ========================================

resource "aws_glue_catalog_database" "inventory" {
  name        = var.athena_database_name
  description = "Database for S3 inventory analytics"

  tags = merge(local.common_tags, {
    Name = "S3 Inventory Database"
    Type = "GlueDatabase"
  })
}

# ========================================
# IAM Roles and Policies
# ========================================

# Lambda execution role
resource "aws_iam_role" "lambda_role" {
  count = var.enable_automated_reporting ? 1 : 0
  name  = "${local.name_prefix}-lambda-role-${local.name_suffix}"

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
    Name = "Lambda Execution Role"
    Type = "IAMRole"
  })
}

# Lambda policy for Athena and S3 access
resource "aws_iam_role_policy" "lambda_policy" {
  count = var.enable_automated_reporting ? 1 : 0
  name  = "${local.name_prefix}-lambda-policy"
  role  = aws_iam_role.lambda_role[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "athena:StartQueryExecution",
          "athena:GetQueryExecution", 
          "athena:GetQueryResults",
          "athena:StopQueryExecution"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.destination.arn,
          "${aws_s3_bucket.destination.arn}/*",
          "arn:aws:s3:::${local.source_bucket_name}",
          "arn:aws:s3:::${local.source_bucket_name}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "glue:GetDatabase",
          "glue:GetTable",
          "glue:GetPartitions"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# Attach basic Lambda execution policy
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  count      = var.enable_automated_reporting ? 1 : 0
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.lambda_role[0].name
}

# ========================================
# Lambda Function for Automated Reporting
# ========================================

# Create Lambda deployment package
data "archive_file" "lambda_zip" {
  count       = var.enable_automated_reporting ? 1 : 0
  type        = "zip"
  output_path = "/tmp/lambda-function-${local.name_suffix}.zip"
  
  source {
    content = templatefile("${path.module}/lambda-function.py.tpl", {
      athena_database = var.athena_database_name
      athena_table    = var.athena_table_name
      dest_bucket     = aws_s3_bucket.destination.id
    })
    filename = "lambda-function.py"
  }
}

# Lambda function
resource "aws_lambda_function" "analytics" {
  count = var.enable_automated_reporting ? 1 : 0
  
  filename         = data.archive_file.lambda_zip[0].output_path
  function_name    = "${local.name_prefix}-analytics-function-${local.name_suffix}"
  role            = aws_iam_role.lambda_role[0].arn
  handler         = "lambda-function.lambda_handler"
  source_code_hash = data.archive_file.lambda_zip[0].output_base64sha256
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size

  environment {
    variables = {
      ATHENA_DATABASE = var.athena_database_name
      ATHENA_TABLE    = var.athena_table_name
      DEST_BUCKET     = aws_s3_bucket.destination.id
      SOURCE_BUCKET   = local.source_bucket_name
    }
  }

  tags = merge(local.common_tags, {
    Name = "Storage Analytics Function"
    Type = "LambdaFunction"
  })
}

# Lambda log group
resource "aws_cloudwatch_log_group" "lambda_logs" {
  count             = var.enable_automated_reporting ? 1 : 0
  name              = "/aws/lambda/${aws_lambda_function.analytics[0].function_name}"
  retention_in_days = 14

  tags = merge(local.common_tags, {
    Name = "Lambda Log Group"
    Type = "CloudWatchLogGroup"
  })
}

# ========================================
# EventBridge Scheduling
# ========================================

# EventBridge rule for scheduled reporting
resource "aws_cloudwatch_event_rule" "schedule" {
  count               = var.enable_automated_reporting ? 1 : 0
  name                = "${local.name_prefix}-analytics-schedule-${local.name_suffix}"
  description         = "Schedule for storage analytics reporting"
  schedule_expression = var.reporting_schedule

  tags = merge(local.common_tags, {
    Name = "Analytics Schedule Rule"
    Type = "EventBridgeRule"
  })
}

# EventBridge target
resource "aws_cloudwatch_event_target" "lambda_target" {
  count     = var.enable_automated_reporting ? 1 : 0
  rule      = aws_cloudwatch_event_rule.schedule[0].name
  target_id = "StorageAnalyticsTarget"
  arn       = aws_lambda_function.analytics[0].arn
}

# Lambda permission for EventBridge
resource "aws_lambda_permission" "eventbridge" {
  count         = var.enable_automated_reporting ? 1 : 0
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.analytics[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.schedule[0].arn
}

# ========================================
# CloudWatch Dashboard
# ========================================

resource "aws_cloudwatch_dashboard" "storage_analytics" {
  count          = var.enable_cloudwatch_dashboard ? 1 : 0
  dashboard_name = "${local.name_prefix}-storage-analytics-${local.name_suffix}"

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
            ["AWS/S3", "BucketSizeBytes", "BucketName", local.source_bucket_name, "StorageType", "StandardStorage"],
            [".", ".", ".", ".", ".", "StandardIAStorage"],
            [".", ".", ".", ".", ".", "GlacierStorage"],
            [".", "NumberOfObjects", ".", ".", ".", "AllStorageTypes"]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "S3 Storage Metrics"
          period  = 86400
          stat    = "Average"
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
            ["AWS/S3", "AllRequests", "BucketName", local.source_bucket_name],
            [".", "GetRequests", ".", "."],
            [".", "PutRequests", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "S3 Request Metrics"
          period  = 3600
          stat    = "Sum"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "Storage Analytics Dashboard"
    Type = "CloudWatchDashboard"
  })
}

# ========================================
# Athena WorkGroup (optional)
# ========================================

resource "aws_athena_workgroup" "analytics" {
  name = "${local.name_prefix}-analytics-workgroup-${local.name_suffix}"

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true
    
    result_configuration {
      output_location = "s3://${aws_s3_bucket.destination.id}/athena-results/"
      
      encryption_configuration {
        encryption_option = "SSE_S3"
      }
    }
  }

  tags = merge(local.common_tags, {
    Name = "Analytics WorkGroup"
    Type = "AthenaWorkGroup"
  })
}