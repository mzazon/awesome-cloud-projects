# Real-Time Data Processing with Amazon Kinesis and Lambda
# Terraform configuration for deploying a complete serverless real-time data processing pipeline

# Data source to get current AWS account ID and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  # Common naming convention for resources
  name_prefix = "${var.project_name}-${var.environment}"
  
  # Resource names with random suffix for uniqueness
  kinesis_stream_name   = "${local.name_prefix}-stream-${random_id.suffix.hex}"
  lambda_function_name  = "${local.name_prefix}-processor-${random_id.suffix.hex}"
  dynamodb_table_name   = "${local.name_prefix}-data-${random_id.suffix.hex}"
  dlq_queue_name        = "${local.name_prefix}-dlq-${random_id.suffix.hex}"
  alarm_name           = "${local.name_prefix}-errors-${random_id.suffix.hex}"
  
  # Common tags for all resources
  common_tags = merge(
    {
      Name        = local.name_prefix
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Recipe      = "real-time-data-processing-with-kinesis-lambda"
    },
    var.additional_tags
  )
}

#------------------------------------------------------------------------------
# KINESIS DATA STREAM
#------------------------------------------------------------------------------

# Kinesis Data Stream for ingesting real-time event data
resource "aws_kinesis_stream" "retail_events_stream" {
  name             = local.kinesis_stream_name
  shard_count      = var.kinesis_shard_count
  retention_period = var.kinesis_retention_period

  # Enable shard-level metrics for monitoring
  shard_level_metrics = var.kinesis_shard_level_metrics

  # Server-side encryption using AWS managed keys
  encryption_type = "KMS"
  kms_key_id      = "alias/aws/kinesis"

  # Stream mode configuration
  stream_mode_details {
    stream_mode = "PROVISIONED"
  }

  tags = merge(local.common_tags, {
    ResourceType = "KinesisStream"
  })
}

#------------------------------------------------------------------------------
# DYNAMODB TABLE
#------------------------------------------------------------------------------

# DynamoDB table for storing processed event data
resource "aws_dynamodb_table" "retail_events_data" {
  name           = local.dynamodb_table_name
  billing_mode   = var.dynamodb_billing_mode
  hash_key       = "userId"
  range_key      = "eventTimestamp"

  # Capacity configuration (only used with PROVISIONED billing mode)
  read_capacity  = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_read_capacity : null
  write_capacity = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_write_capacity : null

  # Table schema definition
  attribute {
    name = "userId"
    type = "S"
  }

  attribute {
    name = "eventTimestamp"
    type = "N"
  }

  attribute {
    name = "eventType"
    type = "S"
  }

  attribute {
    name = "productId"
    type = "S"
  }

  # Global Secondary Index for querying by event type
  global_secondary_index {
    name               = "EventTypeIndex"
    hash_key           = "eventType"
    range_key          = "eventTimestamp"
    projection_type    = "ALL"
    read_capacity      = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_read_capacity : null
    write_capacity     = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_write_capacity : null
  }

  # Global Secondary Index for querying by product
  global_secondary_index {
    name               = "ProductIndex"
    hash_key           = "productId"
    range_key          = "eventTimestamp"
    projection_type    = "ALL"
    read_capacity      = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_read_capacity : null
    write_capacity     = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_write_capacity : null
  }

  # Enable point-in-time recovery for data protection
  point_in_time_recovery {
    enabled = var.dynamodb_point_in_time_recovery_enabled
  }

  # Server-side encryption configuration
  server_side_encryption {
    enabled     = var.dynamodb_server_side_encryption_enabled
    kms_key_arn = var.dynamodb_server_side_encryption_enabled ? aws_kms_key.dynamodb_key[0].arn : null
  }

  tags = merge(local.common_tags, {
    ResourceType = "DynamoDBTable"
  })
}

# KMS key for DynamoDB encryption (only created if encryption is enabled)
resource "aws_kms_key" "dynamodb_key" {
  count = var.dynamodb_server_side_encryption_enabled ? 1 : 0

  description             = "KMS key for DynamoDB table encryption"
  deletion_window_in_days = 7

  tags = merge(local.common_tags, {
    ResourceType = "KMSKey"
    Purpose      = "DynamoDBEncryption"
  })
}

# KMS key alias for easier management
resource "aws_kms_alias" "dynamodb_key_alias" {
  count = var.dynamodb_server_side_encryption_enabled ? 1 : 0

  name          = "alias/${local.dynamodb_table_name}-key"
  target_key_id = aws_kms_key.dynamodb_key[0].key_id
}

