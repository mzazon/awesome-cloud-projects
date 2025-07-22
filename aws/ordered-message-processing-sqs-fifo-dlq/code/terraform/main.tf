# Data sources for AWS account and region information
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  count       = var.resource_suffix == "" ? 1 : 0
  byte_length = 4
}

# Local values for consistent resource naming
locals {
  suffix            = var.resource_suffix != "" ? var.resource_suffix : random_id.suffix[0].hex
  project_name      = "${var.project_name}-${local.suffix}"
  main_queue_name   = "${local.project_name}-main-queue.fifo"
  dlq_name          = "${local.project_name}-dlq.fifo"
  order_table_name  = "${local.project_name}-orders"
  archive_bucket    = "${local.project_name}-message-archive"
  sns_topic_name    = "${local.project_name}-alerts"
  
  # Common tags for all resources
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    Recipe      = "ordered-message-processing-sqs-fifo-dead-letter-queues"
  }
}

# ============================================================================
# KMS Key for Encryption (Optional)
# ============================================================================

# KMS key for encrypting SQS queues and S3 bucket
resource "aws_kms_key" "fifo_processing_key" {
  count = var.enable_kms_encryption ? 1 : 0
  
  description         = "KMS key for FIFO message processing encryption"
  deletion_window_in_days = var.kms_key_deletion_window
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow SQS service access"
        Effect = "Allow"
        Principal = {
          Service = "sqs.amazonaws.com"
        }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = "*"
      },
      {
        Sid    = "Allow Lambda service access"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = "*"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-kms-key"
  })
}

# KMS key alias for easier reference
resource "aws_kms_alias" "fifo_processing_alias" {
  count = var.enable_kms_encryption ? 1 : 0
  
  name          = "alias/${local.project_name}-fifo-processing"
  target_key_id = aws_kms_key.fifo_processing_key[0].key_id
}

# ============================================================================
# DynamoDB Table for Order State Management
# ============================================================================

# DynamoDB table for storing order processing state
resource "aws_dynamodb_table" "orders" {
  name           = local.order_table_name
  billing_mode   = "PROVISIONED"
  read_capacity  = var.dynamodb_read_capacity
  write_capacity = var.dynamodb_write_capacity
  hash_key       = "OrderId"

  # Primary key attribute
  attribute {
    name = "OrderId"
    type = "S"
  }

  # GSI attributes for querying by message group
  attribute {
    name = "MessageGroupId"
    type = "S"
  }

  attribute {
    name = "ProcessedAt"
    type = "S"
  }

  # Global Secondary Index for querying by message group
  global_secondary_index {
    name            = "MessageGroup-ProcessedAt-index"
    hash_key        = "MessageGroupId"
    range_key       = "ProcessedAt"
    read_capacity   = var.gsi_read_capacity
    write_capacity  = var.gsi_write_capacity
    projection_type = "ALL"
  }

  # Enable DynamoDB Streams for real-time data changes
  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  # Enable point-in-time recovery for data protection
  point_in_time_recovery {
    enabled = true
  }

  tags = merge(local.common_tags, {
    Name = local.order_table_name
  })
}

# ============================================================================
# S3 Bucket for Message Archiving
# ============================================================================

# S3 bucket for archiving poison messages
resource "aws_s3_bucket" "message_archive" {
  bucket = local.archive_bucket

  tags = merge(local.common_tags, {
    Name = local.archive_bucket
  })
}

# S3 bucket versioning configuration
resource "aws_s3_bucket_versioning" "message_archive_versioning" {
  bucket = aws_s3_bucket.message_archive.id
  
  versioning_configuration {
    status = var.enable_s3_versioning ? "Enabled" : "Disabled"
  }
}

# S3 bucket server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "message_archive_encryption" {
  bucket = aws_s3_bucket.message_archive.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = var.enable_kms_encryption ? aws_kms_key.fifo_processing_key[0].arn : null
      sse_algorithm     = var.enable_kms_encryption ? "aws:kms" : "AES256"
    }
    bucket_key_enabled = var.enable_kms_encryption
  }
}

