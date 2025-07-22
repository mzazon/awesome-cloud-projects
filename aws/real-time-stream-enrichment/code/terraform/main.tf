# ==============================================================================
# Real-Time Stream Enrichment with Kinesis Data Firehose and EventBridge Pipes
# ==============================================================================

# Data sources for current AWS account and region information
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Random ID for unique resource naming
resource "random_id" "bucket_suffix" {
  byte_length = 8
}

# ==============================================================================
# S3 BUCKET FOR ENRICHED DATA STORAGE
# ==============================================================================

# S3 bucket for storing enriched streaming data
resource "aws_s3_bucket" "enriched_data" {
  bucket        = "${var.s3_bucket_prefix}-${random_id.bucket_suffix.hex}"
  force_destroy = true

  tags = {
    Name        = "${var.project_name}-enriched-data-${random_id.bucket_suffix.hex}"
    Purpose     = "Store enriched streaming data from EventBridge Pipes"
    DataType    = "Enriched streaming events"
    Environment = var.environment
  }
}

# S3 bucket versioning configuration
resource "aws_s3_bucket_versioning" "enriched_data" {
  bucket = aws_s3_bucket.enriched_data.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket server-side encryption configuration
resource "aws_s3_bucket_server_side_encryption_configuration" "enriched_data" {
  count  = var.enable_encryption ? 1 : 0
  bucket = aws_s3_bucket.enriched_data.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# S3 bucket public access block (security best practice)
resource "aws_s3_bucket_public_access_block" "enriched_data" {
  bucket = aws_s3_bucket.enriched_data.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket lifecycle configuration for cost optimization
resource "aws_s3_bucket_lifecycle_configuration" "enriched_data" {
  bucket = aws_s3_bucket.enriched_data.id

  rule {
    id     = "transition_to_ia"
    status = "Enabled"

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    transition {
      days          = 365
      storage_class = "DEEP_ARCHIVE"
    }
  }

  rule {
    id     = "delete_incomplete_multipart"
    status = "Enabled"

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# ==============================================================================
# DYNAMODB TABLE FOR REFERENCE DATA
# ==============================================================================

# DynamoDB table for storing reference data used during enrichment
resource "aws_dynamodb_table" "reference_data" {
  name           = "${var.project_name}-reference-data-${random_id.bucket_suffix.hex}"
  billing_mode   = var.dynamodb_billing_mode
  hash_key       = "productId"
  read_capacity  = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_read_capacity : null
  write_capacity = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_write_capacity : null

  attribute {
    name = "productId"
    type = "S"
  }

  # Point-in-time recovery for data protection
  point_in_time_recovery {
    enabled = var.enable_point_in_time_recovery
  }

  # Server-side encryption
  dynamic "server_side_encryption" {
    for_each = var.enable_encryption ? [1] : []
    content {
      enabled = true
    }
  }

  tags = {
    Name        = "${var.project_name}-reference-data"
    Purpose     = "Store reference data for stream enrichment"
    DataType    = "Product information"
    Environment = var.environment
  }
}

# Sample reference data items (optional)
resource "aws_dynamodb_table_item" "sample_product_001" {
  count      = var.populate_sample_data ? 1 : 0
  table_name = aws_dynamodb_table.reference_data.name
  hash_key   = aws_dynamodb_table.reference_data.hash_key

  item = jsonencode({
    productId = {
      S = "PROD-001"
    }
    productName = {
      S = "Smart Sensor"
    }
    category = {
      S = "IoT Devices"
    }
    price = {
      N = "49.99"
    }
    description = {
      S = "Advanced IoT sensor with built-in analytics"
    }
    manufacturer = {
      S = "TechCorp"
    }
  })
}

resource "aws_dynamodb_table_item" "sample_product_002" {
  count      = var.populate_sample_data ? 1 : 0
  table_name = aws_dynamodb_table.reference_data.name
  hash_key   = aws_dynamodb_table.reference_data.hash_key

  item = jsonencode({
    productId = {
      S = "PROD-002"
    }
    productName = {
      S = "Temperature Monitor"
    }
    category = {
      S = "IoT Devices"
    }
    price = {
      N = "79.99"
    }
    description = {
      S = "High-precision temperature monitoring device"
    }
    manufacturer = {
      S = "SensorTech"
    }
  })
}

resource "aws_dynamodb_table_item" "sample_product_003" {
  count      = var.populate_sample_data ? 1 : 0
  table_name = aws_dynamodb_table.reference_data.name
  hash_key   = aws_dynamodb_table.reference_data.hash_key

  item = jsonencode({
    productId = {
      S = "PROD-003"
    }
    productName = {
      S = "Pressure Gauge"
    }
    category = {
      S = "Industrial Equipment"
    }
    price = {
      N = "129.99"
    }
    description = {
      S = "Industrial-grade pressure monitoring gauge"
    }
    manufacturer = {
      S = "IndustrialSys"
    }
  })
}

# ==============================================================================
# KINESIS DATA STREAM
# ==============================================================================

# Kinesis Data Stream for ingesting raw events
resource "aws_kinesis_stream" "raw_events" {
  name                      = "${var.project_name}-raw-events-${random_id.bucket_suffix.hex}"
  retention_period          = var.kinesis_retention_period
  shard_level_metrics       = ["IncomingRecords", "OutgoingRecords"]
  enforce_consumer_deletion = true

  # Stream mode configuration
  stream_mode_details {
    stream_mode = var.kinesis_stream_mode
  }

  # Shard configuration (only applicable for PROVISIONED mode)
  dynamic "shard_count" {
    for_each = var.kinesis_stream_mode == "PROVISIONED" ? [1] : []
    content {
      shard_count = var.kinesis_shard_count
    }
  }

  # Encryption configuration
  dynamic "encryption_type" {
    for_each = var.enable_encryption ? [1] : []
    content {
      encryption_type = "KMS"
      key_id          = "alias/aws/kinesis"
    }
  }

  tags = {
    Name        = "${var.project_name}-raw-events"
    Purpose     = "Ingest raw streaming events for enrichment"
    StreamMode  = var.kinesis_stream_mode
    Environment = var.environment
  }
}

# ==============================================================================
# LAMBDA FUNCTION FOR EVENT ENRICHMENT
# ==============================================================================

# CloudWatch Log Group for Lambda function
resource "aws_cloudwatch_log_group" "lambda_logs" {
  count             = var.enable_cloudwatch_logs ? 1 : 0
  name              = "/aws/lambda/${var.project_name}-enrichment-${random_id.bucket_suffix.hex}"
  retention_in_days = var.log_retention_days

  tags = {
    Name        = "${var.project_name}-lambda-logs"
    Purpose     = "Store Lambda function execution logs"
    Environment = var.environment
  }
}

# IAM role for Lambda execution
resource "aws_iam_role" "lambda_execution_role" {
  name = "${var.project_name}-lambda-execution-role-${random_id.bucket_suffix.hex}"

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

  tags = {
    Name        = "${var.project_name}-lambda-execution-role"
    Purpose     = "Lambda execution role for event enrichment"
    Environment = var.environment
  }
}

# IAM policy for Lambda basic execution (CloudWatch Logs)
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.lambda_execution_role.name
}

# IAM policy for DynamoDB read access
resource "aws_iam_role_policy" "lambda_dynamodb_access" {
  name = "${var.project_name}-lambda-dynamodb-policy"
  role = aws_iam_role.lambda_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:Query",
          "dynamodb:BatchGetItem"
        ]
        Resource = aws_dynamodb_table.reference_data.arn
      }
    ]
  })
}

