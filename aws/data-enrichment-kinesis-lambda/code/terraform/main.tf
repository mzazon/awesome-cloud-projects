# main.tf - Main infrastructure configuration for streaming data enrichment

# Data sources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Resource naming convention
  name_prefix = "${var.project_name}-${var.environment}"
  name_suffix = random_id.suffix.hex
  
  # Common tags
  common_tags = merge(
    {
      Environment = var.environment
      Project     = var.project_name
      ManagedBy   = "terraform"
      Purpose     = "DataEnrichment"
    },
    var.additional_tags
  )
}

# =============================================================================
# DynamoDB Table for User Profile Lookups
# =============================================================================

resource "aws_dynamodb_table" "enrichment_lookup" {
  name           = "${local.name_prefix}-lookup-table-${local.name_suffix}"
  billing_mode   = var.dynamodb_billing_mode
  hash_key       = "user_id"

  attribute {
    name = "user_id"
    type = "S"
  }

  # Enable point-in-time recovery for data protection
  point_in_time_recovery {
    enabled = true
  }

  # Enable server-side encryption
  server_side_encryption {
    enabled = true
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-lookup-table-${local.name_suffix}"
  })
}

# Populate DynamoDB table with sample data
resource "aws_dynamodb_table_item" "sample_user_1" {
  table_name = aws_dynamodb_table.enrichment_lookup.name
  hash_key   = aws_dynamodb_table.enrichment_lookup.hash_key

  item = jsonencode({
    user_id = {
      S = "user123"
    }
    name = {
      S = "John Doe"
    }
    email = {
      S = "john@example.com"
    }
    segment = {
      S = "premium"
    }
    location = {
      S = "New York"
    }
  })
}

resource "aws_dynamodb_table_item" "sample_user_2" {
  table_name = aws_dynamodb_table.enrichment_lookup.name
  hash_key   = aws_dynamodb_table.enrichment_lookup.hash_key

  item = jsonencode({
    user_id = {
      S = "user456"
    }
    name = {
      S = "Jane Smith"
    }
    email = {
      S = "jane@example.com"
    }
    segment = {
      S = "standard"
    }
    location = {
      S = "California"
    }
  })
}

# =============================================================================
# S3 Bucket for Enriched Data Storage
# =============================================================================

# S3 bucket for storing enriched data
resource "aws_s3_bucket" "enriched_data" {
  bucket = "${local.name_prefix}-enriched-data-${local.name_suffix}"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-enriched-data-${local.name_suffix}"
  })
}

# Configure bucket versioning
resource "aws_s3_bucket_versioning" "enriched_data" {
  bucket = aws_s3_bucket.enriched_data.id
  versioning_configuration {
    status = var.s3_versioning_enabled ? "Enabled" : "Disabled"
  }
}

# Configure server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "enriched_data" {
  bucket = aws_s3_bucket.enriched_data.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# Block public access
resource "aws_s3_bucket_public_access_block" "enriched_data" {
  bucket = aws_s3_bucket.enriched_data.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# =============================================================================
# Kinesis Data Stream
# =============================================================================

resource "aws_kinesis_stream" "data_stream" {
  name             = "${local.name_prefix}-stream-${local.name_suffix}"
  shard_count      = var.kinesis_shard_count
  retention_period = 24

  # Enable encryption
  encryption_type = "KMS"
  kms_key_id      = "alias/aws/kinesis"

  # Enable enhanced monitoring if specified
  shard_level_metrics = var.enable_enhanced_monitoring ? [
    "IncomingRecords",
    "OutgoingRecords",
    "IncomingBytes",
    "OutgoingBytes",
    "WriteProvisionedThroughputExceeded",
    "ReadProvisionedThroughputExceeded"
  ] : []

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-stream-${local.name_suffix}"
  })
}

# =============================================================================
# IAM Role and Policies for Lambda Function
# =============================================================================

# IAM role for Lambda function
resource "aws_iam_role" "lambda_execution_role" {
  name = "${local.name_prefix}-lambda-role-${local.name_suffix}"

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
    Name = "${local.name_prefix}-lambda-role-${local.name_suffix}"
  })
}

# Attach basic Lambda execution policy
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.lambda_execution_role.name
}

