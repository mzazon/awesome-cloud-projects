# Real-time Clickstream Analytics Infrastructure
# This Terraform configuration creates a complete real-time analytics pipeline
# using AWS Kinesis Data Streams, Lambda, DynamoDB, and CloudWatch

# Data sources for current AWS configuration
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  # Common naming convention
  name_prefix = "${var.project_name}-${var.environment}"
  random_suffix = random_id.suffix.hex
  
  # Resource names
  stream_name = "${local.name_prefix}-events-${local.random_suffix}"
  table_prefix = "${local.name_prefix}-${local.random_suffix}"
  bucket_name = "${local.name_prefix}-archive-${local.random_suffix}"
  
  # Common tags
  common_tags = merge(var.tags, {
    Name        = local.name_prefix
    Environment = var.environment
    Project     = var.project_name
  })
}

# ================================
# S3 Bucket for Raw Data Archive
# ================================

# S3 bucket for storing raw clickstream events
resource "aws_s3_bucket" "clickstream_archive" {
  bucket = local.bucket_name

  tags = merge(local.common_tags, {
    Purpose = "Raw clickstream data archive"
  })
}

# S3 bucket versioning configuration
resource "aws_s3_bucket_versioning" "clickstream_archive" {
  bucket = aws_s3_bucket.clickstream_archive.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "clickstream_archive" {
  bucket = aws_s3_bucket.clickstream_archive.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# S3 bucket public access block
resource "aws_s3_bucket_public_access_block" "clickstream_archive" {
  bucket = aws_s3_bucket.clickstream_archive.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket lifecycle configuration for cost optimization
resource "aws_s3_bucket_lifecycle_configuration" "clickstream_archive" {
  bucket = aws_s3_bucket.clickstream_archive.id

  rule {
    id     = "lifecycle_rule"
    status = "Enabled"

    expiration {
      days = var.s3_lifecycle_expiration_days
    }

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 90
      storage_class = "GLACIER"
    }
  }
}

# ================================
# Kinesis Data Stream
# ================================

# Kinesis Data Stream for real-time clickstream ingestion
resource "aws_kinesis_stream" "clickstream_events" {
  name             = local.stream_name
  shard_count      = var.kinesis_shard_count
  retention_period = var.kinesis_retention_period

  shard_level_metrics = [
    "IncomingRecords",
    "OutgoingRecords",
  ]

  stream_mode_details {
    stream_mode = "PROVISIONED"
  }

  encryption_type = "KMS"
  kms_key_id      = "alias/aws/kinesis"

  tags = merge(local.common_tags, {
    Purpose = "Clickstream event ingestion"
  })
}

# ================================
# DynamoDB Tables
# ================================

# DynamoDB table for page view metrics
resource "aws_dynamodb_table" "page_metrics" {
  name           = "${local.table_prefix}-page-metrics"
  billing_mode   = var.dynamodb_billing_mode
  hash_key       = "page_url"
  range_key      = "timestamp_hour"

  attribute {
    name = "page_url"
    type = "S"
  }

  attribute {
    name = "timestamp_hour"
    type = "S"
  }

  # TTL configuration for automatic data expiration
  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  # Point-in-time recovery for data protection
  point_in_time_recovery {
    enabled = true
  }

  # Server-side encryption
  server_side_encryption {
    enabled = true
  }

  tags = merge(local.common_tags, {
    Purpose = "Page view metrics storage"
  })
}

# DynamoDB table for session metrics
resource "aws_dynamodb_table" "session_metrics" {
  name         = "${local.table_prefix}-session-metrics"
  billing_mode = var.dynamodb_billing_mode
  hash_key     = "session_id"

  attribute {
    name = "session_id"
    type = "S"
  }

  # TTL configuration
  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  # Point-in-time recovery
  point_in_time_recovery {
    enabled = true
  }

  # Server-side encryption
  server_side_encryption {
    enabled = true
  }

  tags = merge(local.common_tags, {
    Purpose = "Session metrics storage"
  })
}

# DynamoDB table for real-time counters
resource "aws_dynamodb_table" "counters" {
  name         = "${local.table_prefix}-counters"
  billing_mode = var.dynamodb_billing_mode
  hash_key     = "metric_name"
  range_key    = "time_window"

  attribute {
    name = "metric_name"
    type = "S"
  }

  attribute {
    name = "time_window"
    type = "S"
  }

  # TTL configuration for automatic cleanup
  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  # Point-in-time recovery
  point_in_time_recovery {
    enabled = true
  }

  # Server-side encryption
  server_side_encryption {
    enabled = true
  }

  tags = merge(local.common_tags, {
    Purpose = "Real-time counters storage"
  })
}

# ================================
# SNS Topic for Alerts (Optional)
# ================================

# SNS topic for anomaly alerts
resource "aws_sns_topic" "anomaly_alerts" {
  count = var.enable_sns_alerts ? 1 : 0
  name  = "${local.name_prefix}-anomaly-alerts-${local.random_suffix}"

  # Enable server-side encryption
  kms_master_key_id = "alias/aws/sns"

  tags = merge(local.common_tags, {
    Purpose = "Anomaly detection alerts"
  })
}

# SNS topic subscription for email alerts
resource "aws_sns_topic_subscription" "email_alerts" {
  count     = var.enable_sns_alerts && var.sns_email_endpoint != "" ? 1 : 0
  topic_arn = aws_sns_topic.anomaly_alerts[0].arn
  protocol  = "email"
  endpoint  = var.sns_email_endpoint
}

# ================================
# IAM Roles and Policies
# ================================

# IAM role for Lambda functions
resource "aws_iam_role" "lambda_execution_role" {
  name = "${local.name_prefix}-lambda-role-${local.random_suffix}"

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
    Purpose = "Lambda execution role"
  })
}