#------------------------------------------------------------------------------
# SQS DEAD LETTER QUEUE
#------------------------------------------------------------------------------

# SQS queue for handling failed event processing
resource "aws_sqs_queue" "failed_events_dlq" {
  name                      = local.dlq_queue_name
  message_retention_seconds = var.sqs_message_retention_seconds
  visibility_timeout_seconds = var.sqs_visibility_timeout_seconds

  # Server-side encryption using SQS managed keys
  sqs_managed_sse_enabled = true

  tags = merge(local.common_tags, {
    ResourceType = "SQSQueue"
    Purpose      = "DeadLetterQueue"
  })
}

#------------------------------------------------------------------------------
# IAM ROLES AND POLICIES
#------------------------------------------------------------------------------

# IAM role for Lambda function execution
resource "aws_iam_role" "lambda_execution_role" {
  name = "${local.lambda_function_name}-role"

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
    ResourceType = "IAMRole"
    Purpose      = "LambdaExecution"
  })
}

# Custom IAM policy for Lambda function permissions
resource "aws_iam_policy" "lambda_policy" {
  name        = "${local.lambda_function_name}-policy"
  description = "IAM policy for Lambda function to access Kinesis, DynamoDB, SQS, and CloudWatch"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kinesis:DescribeStream",
          "kinesis:GetRecords",
          "kinesis:GetShardIterator",
          "kinesis:ListShards"
        ]
        Resource = aws_kinesis_stream.retail_events_stream.arn
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
          aws_dynamodb_table.retail_events_data.arn,
          "${aws_dynamodb_table.retail_events_data.arn}/index/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = aws_sqs_queue.failed_events_dlq.arn
      },
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
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "cloudwatch:namespace" = "RetailEventProcessing"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords"
        ]
        Resource = "*"
      }
    ]
  })

  tags = merge(local.common_tags, {
    ResourceType = "IAMPolicy"
    Purpose      = "LambdaPermissions"
  })
}

# Attach custom policy to Lambda role
resource "aws_iam_role_policy_attachment" "lambda_policy_attachment" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

# Attach AWS managed policy for basic Lambda execution
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

#------------------------------------------------------------------------------
# LAMBDA FUNCTION
#------------------------------------------------------------------------------

# CloudWatch Log Group for Lambda function logs
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${local.lambda_function_name}"
  retention_in_days = 14

  tags = merge(local.common_tags, {
    ResourceType = "CloudWatchLogGroup"
    Purpose      = "LambdaLogs"
  })
}

# Create ZIP file for Lambda function code
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda_function.zip"
  
  source {
    content = templatefile("${path.module}/lambda_function.py.tpl", {
      dynamodb_table_name = local.dynamodb_table_name
      dlq_queue_url      = aws_sqs_queue.failed_events_dlq.url
    })
    filename = "lambda_function.py"
  }
}

# Lambda function for processing Kinesis stream records
resource "aws_lambda_function" "retail_event_processor" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = local.lambda_function_name
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = "python3.9"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  # Reserved concurrency configuration
  reserved_concurrent_executions = var.lambda_reserved_concurrency == -1 ? null : var.lambda_reserved_concurrency

  # Environment variables for Lambda function
  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.retail_events_data.name
      DLQ_URL        = aws_sqs_queue.failed_events_dlq.url
      AWS_REGION     = data.aws_region.current.name
    }
  }

  # Enable X-Ray tracing for monitoring and debugging
  tracing_config {
    mode = "Active"
  }

  # Ensure log group is created before the function
  depends_on = [aws_cloudwatch_log_group.lambda_logs]

  tags = merge(local.common_tags, {
    ResourceType = "LambdaFunction"
    Purpose      = "StreamProcessor"
  })
}

# Event source mapping to connect Lambda to Kinesis stream
resource "aws_lambda_event_source_mapping" "kinesis_trigger" {
  event_source_arn          = aws_kinesis_stream.retail_events_stream.arn
  function_name             = aws_lambda_function.retail_event_processor.arn
  starting_position         = var.lambda_starting_position
  batch_size                = var.lambda_batch_size
  maximum_batching_window_in_seconds = var.lambda_maximum_batching_window_in_seconds

  # Parallelization configuration for better throughput
  parallelization_factor = 1

  # Error handling configuration
  maximum_retry_attempts = 3
  
  # Tumbling window configuration for aggregation
  tumbling_window_in_seconds = 0

  depends_on = [aws_iam_role_policy_attachment.lambda_policy_attachment]
}

