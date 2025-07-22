# Data sources for current AWS account and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource names
resource "random_password" "suffix" {
  length  = 6
  special = false
  upper   = false
}

locals {
  # Common name prefix for all resources
  name_prefix = "${var.project_name}-${var.environment}"
  
  # Resource-specific names with random suffix
  delivery_stream_name = "${local.name_prefix}-stream-${random_password.suffix.result}"
  lambda_function_name = "${local.name_prefix}-transform-${random_password.suffix.result}"
  
  # S3 bucket names (must be globally unique)
  raw_bucket_name       = "${local.name_prefix}-raw-${random_password.suffix.result}"
  processed_bucket_name = "${local.name_prefix}-processed-${random_password.suffix.result}"
  error_bucket_name     = "${local.name_prefix}-errors-${random_password.suffix.result}"
  
  # IAM role names
  lambda_role_name    = "${local.name_prefix}-lambda-role-${random_password.suffix.result}"
  firehose_role_name  = "${local.name_prefix}-firehose-role-${random_password.suffix.result}"
  
  # SNS topic name
  sns_topic_name = "${local.name_prefix}-alarms-${random_password.suffix.result}"
  
  # Common tags
  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
    },
    var.tags
  )
}

# ============================================================================
# S3 BUCKETS
# ============================================================================

# Raw data backup bucket
resource "aws_s3_bucket" "raw_data" {
  bucket = local.raw_bucket_name
  tags   = local.common_tags
}

# Processed data destination bucket
resource "aws_s3_bucket" "processed_data" {
  bucket = local.processed_bucket_name
  tags   = local.common_tags
}

# Error/failed data bucket (Dead Letter Queue)
resource "aws_s3_bucket" "error_data" {
  bucket = local.error_bucket_name
  tags   = local.common_tags
}

# S3 bucket encryption configuration
resource "aws_s3_bucket_server_side_encryption_configuration" "raw_data" {
  count  = var.enable_s3_encryption ? 1 : 0
  bucket = aws_s3_bucket.raw_data.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "processed_data" {
  count  = var.enable_s3_encryption ? 1 : 0
  bucket = aws_s3_bucket.processed_data.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "error_data" {
  count  = var.enable_s3_encryption ? 1 : 0
  bucket = aws_s3_bucket.error_data.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 bucket versioning
resource "aws_s3_bucket_versioning" "raw_data" {
  bucket = aws_s3_bucket.raw_data.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_versioning" "processed_data" {
  bucket = aws_s3_bucket.processed_data.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_versioning" "error_data" {
  bucket = aws_s3_bucket.error_data.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket public access block
resource "aws_s3_bucket_public_access_block" "raw_data" {
  bucket = aws_s3_bucket.raw_data.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "processed_data" {
  bucket = aws_s3_bucket.processed_data.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "error_data" {
  bucket = aws_s3_bucket.error_data.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ============================================================================
# IAM ROLES AND POLICIES
# ============================================================================

# Lambda execution role
resource "aws_iam_role" "lambda_execution" {
  name = local.lambda_role_name

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

  tags = local.common_tags
}

# Lambda execution policy
resource "aws_iam_role_policy" "lambda_execution" {
  name = "lambda-execution-policy"
  role = aws_iam_role.lambda_execution.id

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
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "firehose:DescribeDeliveryStream",
          "firehose:ListDeliveryStreams",
          "firehose:ListTagsForDeliveryStream"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:AbortMultipartUpload",
          "s3:GetBucketLocation",
          "s3:GetObject",
          "s3:ListBucket",
          "s3:ListBucketMultipartUploads",
          "s3:PutObject"
        ]
        Resource = [
          aws_s3_bucket.error_data.arn,
          "${aws_s3_bucket.error_data.arn}/*",
          aws_s3_bucket.processed_data.arn,
          "${aws_s3_bucket.processed_data.arn}/*"
        ]
      }
    ]
  })
}

# Kinesis Firehose service role
resource "aws_iam_role" "firehose_delivery" {
  name = local.firehose_role_name

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

  tags = local.common_tags
}

# Kinesis Firehose delivery policy
resource "aws_iam_role_policy" "firehose_delivery" {
  name = "firehose-delivery-policy"
  role = aws_iam_role.firehose_delivery.id

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
          "s3:PutObject"
        ]
        Resource = [
          aws_s3_bucket.raw_data.arn,
          "${aws_s3_bucket.raw_data.arn}/*",
          aws_s3_bucket.processed_data.arn,
          "${aws_s3_bucket.processed_data.arn}/*",
          aws_s3_bucket.error_data.arn,
          "${aws_s3_bucket.error_data.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction",
          "lambda:GetFunctionConfiguration"
        ]
        Resource = "${aws_lambda_function.transform.arn}:*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:PutLogEvents",
          "logs:CreateLogGroup",
          "logs:CreateLogStream"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "kinesis:DescribeStream",
          "kinesis:GetShardIterator",
          "kinesis:GetRecords",
          "kinesis:ListShards"
        ]
        Resource = "arn:aws:kinesis:*:*:stream/*"
      }
    ]
  })
}

