# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Data sources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  # Generate unique names for resources
  random_suffix            = random_string.suffix.result
  lambda_layer_name        = "${var.project_name}-shared-layer-${local.random_suffix}"
  custom_event_bus         = "${var.project_name}-event-bus-${local.random_suffix}"
  s3_bucket_raw           = "${var.project_name}-raw-data-${local.random_suffix}"
  s3_bucket_processed     = "${var.project_name}-processed-data-${local.random_suffix}"
  s3_bucket_quarantine    = "${var.project_name}-quarantine-data-${local.random_suffix}"
  dynamodb_metadata_table = "${var.project_name}-metadata-${local.random_suffix}"
  glue_database           = "${var.project_name}_catalog_${local.random_suffix}"
  
  # Common tags
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
    Recipe      = "advanced-serverless-data-lake-architecture"
  }
}

# ===== S3 BUCKETS =====

# S3 bucket for raw data ingestion
resource "aws_s3_bucket" "raw_data" {
  bucket        = local.s3_bucket_raw
  force_destroy = var.s3_force_destroy
  
  tags = merge(local.common_tags, {
    Name        = "Raw Data Bucket"
    Purpose     = "Data Lake Raw Storage"
    DataClass   = "Raw"
  })
}

# S3 bucket versioning for raw data
resource "aws_s3_bucket_versioning" "raw_data" {
  bucket = aws_s3_bucket.raw_data.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket server-side encryption for raw data
resource "aws_s3_bucket_server_side_encryption_configuration" "raw_data" {
  bucket = aws_s3_bucket.raw_data.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 bucket for processed data
resource "aws_s3_bucket" "processed_data" {
  bucket        = local.s3_bucket_processed
  force_destroy = var.s3_force_destroy
  
  tags = merge(local.common_tags, {
    Name        = "Processed Data Bucket"
    Purpose     = "Data Lake Processed Storage"
    DataClass   = "Processed"
  })
}

# S3 bucket versioning for processed data
resource "aws_s3_bucket_versioning" "processed_data" {
  bucket = aws_s3_bucket.processed_data.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket server-side encryption for processed data
resource "aws_s3_bucket_server_side_encryption_configuration" "processed_data" {
  bucket = aws_s3_bucket.processed_data.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 bucket for quarantine data
resource "aws_s3_bucket" "quarantine_data" {
  bucket        = local.s3_bucket_quarantine
  force_destroy = var.s3_force_destroy
  
  tags = merge(local.common_tags, {
    Name        = "Quarantine Data Bucket"
    Purpose     = "Data Lake Quarantine Storage"
    DataClass   = "Quarantine"
  })
}

# S3 bucket versioning for quarantine data
resource "aws_s3_bucket_versioning" "quarantine_data" {
  bucket = aws_s3_bucket.quarantine_data.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket server-side encryption for quarantine data
resource "aws_s3_bucket_server_side_encryption_configuration" "quarantine_data" {
  bucket = aws_s3_bucket.quarantine_data.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# ===== DYNAMODB TABLE =====

# DynamoDB table for metadata storage
resource "aws_dynamodb_table" "metadata" {
  name           = local.dynamodb_metadata_table
  billing_mode   = var.dynamodb_billing_mode
  hash_key       = "ProcessId"
  range_key      = "Timestamp"
  stream_enabled = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  attribute {
    name = "ProcessId"
    type = "S"
  }

  attribute {
    name = "Timestamp"
    type = "S"
  }

  tags = merge(local.common_tags, {
    Name    = "Metadata Table"
    Purpose = "Data Lake Metadata Storage"
  })
}

# ===== IAM ROLES AND POLICIES =====

# Lambda execution role
resource "aws_iam_role" "lambda_role" {
  name = "${var.project_name}-lambda-role-${local.random_suffix}"

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
  })
}

# Lambda role policy for comprehensive permissions
resource "aws_iam_role_policy" "lambda_policy" {
  name = "${var.project_name}-lambda-policy-${local.random_suffix}"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
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
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.raw_data.arn,
          "${aws_s3_bucket.raw_data.arn}/*",
          aws_s3_bucket.processed_data.arn,
          "${aws_s3_bucket.processed_data.arn}/*",
          aws_s3_bucket.quarantine_data.arn,
          "${aws_s3_bucket.quarantine_data.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:UpdateItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = aws_dynamodb_table.metadata.arn
      },
      {
        Effect = "Allow"
        Action = [
          "events:PutEvents"
        ]
        Resource = aws_cloudwatch_event_bus.custom_bus.arn
      },
      {
        Effect = "Allow"
        Action = [
          "glue:StartJobRun",
          "glue:GetJobRun",
          "glue:StartWorkflowRun",
          "glue:GetWorkflowRun"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords"
        ]
        Resource = "*"
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

# Glue service role
resource "aws_iam_role" "glue_role" {
  name = "${var.project_name}-glue-role-${local.random_suffix}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "glue.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "Glue Service Role"
  })
}

# Attach AWS managed policy for Glue service
resource "aws_iam_role_policy_attachment" "glue_service_role" {
  role       = aws_iam_role.glue_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

# Custom S3 policy for Glue
resource "aws_iam_role_policy" "glue_s3_policy" {
  name = "${var.project_name}-glue-s3-policy-${local.random_suffix}"
  role = aws_iam_role.glue_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.processed_data.arn,
          "${aws_s3_bucket.processed_data.arn}/*"
        ]
      }
    ]
  })
}