# Lambda function code archive
data "archive_file" "lambda_code" {
  type        = "zip"
  output_path = "${path.module}/lambda_function.zip"
  
  source {
    content = templatefile("${path.module}/lambda_function.py.tpl", {
      table_name = aws_dynamodb_table.reference_data.name
    })
    filename = "lambda_function.py"
  }
}

# Lambda function for event enrichment
resource "aws_lambda_function" "enrichment" {
  function_name    = "${var.project_name}-enrichment-${random_id.bucket_suffix.hex}"
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  filename        = data.archive_file.lambda_code.output_path
  source_code_hash = data.archive_file.lambda_code.output_base64sha256

  environment {
    variables = {
      TABLE_NAME   = aws_dynamodb_table.reference_data.name
      LOG_LEVEL    = var.environment == "prod" ? "INFO" : "DEBUG"
      ENVIRONMENT  = var.environment
    }
  }

  # CloudWatch Logs dependency
  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_cloudwatch_log_group.lambda_logs,
  ]

  tags = {
    Name        = "${var.project_name}-enrichment-function"
    Purpose     = "Enrich streaming events with reference data"
    Runtime     = var.lambda_runtime
    Environment = var.environment
  }
}

# ==============================================================================
# KINESIS DATA FIREHOSE
# ==============================================================================