# S3 bucket public access block for security
resource "aws_s3_bucket_public_access_block" "message_archive_pab" {
  bucket = aws_s3_bucket.message_archive.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket lifecycle configuration for cost optimization
resource "aws_s3_bucket_lifecycle_configuration" "message_archive_lifecycle" {
  bucket = aws_s3_bucket.message_archive.id

  rule {
    id     = "poison_message_lifecycle"
    status = "Enabled"

    filter {
      prefix = "poison-messages/"
    }

    transition {
      days          = var.s3_lifecycle_standard_ia_days
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = var.s3_lifecycle_glacier_days
      storage_class = "GLACIER"
    }
  }
}

# ============================================================================
# SNS Topic for Alerting
# ============================================================================

# SNS topic for operational alerts
resource "aws_sns_topic" "alerts" {
  name = local.sns_topic_name
  
  # Enable KMS encryption if specified
  kms_master_key_id = var.enable_kms_encryption ? aws_kms_key.fifo_processing_key[0].arn : null

  tags = merge(local.common_tags, {
    Name = local.sns_topic_name
  })
}

# Optional email subscription for alerts
resource "aws_sns_topic_subscription" "email_alerts" {
  count = var.notification_email != "" ? 1 : 0
  
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# ============================================================================
# SQS Dead Letter Queue (FIFO)
# ============================================================================

# Dead Letter Queue for failed messages
resource "aws_sqs_queue" "dlq" {
  name                       = local.dlq_name
  fifo_queue                = true
  content_based_deduplication = true
  message_retention_seconds  = var.message_retention_period
  visibility_timeout_seconds = var.dlq_visibility_timeout

  # Enable KMS encryption if specified
  kms_master_key_id                 = var.enable_kms_encryption ? aws_kms_key.fifo_processing_key[0].arn : null
  kms_data_key_reuse_period_seconds = var.enable_kms_encryption ? 300 : null

  tags = merge(local.common_tags, {
    Name = local.dlq_name
  })
}

# ============================================================================
# SQS Main FIFO Queue with Dead Letter Queue Configuration
# ============================================================================

# Main FIFO queue with advanced configuration
resource "aws_sqs_queue" "main_queue" {
  name                       = local.main_queue_name
  fifo_queue                = true
  content_based_deduplication = false # Using explicit deduplication for control
  deduplication_scope       = "messageGroup"
  fifo_throughput_limit     = "perMessageGroupId"
  message_retention_seconds = var.message_retention_period
  visibility_timeout_seconds = var.main_queue_visibility_timeout

  # Dead letter queue configuration
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = var.max_receive_count
  })

  # Enable KMS encryption if specified
  kms_master_key_id                 = var.enable_kms_encryption ? aws_kms_key.fifo_processing_key[0].arn : null
  kms_data_key_reuse_period_seconds = var.enable_kms_encryption ? 300 : null

  tags = merge(local.common_tags, {
    Name = local.main_queue_name
  })
}

# ============================================================================
# IAM Roles and Policies for Lambda Functions
# ============================================================================

# IAM role for message processor Lambda
resource "aws_iam_role" "processor_role" {
  name = "${local.project_name}-processor-role"

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
    Name = "${local.project_name}-processor-role"
  })
}

# Attach basic execution policy to processor role
resource "aws_iam_role_policy_attachment" "processor_basic_execution" {
  role       = aws_iam_role.processor_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Custom policy for message processor permissions
resource "aws_iam_role_policy" "processor_permissions" {
  name = "MessageProcessingAccess"
  role = aws_iam_role.processor_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:SendMessage"
        ]
        Resource = [
          aws_sqs_queue.main_queue.arn,
          aws_sqs_queue.dlq.arn
        ]
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
          aws_dynamodb_table.orders.arn,
          "${aws_dynamodb_table.orders.arn}/index/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
      },
      # KMS permissions if encryption is enabled
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = var.enable_kms_encryption ? [aws_kms_key.fifo_processing_key[0].arn] : []
      }
    ]
  })
}

# IAM role for poison message handler Lambda
resource "aws_iam_role" "poison_handler_role" {
  name = "${local.project_name}-poison-handler-role"

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
    Name = "${local.project_name}-poison-handler-role"
  })
}