# ===== LAMBDA LAYER =====

# Create Lambda layer ZIP file with shared utilities
data "archive_file" "lambda_layer" {
  type        = "zip"
  output_path = "${path.module}/lambda-layer.zip"
  
  source {
    content = templatefile("${path.module}/lambda_layer_code.py", {})
    filename = "python/data_utils.py"
  }
  
  source {
    content = <<-EOT
pandas==1.5.3
numpy==1.24.3
boto3==1.26.137
jsonschema==4.17.3
requests==2.31.0
EOT
    filename = "python/requirements.txt"
  }
}

# Lambda layer for shared utilities
resource "aws_lambda_layer_version" "shared_layer" {
  filename                 = data.archive_file.lambda_layer.output_path
  layer_name               = local.lambda_layer_name
  description              = var.lambda_layer_description
  compatible_runtimes      = [var.lambda_runtime]
  compatible_architectures = ["x86_64", "arm64"]
  source_code_hash         = data.archive_file.lambda_layer.output_base64sha256

  depends_on = [data.archive_file.lambda_layer]
}

# ===== LAMBDA FUNCTIONS =====

# Data ingestion Lambda function
data "archive_file" "data_ingestion_lambda" {
  type        = "zip"
  output_path = "${path.module}/data-ingestion-lambda.zip"
  
  source {
    content = templatefile("${path.module}/lambda_ingestion_code.py", {
      metadata_table   = local.dynamodb_metadata_table
      custom_event_bus = local.custom_event_bus
      processed_bucket = local.s3_bucket_processed
    })
    filename = "lambda_function.py"
  }
}

resource "aws_lambda_function" "data_ingestion" {
  function_name    = "${var.project_name}-data-ingestion-${local.random_suffix}"
  filename         = data.archive_file.data_ingestion_lambda.output_path
  handler          = "lambda_function.lambda_handler"
  runtime          = var.lambda_runtime
  role             = aws_iam_role.lambda_role.arn
  timeout          = var.lambda_timeout
  memory_size      = var.lambda_memory_size
  source_code_hash = data.archive_file.data_ingestion_lambda.output_base64sha256

  layers = [aws_lambda_layer_version.shared_layer.arn]

  environment {
    variables = {
      METADATA_TABLE    = aws_dynamodb_table.metadata.name
      CUSTOM_EVENT_BUS  = aws_cloudwatch_event_bus.custom_bus.name
      PROCESSED_BUCKET  = aws_s3_bucket.processed_data.bucket
    }
  }

  tracing_config {
    mode = var.enable_xray_tracing ? "Active" : "PassThrough"
  }

  depends_on = [
    aws_iam_role_policy.lambda_policy,
    data.archive_file.data_ingestion_lambda,
    aws_lambda_layer_version.shared_layer
  ]

  tags = merge(local.common_tags, {
    Name = "Data Ingestion Function"
  })
}

# Data validation Lambda function
data "archive_file" "data_validation_lambda" {
  type        = "zip"
  output_path = "${path.module}/data-validation-lambda.zip"
  
  source {
    content = templatefile("${path.module}/lambda_validation_code.py", {
      metadata_table      = local.dynamodb_metadata_table
      custom_event_bus    = local.custom_event_bus
      processed_bucket    = local.s3_bucket_processed
      quarantine_bucket   = local.s3_bucket_quarantine
    })
    filename = "lambda_function.py"
  }
}