# IAM role for Kinesis Data Firehose
resource "aws_iam_role" "firehose_delivery_role" {
  name = "${var.project_name}-firehose-delivery-role-${random_id.bucket_suffix.hex}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "firehose.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-firehose-delivery-role"
    Purpose     = "Firehose delivery role for S3 destination"
    Environment = var.environment
  }
}

# IAM policy for Firehose S3 delivery
resource "aws_iam_role_policy" "firehose_s3_policy" {
  name = "${var.project_name}-firehose-s3-policy"
  role = aws_iam_role.firehose_delivery_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:AbortMultipartUpload",
          "s3:GetBucketLocation",
          "s3:GetObject",
          "s3:ListBucket",
          "s3:ListBucketMultipartUploads",
          "s3:PutObject",
          "s3:PutObjectAcl"
        ]
        Resource = [
          aws_s3_bucket.enriched_data.arn,
          "${aws_s3_bucket.enriched_data.arn}/*"
        ]
      }
    ]
  })
}

# Kinesis Data Firehose delivery stream
resource "aws_kinesis_firehose_delivery_stream" "s3_delivery" {
  name        = "${var.project_name}-s3-delivery-${random_id.bucket_suffix.hex}"
  destination = "extended_s3"

  extended_s3_configuration {
    role_arn           = aws_iam_role.firehose_delivery_role.arn
    bucket_arn         = aws_s3_bucket.enriched_data.arn
    prefix             = "${var.s3_data_prefix}/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/hour=!{timestamp:HH}/"
    error_output_prefix = "${var.s3_error_prefix}/"
    compression_format = var.firehose_compression_format

    # Buffering configuration
    buffering_size     = var.firehose_buffer_size
    buffering_interval = var.firehose_buffer_interval

    # CloudWatch logging
    cloudwatch_logging_options {
      enabled         = var.enable_cloudwatch_logs
      log_group_name  = var.enable_cloudwatch_logs ? "/aws/kinesisfirehose/${var.project_name}-s3-delivery" : null
    }

    # Data format conversion (disabled by default, can be enabled for analytics)
    data_format_conversion_configuration {
      enabled = false
    }
  }

  tags = {
    Name        = "${var.project_name}-s3-delivery"
    Purpose     = "Deliver enriched events to S3 data lake"
    Destination = "S3"
    Environment = var.environment
  }
}

# ==============================================================================
# EVENTBRIDGE PIPES
# ==============================================================================

# IAM role for EventBridge Pipes
resource "aws_iam_role" "pipes_execution_role" {
  name = "${var.project_name}-pipes-execution-role-${random_id.bucket_suffix.hex}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "pipes.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-pipes-execution-role"
    Purpose     = "EventBridge Pipes execution role for stream processing"
    Environment = var.environment
  }
}

# IAM policy for EventBridge Pipes Kinesis source access
resource "aws_iam_role_policy" "pipes_kinesis_source_policy" {
  name = "${var.project_name}-pipes-kinesis-source-policy"
  role = aws_iam_role.pipes_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kinesis:DescribeStream",
          "kinesis:GetRecords",
          "kinesis:GetShardIterator",
          "kinesis:ListStreams",
          "kinesis:SubscribeToShard",
          "kinesis:DescribeStreamSummary",
          "kinesis:ListShards"
        ]
        Resource = aws_kinesis_stream.raw_events.arn
      }
    ]
  })
}