# Attach basic execution policy to poison handler role
resource "aws_iam_role_policy_attachment" "poison_handler_basic_execution" {
  role       = aws_iam_role.poison_handler_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Custom policy for poison message handler permissions
resource "aws_iam_role_policy" "poison_handler_permissions" {
  name = "PoisonMessageHandlingAccess"
  role = aws_iam_role.poison_handler_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:SendMessage"
        ]
        Resource = [
          aws_sqs_queue.dlq.arn,
          aws_sqs_queue.main_queue.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject"
        ]
        Resource = "${aws_s3_bucket.message_archive.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.alerts.arn
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
      },
      # KMS permissions if encryption is enabled
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = var.enable_kms_encryption ? [aws_kms_key.fifo_processing_key[0].arn] : []
      }
    ]
  })
}

# ============================================================================
# Lambda Function Code Preparation
# ============================================================================

# Archive message processor Lambda code
data "archive_file" "message_processor_zip" {
  type        = "zip"
  output_path = "${path.module}/message_processor.zip"
  
  source {
    content = templatefile("${path.module}/lambda_code/message_processor.py.tpl", {
      order_table_name = aws_dynamodb_table.orders.name
    })
    filename = "message_processor.py"
  }
}

# Archive poison message handler Lambda code
data "archive_file" "poison_handler_zip" {
  type        = "zip"
  output_path = "${path.module}/poison_handler.zip"
  
  source {
    content = templatefile("${path.module}/lambda_code/poison_message_handler.py.tpl", {
      archive_bucket_name = aws_s3_bucket.message_archive.bucket
      sns_topic_arn      = aws_sns_topic.alerts.arn
      main_queue_url     = aws_sqs_queue.main_queue.url
    })
    filename = "poison_message_handler.py"
  }
}

# Archive message replay Lambda code
data "archive_file" "message_replay_zip" {
  type        = "zip"
  output_path = "${path.module}/message_replay.zip"
  
  source {
    content = templatefile("${path.module}/lambda_code/message_replay.py.tpl", {
      archive_bucket_name = aws_s3_bucket.message_archive.bucket
      main_queue_url     = aws_sqs_queue.main_queue.url
    })
    filename = "message_replay.py"
  }
}

# ============================================================================
# Lambda Functions
# ============================================================================

# Message Processor Lambda Function
resource "aws_lambda_function" "message_processor" {
  filename         = data.archive_file.message_processor_zip.output_path
  function_name    = "${local.project_name}-message-processor"
  role            = aws_iam_role.processor_role.arn
  handler         = "message_processor.lambda_handler"
  runtime         = "python3.9"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  reserved_concurrent_executions = var.lambda_reserved_concurrency

  source_code_hash = data.archive_file.message_processor_zip.output_base64sha256

  environment {
    variables = {
      ORDER_TABLE_NAME = aws_dynamodb_table.orders.name
    }
  }

  # Enable dead letter queue for Lambda function failures
  dead_letter_config {
    target_arn = aws_sqs_queue.dlq.arn
  }

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-message-processor"
  })

  depends_on = [
    aws_iam_role_policy_attachment.processor_basic_execution,
    aws_iam_role_policy.processor_permissions,
    aws_cloudwatch_log_group.processor_logs
  ]
}

# Poison Message Handler Lambda Function
resource "aws_lambda_function" "poison_handler" {
  filename         = data.archive_file.poison_handler_zip.output_path
  function_name    = "${local.project_name}-poison-handler"
  role            = aws_iam_role.poison_handler_role.arn
  handler         = "poison_message_handler.lambda_handler"
  runtime         = "python3.9"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size

  source_code_hash = data.archive_file.poison_handler_zip.output_base64sha256

  environment {
    variables = {
      ARCHIVE_BUCKET_NAME = aws_s3_bucket.message_archive.bucket
      SNS_TOPIC_ARN      = aws_sns_topic.alerts.arn
      MAIN_QUEUE_URL     = aws_sqs_queue.main_queue.url
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-poison-handler"
  })

  depends_on = [
    aws_iam_role_policy_attachment.poison_handler_basic_execution,
    aws_iam_role_policy.poison_handler_permissions,
    aws_cloudwatch_log_group.poison_handler_logs
  ]
}