#------------------------------------------------------------------------------
# CLOUDWATCH MONITORING
#------------------------------------------------------------------------------

# CloudWatch metric alarm for monitoring failed events
resource "aws_cloudwatch_metric_alarm" "stream_processing_errors" {
  alarm_name          = local.alarm_name
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.cloudwatch_alarm_evaluation_periods
  metric_name         = "FailedEvents"
  namespace           = "RetailEventProcessing"
  period              = var.cloudwatch_alarm_period_seconds
  statistic           = "Sum"
  threshold           = var.cloudwatch_alarm_threshold
  alarm_description   = "Alert when too many events fail processing"
  alarm_actions       = var.sns_email_endpoint != "" ? [aws_sns_topic.alert_topic[0].arn] : []
  ok_actions         = var.sns_email_endpoint != "" ? [aws_sns_topic.alert_topic[0].arn] : []
  treat_missing_data = "notBreaching"

  tags = merge(local.common_tags, {
    ResourceType = "CloudWatchAlarm"
    Purpose      = "ErrorMonitoring"
  })
}

# Additional CloudWatch alarms for comprehensive monitoring
resource "aws_cloudwatch_metric_alarm" "lambda_duration" {
  alarm_name          = "${local.alarm_name}-duration"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Average"
  threshold           = var.lambda_timeout * 1000 * 0.8 # 80% of timeout in milliseconds
  alarm_description   = "Alert when Lambda function duration is high"
  treat_missing_data = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.retail_event_processor.function_name
  }

  alarm_actions = var.sns_email_endpoint != "" ? [aws_sns_topic.alert_topic[0].arn] : []

  tags = merge(local.common_tags, {
    ResourceType = "CloudWatchAlarm"
    Purpose      = "PerformanceMonitoring"
  })
}

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "${local.alarm_name}-lambda-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 5
  alarm_description   = "Alert when Lambda function has errors"
  treat_missing_data = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.retail_event_processor.function_name
  }

  alarm_actions = var.sns_email_endpoint != "" ? [aws_sns_topic.alert_topic[0].arn] : []

  tags = merge(local.common_tags, {
    ResourceType = "CloudWatchAlarm"
    Purpose      = "ErrorMonitoring"
  })
}

#------------------------------------------------------------------------------
# SNS TOPIC FOR NOTIFICATIONS (OPTIONAL)
#------------------------------------------------------------------------------

# SNS topic for alarm notifications (only created if email is provided)
resource "aws_sns_topic" "alert_topic" {
  count = var.sns_email_endpoint != "" ? 1 : 0

  name         = "${local.name_prefix}-alerts-${random_id.suffix.hex}"
  display_name = "Retail Event Processing Alerts"

  # Server-side encryption
  kms_master_key_id = "alias/aws/sns"

  tags = merge(local.common_tags, {
    ResourceType = "SNSTopic"
    Purpose      = "AlertNotifications"
  })
}

# Email subscription for SNS topic
resource "aws_sns_topic_subscription" "email_alert" {
  count = var.sns_email_endpoint != "" ? 1 : 0

  topic_arn = aws_sns_topic.alert_topic[0].arn
  protocol  = "email"
  endpoint  = var.sns_email_endpoint
}

#------------------------------------------------------------------------------
# TEST DATA PRODUCER (OPTIONAL)
#------------------------------------------------------------------------------

# Create a test data producer script
resource "local_file" "test_data_producer" {
  content = templatefile("${path.module}/test_data_producer.py.tpl", {
    kinesis_stream_name = aws_kinesis_stream.retail_events_stream.name
    aws_region         = data.aws_region.current.name
  })
  filename = "${path.module}/test_data_producer.py"
}

#------------------------------------------------------------------------------
# LAMBDA FUNCTION CODE TEMPLATE
#------------------------------------------------------------------------------

# Lambda function code template
resource "local_file" "lambda_function_template" {
  content = templatefile("${path.module}/lambda_function.py.tpl", {
    dynamodb_table_name = local.dynamodb_table_name
    dlq_queue_url      = aws_sqs_queue.failed_events_dlq.url
  })
  filename = "${path.module}/lambda_function.py"
}