# ============================================================================
# LAMBDA FUNCTION
# ============================================================================

# Create Lambda function code
data "archive_file" "lambda_transform" {
  type        = "zip"
  output_path = "${path.module}/lambda_transform.zip"
  
  source {
    content = templatefile("${path.module}/lambda_transform.js", {
      min_log_level         = var.min_log_level
      fields_to_redact      = jsonencode(var.fields_to_redact)
      add_processing_timestamp = true
    })
    filename = "index.js"
  }
}

# Lambda function for data transformation
resource "aws_lambda_function" "transform" {
  filename         = data.archive_file.lambda_transform.output_path
  function_name    = local.lambda_function_name
  role            = aws_iam_role.lambda_execution.arn
  handler         = "index.handler"
  runtime         = "nodejs18.x"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.lambda_transform.output_base64sha256

  description = "Transform function for Kinesis Data Firehose - filters, enriches, and redacts log data"

  environment {
    variables = {
      MIN_LOG_LEVEL         = var.min_log_level
      FIELDS_TO_REDACT      = jsonencode(var.fields_to_redact)
      ADD_PROCESSING_TIMESTAMP = "true"
    }
  }

  tags = local.common_tags

  depends_on = [
    aws_iam_role_policy.lambda_execution,
    aws_cloudwatch_log_group.lambda_logs
  ]
}

# CloudWatch Log Group for Lambda
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${local.lambda_function_name}"
  retention_in_days = 14
  tags              = local.common_tags
}

# ============================================================================
# KINESIS DATA FIREHOSE
# ============================================================================

# CloudWatch Log Group for Firehose
resource "aws_cloudwatch_log_group" "firehose_logs" {
  count             = var.enable_cloudwatch_logs ? 1 : 0
  name              = "/aws/kinesisfirehose/${local.delivery_stream_name}"
  retention_in_days = 14
  tags              = local.common_tags
}

# Kinesis Data Firehose delivery stream
resource "aws_kinesis_firehose_delivery_stream" "log_processing" {
  name        = local.delivery_stream_name
  destination = "extended_s3"

  extended_s3_configuration {
    # IAM role for S3 delivery
    role_arn = aws_iam_role.firehose_delivery.arn
    
    # Primary destination bucket
    bucket_arn = aws_s3_bucket.processed_data.arn
    
    # S3 prefix with timestamp partitioning for optimal query performance
    prefix = "logs/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/"
    
    # Error output prefix
    error_output_prefix = "errors/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/!{firehose:error-output-type}/"
    
    # Buffering hints - balance between latency and efficiency
    buffering_size     = var.firehose_buffer_size
    buffering_interval = var.firehose_buffer_interval
    
    # Compression format
    compression_format = var.s3_compression_format
    
    # Enable S3 backup of raw data
    s3_backup_mode = "Enabled"
    
    # S3 backup configuration
    s3_backup_configuration {
      role_arn           = aws_iam_role.firehose_delivery.arn
      bucket_arn         = aws_s3_bucket.raw_data.arn
      prefix             = "raw/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/"
      buffering_size     = var.firehose_buffer_size
      buffering_interval = var.firehose_buffer_interval
      compression_format = var.s3_compression_format
    }
    
    # Data transformation with Lambda
    processing_configuration {
      enabled = true
      
      processors {
        type = "Lambda"
        
        parameters {
          parameter_name  = "LambdaArn"
          parameter_value = "${aws_lambda_function.transform.arn}:$LATEST"
        }
        
        parameters {
          parameter_name  = "BufferSizeInMBs"
          parameter_value = tostring(var.lambda_buffer_size)
        }
        
        parameters {
          parameter_name  = "BufferIntervalInSeconds"
          parameter_value = tostring(var.firehose_buffer_interval)
        }
      }
    }
    
    # CloudWatch logging configuration
    dynamic "cloudwatch_logging_options" {
      for_each = var.enable_cloudwatch_logs ? [1] : []
      content {
        enabled         = true
        log_group_name  = aws_cloudwatch_log_group.firehose_logs[0].name
        log_stream_name = "S3Delivery"
      }
    }
  }

  tags = local.common_tags

  depends_on = [
    aws_iam_role_policy.firehose_delivery,
    aws_lambda_function.transform
  ]
}