resource "aws_lambda_function" "data_validation" {
  function_name    = "${var.project_name}-data-validation-${local.random_suffix}"
  filename         = data.archive_file.data_validation_lambda.output_path
  handler          = "lambda_function.lambda_handler"
  runtime          = var.lambda_runtime
  role             = aws_iam_role.lambda_role.arn
  timeout          = var.lambda_timeout
  memory_size      = var.lambda_memory_size
  source_code_hash = data.archive_file.data_validation_lambda.output_base64sha256

  layers = [aws_lambda_layer_version.shared_layer.arn]

  environment {
    variables = {
      METADATA_TABLE      = aws_dynamodb_table.metadata.name
      CUSTOM_EVENT_BUS    = aws_cloudwatch_event_bus.custom_bus.name
      PROCESSED_BUCKET    = aws_s3_bucket.processed_data.bucket
      QUARANTINE_BUCKET   = aws_s3_bucket.quarantine_data.bucket
    }
  }

  tracing_config {
    mode = var.enable_xray_tracing ? "Active" : "PassThrough"
  }

  depends_on = [
    aws_iam_role_policy.lambda_policy,
    data.archive_file.data_validation_lambda,
    aws_lambda_layer_version.shared_layer
  ]

  tags = merge(local.common_tags, {
    Name = "Data Validation Function"
  })
}

# Quality monitoring Lambda function
data "archive_file" "quality_monitoring_lambda" {
  type        = "zip"
  output_path = "${path.module}/quality-monitoring-lambda.zip"
  
  source {
    content = templatefile("${path.module}/lambda_quality_code.py", {
      metadata_table = local.dynamodb_metadata_table
      project_name   = var.project_name
    })
    filename = "lambda_function.py"
  }
}

resource "aws_lambda_function" "quality_monitoring" {
  function_name    = "${var.project_name}-quality-monitoring-${local.random_suffix}"
  filename         = data.archive_file.quality_monitoring_lambda.output_path
  handler          = "lambda_function.lambda_handler"
  runtime          = var.lambda_runtime
  role             = aws_iam_role.lambda_role.arn
  timeout          = var.lambda_timeout
  memory_size      = 256
  source_code_hash = data.archive_file.quality_monitoring_lambda.output_base64sha256

  layers = [aws_lambda_layer_version.shared_layer.arn]

  environment {
    variables = {
      METADATA_TABLE = aws_dynamodb_table.metadata.name
      PROJECT_NAME   = var.project_name
    }
  }

  tracing_config {
    mode = var.enable_xray_tracing ? "Active" : "PassThrough"
  }

  depends_on = [
    aws_iam_role_policy.lambda_policy,
    data.archive_file.quality_monitoring_lambda,
    aws_lambda_layer_version.shared_layer
  ]

  tags = merge(local.common_tags, {
    Name = "Quality Monitoring Function"
  })
}

# ===== CLOUDWATCH LOG GROUPS =====

# CloudWatch log group for data ingestion function
resource "aws_cloudwatch_log_group" "data_ingestion_logs" {
  name              = "/aws/lambda/${aws_lambda_function.data_ingestion.function_name}"
  retention_in_days = var.enable_cloudwatch_logs_retention ? var.cloudwatch_logs_retention_days : null

  tags = merge(local.common_tags, {
    Name = "Data Ingestion Logs"
  })
}

# CloudWatch log group for data validation function
resource "aws_cloudwatch_log_group" "data_validation_logs" {
  name              = "/aws/lambda/${aws_lambda_function.data_validation.function_name}"
  retention_in_days = var.enable_cloudwatch_logs_retention ? var.cloudwatch_logs_retention_days : null

  tags = merge(local.common_tags, {
    Name = "Data Validation Logs"
  })
}

# CloudWatch log group for quality monitoring function
resource "aws_cloudwatch_log_group" "quality_monitoring_logs" {
  name              = "/aws/lambda/${aws_lambda_function.quality_monitoring.function_name}"
  retention_in_days = var.enable_cloudwatch_logs_retention ? var.cloudwatch_logs_retention_days : null

  tags = merge(local.common_tags, {
    Name = "Quality Monitoring Logs"
  })
}

# ===== EVENTBRIDGE CONFIGURATION =====