# IAM policy for EventBridge Pipes Lambda enrichment access
resource "aws_iam_role_policy" "pipes_lambda_enrichment_policy" {
  name = "${var.project_name}-pipes-lambda-enrichment-policy"
  role = aws_iam_role.pipes_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = aws_lambda_function.enrichment.arn
      }
    ]
  })
}

# IAM policy for EventBridge Pipes Firehose target access
resource "aws_iam_role_policy" "pipes_firehose_target_policy" {
  name = "${var.project_name}-pipes-firehose-target-policy"
  role = aws_iam_role.pipes_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "firehose:PutRecord",
          "firehose:PutRecordBatch"
        ]
        Resource = aws_kinesis_firehose_delivery_stream.s3_delivery.arn
      }
    ]
  })
}

# EventBridge Pipe for stream enrichment
resource "aws_pipes_pipe" "enrichment_pipe" {
  name     = "${var.project_name}-enrichment-pipe-${random_id.bucket_suffix.hex}"
  role_arn = aws_iam_role.pipes_execution_role.arn

  # Source configuration (Kinesis Data Stream)
  source = aws_kinesis_stream.raw_events.arn
  source_parameters {
    kinesis_stream_parameters {
      starting_position                         = var.pipes_starting_position
      batch_size                               = var.pipes_batch_size
      maximum_batching_window_in_seconds       = var.pipes_maximum_batching_window_in_seconds
      parallelization_factor                   = 1
      starting_position_timestamp              = null
      on_partial_batch_item_failure           = "AUTOMATIC_BISECT"
    }
  }

  # Enrichment configuration (Lambda function)
  enrichment = aws_lambda_function.enrichment.arn
  enrichment_parameters {
    input_template = jsonencode({
      records = "{{ pipes.sourcePayload }}"
    })
  }

  # Target configuration (Kinesis Data Firehose)
  target = aws_kinesis_firehose_delivery_stream.s3_delivery.arn
  target_parameters {
    kinesis_stream_parameters {
      partition_key = "$.productId"
    }
  }

  depends_on = [
    aws_iam_role_policy.pipes_kinesis_source_policy,
    aws_iam_role_policy.pipes_lambda_enrichment_policy,
    aws_iam_role_policy.pipes_firehose_target_policy
  ]

  tags = {
    Name        = "${var.project_name}-enrichment-pipe"
    Purpose     = "Process and enrich streaming events"
    Source      = "Kinesis Data Stream"
    Target      = "Kinesis Data Firehose"
    Environment = var.environment
  }
}

# ==============================================================================
# CLOUDWATCH ALARMS AND MONITORING
# ==============================================================================

# CloudWatch alarm for Lambda function errors
resource "aws_cloudwatch_metric_alarm" "lambda_error_rate" {
  alarm_name          = "${var.project_name}-lambda-error-rate-${random_id.bucket_suffix.hex}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "This metric monitors lambda error rate"
  alarm_actions       = []

  dimensions = {
    FunctionName = aws_lambda_function.enrichment.function_name
  }

  tags = {
    Name        = "${var.project_name}-lambda-error-alarm"
    Purpose     = "Monitor Lambda function errors"
    Environment = var.environment
  }
}

# CloudWatch alarm for Kinesis incoming records
resource "aws_cloudwatch_metric_alarm" "kinesis_incoming_records" {
  alarm_name          = "${var.project_name}-kinesis-incoming-records-${random_id.bucket_suffix.hex}"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "3"
  metric_name         = "IncomingRecords"
  namespace           = "AWS/Kinesis"
  period              = "300"
  statistic           = "Sum"
  threshold           = "1"
  alarm_description   = "This metric monitors Kinesis incoming records"
  treat_missing_data  = "notBreaching"

  dimensions = {
    StreamName = aws_kinesis_stream.raw_events.name
  }

  tags = {
    Name        = "${var.project_name}-kinesis-incoming-alarm"
    Purpose     = "Monitor Kinesis Data Stream activity"
    Environment = var.environment
  }
}