# ============================================================================
# SNS TOPIC FOR NOTIFICATIONS
# ============================================================================

# SNS topic for alarm notifications
resource "aws_sns_topic" "firehose_alarms" {
  count = var.enable_monitoring ? 1 : 0
  name  = local.sns_topic_name
  tags  = local.common_tags
}

# SNS topic policy
resource "aws_sns_topic_policy" "firehose_alarms" {
  count = var.enable_monitoring ? 1 : 0
  arn   = aws_sns_topic.firehose_alarms[0].arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "cloudwatch.amazonaws.com"
        }
        Action = "SNS:Publish"
        Resource = aws_sns_topic.firehose_alarms[0].arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

# Email subscription (if email provided)
resource "aws_sns_topic_subscription" "email_notifications" {
  count     = var.enable_monitoring && var.notification_email != null ? 1 : 0
  topic_arn = aws_sns_topic.firehose_alarms[0].arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# ============================================================================
# CLOUDWATCH MONITORING AND ALARMS
# ============================================================================

# CloudWatch alarm for delivery failures
resource "aws_cloudwatch_metric_alarm" "delivery_failure" {
  count = var.enable_monitoring ? 1 : 0
  
  alarm_name          = "FirehoseDeliveryFailure-${local.delivery_stream_name}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "DeliveryToS3.DataFreshness"
  namespace           = "AWS/Kinesis/Firehose"
  period              = "300"
  statistic           = "Maximum"
  threshold           = tostring(var.data_freshness_threshold)
  alarm_description   = "This metric monitors data freshness for Kinesis Firehose delivery stream"
  alarm_actions       = [aws_sns_topic.firehose_alarms[0].arn]
  ok_actions          = [aws_sns_topic.firehose_alarms[0].arn]
  treat_missing_data  = "breaching"

  dimensions = {
    DeliveryStreamName = aws_kinesis_firehose_delivery_stream.log_processing.name
  }

  tags = local.common_tags
}

# CloudWatch alarm for transformation errors
resource "aws_cloudwatch_metric_alarm" "transformation_errors" {
  count = var.enable_monitoring ? 1 : 0
  
  alarm_name          = "FirehoseTransformationErrors-${local.delivery_stream_name}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "DeliveryToS3.ProcessingFailed"
  namespace           = "AWS/Kinesis/Firehose"
  period              = "300"
  statistic           = "Sum"
  threshold           = "10"
  alarm_description   = "This metric monitors transformation errors in Kinesis Firehose"
  alarm_actions       = [aws_sns_topic.firehose_alarms[0].arn]
  ok_actions          = [aws_sns_topic.firehose_alarms[0].arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    DeliveryStreamName = aws_kinesis_firehose_delivery_stream.log_processing.name
  }

  tags = local.common_tags
}

# CloudWatch alarm for Lambda function errors
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  count = var.enable_monitoring ? 1 : 0
  
  alarm_name          = "LambdaTransformErrors-${local.lambda_function_name}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "This metric monitors errors in the Lambda transformation function"
  alarm_actions       = [aws_sns_topic.firehose_alarms[0].arn]
  ok_actions          = [aws_sns_topic.firehose_alarms[0].arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.transform.function_name
  }

  tags = local.common_tags
}

# CloudWatch alarm for Lambda function duration
resource "aws_cloudwatch_metric_alarm" "lambda_duration" {
  count = var.enable_monitoring ? 1 : 0
  
  alarm_name          = "LambdaTransformDuration-${local.lambda_function_name}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Average"
  threshold           = tostring(var.lambda_timeout * 1000 * 0.8) # 80% of timeout in milliseconds
  alarm_description   = "This metric monitors Lambda function duration approaching timeout"
  alarm_actions       = [aws_sns_topic.firehose_alarms[0].arn]
  ok_actions          = [aws_sns_topic.firehose_alarms[0].arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.transform.function_name
  }

  tags = local.common_tags
}