# Custom EventBridge bus
resource "aws_cloudwatch_event_bus" "custom_bus" {
  name = local.custom_event_bus

  tags = merge(local.common_tags, {
    Name = "Data Lake Event Bus"
  })
}

# EventBridge rule for data ingestion events
resource "aws_cloudwatch_event_rule" "data_ingestion_rule" {
  name           = "${var.project_name}-data-ingestion-rule-${local.random_suffix}"
  description    = "Route data ingestion events to validation function"
  event_bus_name = aws_cloudwatch_event_bus.custom_bus.name
  state          = var.eventbridge_rule_state

  event_pattern = jsonencode({
    source      = ["datalake.ingestion"]
    detail-type = ["Data Received"]
  })

  tags = merge(local.common_tags, {
    Name = "Data Ingestion Rule"
  })
}

# EventBridge rule for data validation events
resource "aws_cloudwatch_event_rule" "data_validation_rule" {
  name           = "${var.project_name}-data-validation-rule-${local.random_suffix}"
  description    = "Route data validation events to quality monitoring"
  event_bus_name = aws_cloudwatch_event_bus.custom_bus.name
  state          = var.eventbridge_rule_state

  event_pattern = jsonencode({
    source      = ["datalake.validation"]
    detail-type = ["Data Validated"]
  })

  tags = merge(local.common_tags, {
    Name = "Data Validation Rule"
  })
}

# EventBridge rule for quality check events
resource "aws_cloudwatch_event_rule" "data_quality_rule" {
  name           = "${var.project_name}-data-quality-rule-${local.random_suffix}"
  description    = "Route quality check events for monitoring"
  event_bus_name = aws_cloudwatch_event_bus.custom_bus.name
  state          = var.eventbridge_rule_state

  event_pattern = jsonencode({
    source      = ["datalake.quality"]
    detail-type = ["Quality Check Complete"]
  })

  tags = merge(local.common_tags, {
    Name = "Data Quality Rule"
  })
}

# EventBridge targets
resource "aws_cloudwatch_event_target" "validation_target" {
  rule           = aws_cloudwatch_event_rule.data_ingestion_rule.name
  event_bus_name = aws_cloudwatch_event_bus.custom_bus.name
  target_id      = "DataValidationTarget"
  arn            = aws_lambda_function.data_validation.arn
}

resource "aws_cloudwatch_event_target" "quality_target" {
  rule           = aws_cloudwatch_event_rule.data_validation_rule.name
  event_bus_name = aws_cloudwatch_event_bus.custom_bus.name
  target_id      = "QualityMonitoringTarget"
  arn            = aws_lambda_function.quality_monitoring.arn
}

# ===== LAMBDA PERMISSIONS =====

# Permission for S3 to invoke data ingestion Lambda
resource "aws_lambda_permission" "s3_invoke_ingestion" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.data_ingestion.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.raw_data.arn
}

# Permission for EventBridge to invoke data validation Lambda
resource "aws_lambda_permission" "eventbridge_invoke_validation" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.data_validation.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.data_ingestion_rule.arn
}

# Permission for EventBridge to invoke quality monitoring Lambda
resource "aws_lambda_permission" "eventbridge_invoke_quality" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.quality_monitoring.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.data_validation_rule.arn
}

# ===== S3 EVENT NOTIFICATION =====

# S3 bucket notification configuration
resource "aws_s3_bucket_notification" "raw_data_notification" {
  bucket = aws_s3_bucket.raw_data.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.data_ingestion.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "input/"
  }

  depends_on = [aws_lambda_permission.s3_invoke_ingestion]
}

# ===== GLUE COMPONENTS =====

# Glue database for data catalog
resource "aws_glue_catalog_database" "data_catalog" {
  name        = local.glue_database
  description = "Data lake catalog database for ${var.project_name}"
}

# Glue crawler for schema discovery
resource "aws_glue_crawler" "data_crawler" {
  database_name = aws_glue_catalog_database.data_catalog.name
  name          = "${var.project_name}-crawler-${local.random_suffix}"
  role          = aws_iam_role.glue_role.arn
  schedule      = var.glue_crawler_schedule

  s3_target {
    path = "s3://${aws_s3_bucket.processed_data.bucket}/validated/"
  }

  tags = merge(local.common_tags, {
    Name = "Data Lake Crawler"
  })
}