# IAM policy for Lambda functions
resource "aws_iam_role_policy" "lambda_policy" {
  name = "${local.name_prefix}-lambda-policy"
  role = aws_iam_role.lambda_execution_role.id

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
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
      },
      {
        Effect = "Allow"
        Action = [
          "kinesis:DescribeStream",
          "kinesis:GetShardIterator",
          "kinesis:GetRecords",
          "kinesis:ListStreams"
        ]
        Resource = aws_kinesis_stream.clickstream_events.arn
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:GetItem",
          "dynamodb:Query"
        ]
        Resource = [
          aws_dynamodb_table.page_metrics.arn,
          aws_dynamodb_table.session_metrics.arn,
          aws_dynamodb_table.counters.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject"
        ]
        Resource = "${aws_s3_bucket.clickstream_archive.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = var.enable_sns_alerts ? aws_sns_topic.anomaly_alerts[0].arn : null
      }
    ]
  })
}

# ================================
# Lambda Functions
# ================================

# Create ZIP file for event processor Lambda
data "archive_file" "event_processor_zip" {
  type        = "zip"
  output_path = "event_processor.zip"
  
  source {
    content = templatefile("${path.module}/lambda_functions/event_processor.js", {
      table_prefix = local.table_prefix
      bucket_name  = local.bucket_name
    })
    filename = "index.js"
  }
  
  source {
    content = jsonencode({
      name = "clickstream-event-processor"
      version = "1.0.0"
      main = "index.js"
      dependencies = {
        "aws-sdk" = "^2.1000.0"
      }
    })
    filename = "package.json"
  }
}

# Event processor Lambda function
resource "aws_lambda_function" "event_processor" {
  filename         = data.archive_file.event_processor_zip.output_path
  function_name    = "${local.name_prefix}-event-processor-${local.random_suffix}"
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "index.handler"
  source_code_hash = data.archive_file.event_processor_zip.output_base64sha256
  runtime         = "nodejs18.x"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size

  environment {
    variables = {
      TABLE_PREFIX = local.table_prefix
      BUCKET_NAME  = local.bucket_name
    }
  }

  # Dead letter queue configuration
  dead_letter_config {
    target_arn = aws_sqs_queue.dlq.arn
  }

  tags = merge(local.common_tags, {
    Purpose = "Process clickstream events"
  })

  depends_on = [
    aws_iam_role_policy.lambda_policy,
    aws_cloudwatch_log_group.event_processor_logs
  ]
}

# CloudWatch log group for event processor
resource "aws_cloudwatch_log_group" "event_processor_logs" {
  name              = "/aws/lambda/${local.name_prefix}-event-processor-${local.random_suffix}"
  retention_in_days = 14

  tags = merge(local.common_tags, {
    Purpose = "Event processor logs"
  })
}

# Event source mapping for event processor
resource "aws_lambda_event_source_mapping" "event_processor_mapping" {
  event_source_arn  = aws_kinesis_stream.clickstream_events.arn
  function_name     = aws_lambda_function.event_processor.arn
  starting_position = "LATEST"
  batch_size        = var.batch_size
  maximum_batching_window_in_seconds = var.maximum_batching_window_in_seconds

  depends_on = [
    aws_iam_role_policy.lambda_policy
  ]
}