# Message Replay Lambda Function
resource "aws_lambda_function" "message_replay" {
  filename         = data.archive_file.message_replay_zip.output_path
  function_name    = "${local.project_name}-message-replay"
  role            = aws_iam_role.poison_handler_role.arn # Reuse poison handler role
  handler         = "message_replay.lambda_handler"
  runtime         = "python3.9"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size

  source_code_hash = data.archive_file.message_replay_zip.output_base64sha256

  environment {
    variables = {
      ARCHIVE_BUCKET_NAME = aws_s3_bucket.message_archive.bucket
      MAIN_QUEUE_URL     = aws_sqs_queue.main_queue.url
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-message-replay"
  })

  depends_on = [
    aws_iam_role_policy_attachment.poison_handler_basic_execution,
    aws_iam_role_policy.poison_handler_permissions,
    aws_cloudwatch_log_group.replay_logs
  ]
}

# ============================================================================
# CloudWatch Log Groups for Lambda Functions
# ============================================================================

# Log group for message processor
resource "aws_cloudwatch_log_group" "processor_logs" {
  name              = "/aws/lambda/${local.project_name}-message-processor"
  retention_in_days = 14

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-processor-logs"
  })
}

# Log group for poison handler
resource "aws_cloudwatch_log_group" "poison_handler_logs" {
  name              = "/aws/lambda/${local.project_name}-poison-handler"
  retention_in_days = 14

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-poison-handler-logs"
  })
}

# Log group for message replay
resource "aws_cloudwatch_log_group" "replay_logs" {
  name              = "/aws/lambda/${local.project_name}-message-replay"
  retention_in_days = 14

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-replay-logs"
  })
}

# ============================================================================
# Lambda Event Source Mappings
# ============================================================================

# Event source mapping for main queue to message processor
resource "aws_lambda_event_source_mapping" "processor_trigger" {
  event_source_arn                   = aws_sqs_queue.main_queue.arn
  function_name                      = aws_lambda_function.message_processor.arn
  batch_size                         = var.processor_batch_size
  maximum_batching_window_in_seconds = var.maximum_batching_window

  depends_on = [
    aws_iam_role_policy.processor_permissions
  ]
}

# Event source mapping for DLQ to poison handler
resource "aws_lambda_event_source_mapping" "poison_handler_trigger" {
  event_source_arn                   = aws_sqs_queue.dlq.arn
  function_name                      = aws_lambda_function.poison_handler.arn
  batch_size                         = var.poison_handler_batch_size
  maximum_batching_window_in_seconds = var.maximum_batching_window

  depends_on = [
    aws_iam_role_policy.poison_handler_permissions
  ]
}

# ============================================================================
# CloudWatch Alarms for Monitoring
# ============================================================================

# Alarm for high message processing failure rate
resource "aws_cloudwatch_metric_alarm" "high_failure_rate" {
  alarm_name          = "${local.project_name}-high-failure-rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "FailedMessages"
  namespace           = "FIFO/MessageProcessing"
  period              = "300"
  statistic           = "Sum"
  threshold           = var.failure_rate_threshold
  alarm_description   = "High message processing failure rate detected"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    Environment = var.environment
  }

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-high-failure-rate"
  })
}

# Alarm for poison messages detected
resource "aws_cloudwatch_metric_alarm" "poison_messages_detected" {
  alarm_name          = "${local.project_name}-poison-messages-detected"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "PoisonMessageCount"
  namespace           = "FIFO/PoisonMessages"
  period              = "300"
  statistic           = "Sum"
  threshold           = "1"
  alarm_description   = "Poison messages detected in dead letter queue"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "notBreaching"

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-poison-messages-detected"
  })
}

# Alarm for high processing latency
resource "aws_cloudwatch_metric_alarm" "high_processing_latency" {
  alarm_name          = "${local.project_name}-high-processing-latency"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "ProcessingTime"
  namespace           = "FIFO/MessageProcessing"
  period              = "300"
  statistic           = "Average"
  threshold           = var.latency_threshold_ms
  alarm_description   = "High message processing latency detected"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-high-processing-latency"
  })
}