# Custom policy for Lambda function permissions
resource "aws_iam_role_policy" "lambda_custom_policy" {
  name = "${local.name_prefix}-lambda-policy-${local.name_suffix}"
  role = aws_iam_role.lambda_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kinesis:DescribeStream",
          "kinesis:DescribeStreamSummary",
          "kinesis:GetRecords",
          "kinesis:GetShardIterator",
          "kinesis:ListShards",
          "kinesis:SubscribeToShard"
        ]
        Resource = aws_kinesis_stream.data_stream.arn
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = aws_dynamodb_table.enrichment_lookup.arn
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:PutObjectAcl"
        ]
        Resource = "${aws_s3_bucket.enriched_data.arn}/*"
      }
    ]
  })
}

# =============================================================================
# Lambda Function for Data Enrichment
# =============================================================================

# Create Lambda function package
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "/tmp/enrichment_function.zip"
  
  source {
    content = templatefile("${path.module}/lambda_function.py", {
      table_name  = aws_dynamodb_table.enrichment_lookup.name
      bucket_name = aws_s3_bucket.enriched_data.bucket
    })
    filename = "lambda_function.py"
  }
}

# Lambda function for data enrichment
resource "aws_lambda_function" "enrichment_function" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "${local.name_prefix}-function-${local.name_suffix}"
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  runtime     = "python3.9"
  timeout     = var.lambda_timeout
  memory_size = var.lambda_memory_size

  environment {
    variables = {
      TABLE_NAME  = aws_dynamodb_table.enrichment_lookup.name
      BUCKET_NAME = aws_s3_bucket.enriched_data.bucket
    }
  }

  # Enable tracing for observability
  tracing_config {
    mode = "Active"
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy.lambda_custom_policy,
    aws_cloudwatch_log_group.lambda_logs
  ]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-function-${local.name_suffix}"
  })
}

# CloudWatch Log Group for Lambda function
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${local.name_prefix}-function-${local.name_suffix}"
  retention_in_days = var.cloudwatch_log_retention_days

  tags = merge(local.common_tags, {
    Name = "/aws/lambda/${local.name_prefix}-function-${local.name_suffix}"
  })
}

# =============================================================================
# Event Source Mapping (Kinesis to Lambda)
# =============================================================================

resource "aws_lambda_event_source_mapping" "kinesis_lambda_trigger" {
  event_source_arn  = aws_kinesis_stream.data_stream.arn
  function_name     = aws_lambda_function.enrichment_function.arn
  starting_position = "LATEST"

  # Batch configuration for optimal performance
  batch_size                         = var.lambda_batch_size
  maximum_batching_window_in_seconds = var.lambda_maximum_batching_window_in_seconds

  # Error handling configuration
  maximum_record_age_in_seconds = 86400  # 24 hours
  bisect_batch_on_function_error = true
  maximum_retry_attempts         = 3

  depends_on = [
    aws_lambda_function.enrichment_function,
    aws_kinesis_stream.data_stream
  ]
}

# =============================================================================
# CloudWatch Alarms for Monitoring
# =============================================================================

# Lambda function error alarm
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  count = var.cloudwatch_alarms_enabled ? 1 : 0

  alarm_name          = "${local.name_prefix}-lambda-errors-${local.name_suffix}"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "1"
  alarm_description   = "This metric monitors lambda errors"

  dimensions = {
    FunctionName = aws_lambda_function.enrichment_function.function_name
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-lambda-errors-${local.name_suffix}"
  })
}

# Kinesis incoming records alarm
resource "aws_cloudwatch_metric_alarm" "kinesis_incoming_records" {
  count = var.cloudwatch_alarms_enabled ? 1 : 0

  alarm_name          = "${local.name_prefix}-kinesis-incoming-records-${local.name_suffix}"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "IncomingRecords"
  namespace           = "AWS/Kinesis"
  period              = "300"
  statistic           = "Sum"
  threshold           = "1"
  alarm_description   = "This metric monitors kinesis incoming records"

  dimensions = {
    StreamName = aws_kinesis_stream.data_stream.name
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-kinesis-incoming-records-${local.name_suffix}"
  })
}

# Lambda duration alarm
resource "aws_cloudwatch_metric_alarm" "lambda_duration" {
  count = var.cloudwatch_alarms_enabled ? 1 : 0

  alarm_name          = "${local.name_prefix}-lambda-duration-${local.name_suffix}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Average"
  threshold           = var.lambda_timeout * 1000 * 0.8  # 80% of timeout in milliseconds
  alarm_description   = "This metric monitors lambda duration"

  dimensions = {
    FunctionName = aws_lambda_function.enrichment_function.function_name
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-lambda-duration-${local.name_suffix}"
  })
}