# Create ZIP file for anomaly detector Lambda
data "archive_file" "anomaly_detector_zip" {
  count = var.enable_anomaly_detection ? 1 : 0
  type  = "zip"
  output_path = "anomaly_detector.zip"
  
  source {
    content = templatefile("${path.module}/lambda_functions/anomaly_detector.js", {
      table_prefix    = local.table_prefix
      sns_topic_arn   = var.enable_sns_alerts ? aws_sns_topic.anomaly_alerts[0].arn : ""
    })
    filename = "index.js"
  }
  
  source {
    content = jsonencode({
      name = "clickstream-anomaly-detector"
      version = "1.0.0"
      main = "index.js"
      dependencies = {
        "aws-sdk" = "^2.1000.0"
      }
    })
    filename = "package.json"
  }
}

# Anomaly detection Lambda function
resource "aws_lambda_function" "anomaly_detector" {
  count            = var.enable_anomaly_detection ? 1 : 0
  filename         = data.archive_file.anomaly_detector_zip[0].output_path
  function_name    = "${local.name_prefix}-anomaly-detector-${local.random_suffix}"
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "index.handler"
  source_code_hash = data.archive_file.anomaly_detector_zip[0].output_base64sha256
  runtime         = "nodejs18.x"
  timeout         = 30
  memory_size     = 128

  environment {
    variables = {
      TABLE_PREFIX  = local.table_prefix
      SNS_TOPIC_ARN = var.enable_sns_alerts ? aws_sns_topic.anomaly_alerts[0].arn : ""
    }
  }

  # Dead letter queue configuration
  dead_letter_config {
    target_arn = aws_sqs_queue.dlq.arn
  }

  tags = merge(local.common_tags, {
    Purpose = "Detect anomalies in clickstream"
  })

  depends_on = [
    aws_iam_role_policy.lambda_policy,
    aws_cloudwatch_log_group.anomaly_detector_logs
  ]
}

# CloudWatch log group for anomaly detector
resource "aws_cloudwatch_log_group" "anomaly_detector_logs" {
  count             = var.enable_anomaly_detection ? 1 : 0
  name              = "/aws/lambda/${local.name_prefix}-anomaly-detector-${local.random_suffix}"
  retention_in_days = 14

  tags = merge(local.common_tags, {
    Purpose = "Anomaly detector logs"
  })
}

# Event source mapping for anomaly detector
resource "aws_lambda_event_source_mapping" "anomaly_detector_mapping" {
  count             = var.enable_anomaly_detection ? 1 : 0
  event_source_arn  = aws_kinesis_stream.clickstream_events.arn
  function_name     = aws_lambda_function.anomaly_detector[0].arn
  starting_position = "LATEST"
  batch_size        = 50
  maximum_batching_window_in_seconds = 10

  depends_on = [
    aws_iam_role_policy.lambda_policy
  ]
}

# ================================
# Dead Letter Queue
# ================================

# SQS dead letter queue for failed Lambda invocations
resource "aws_sqs_queue" "dlq" {
  name                      = "${local.name_prefix}-dlq-${local.random_suffix}"
  message_retention_seconds = 1209600 # 14 days

  # Server-side encryption
  kms_master_key_id = "alias/aws/sqs"

  tags = merge(local.common_tags, {
    Purpose = "Dead letter queue for failed Lambda invocations"
  })
}

# ================================
# CloudWatch Dashboard
# ================================

# CloudWatch dashboard for monitoring
resource "aws_cloudwatch_dashboard" "clickstream_dashboard" {
  count          = var.enable_cloudwatch_dashboard ? 1 : 0
  dashboard_name = "${local.name_prefix}-dashboard-${local.random_suffix}"

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
            ["Clickstream/Events", "EventsProcessed", "EventType", "page_view"],
            ["...", "click"]
          ]
          period = 300
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "Events Processed by Type"
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
            ["AWS/Lambda", "Duration", "FunctionName", aws_lambda_function.event_processor.function_name],
            [".", "Errors", ".", "."],
            [".", "Invocations", ".", "."]
          ]
          period = 300
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "Lambda Performance"
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
            ["AWS/Kinesis", "IncomingRecords", "StreamName", aws_kinesis_stream.clickstream_events.name],
            [".", "OutgoingRecords", ".", "."]
          ]
          period = 300
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "Kinesis Stream Throughput"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Purpose = "Monitoring dashboard"
  })
}