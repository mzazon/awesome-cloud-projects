# Main Terraform configuration for DynamoDB Streams real-time processing

# Data sources for current AWS account and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  # Common naming convention
  name_prefix = "${var.project_name}-${var.environment}"
  
  # Resource names with random suffix for uniqueness
  table_name          = "${var.table_name}-${random_id.suffix.hex}"
  function_name       = "${local.name_prefix}-processor-${random_id.suffix.hex}"
  role_name          = "${local.name_prefix}-role-${random_id.suffix.hex}"
  policy_name        = "${local.name_prefix}-policy-${random_id.suffix.hex}"
  sns_topic_name     = "${local.name_prefix}-notifications-${random_id.suffix.hex}"
  dlq_name           = "${local.name_prefix}-dlq-${random_id.suffix.hex}"
  s3_bucket_name     = var.s3_bucket_name != "" ? var.s3_bucket_name : "${local.name_prefix}-audit-${random_id.suffix.hex}"
  
  # Common tags
  common_tags = merge(var.tags, {
    Project     = var.project_name
    Environment = var.environment
    Component   = "DynamoDBStreams"
  })
}

# DynamoDB table with streams enabled
resource "aws_dynamodb_table" "user_activities" {
  name           = local.table_name
  billing_mode   = "PROVISIONED"
  read_capacity  = var.read_capacity
  write_capacity = var.write_capacity
  hash_key       = "UserId"
  range_key      = "ActivityId"

  # Primary key attributes
  attribute {
    name = "UserId"
    type = "S"
  }

  attribute {
    name = "ActivityId"
    type = "S"
  }

  # Enable DynamoDB Streams with NEW_AND_OLD_IMAGES view type
  stream_enabled   = true
  stream_view_type = var.stream_view_type

  # Point-in-time recovery for data protection
  point_in_time_recovery {
    enabled = true
  }

  # Server-side encryption
  server_side_encryption {
    enabled = true
  }

  tags = merge(local.common_tags, {
    Name = local.table_name
    Type = "DynamoDBTable"
  })

  lifecycle {
    prevent_destroy = false
  }
}

# S3 bucket for audit logs
resource "aws_s3_bucket" "audit_logs" {
  bucket = local.s3_bucket_name

  tags = merge(local.common_tags, {
    Name = local.s3_bucket_name
    Type = "S3Bucket"
  })
}

# S3 bucket versioning
resource "aws_s3_bucket_versioning" "audit_logs" {
  bucket = aws_s3_bucket.audit_logs.id
  versioning_configuration {
    status = var.enable_s3_versioning ? "Enabled" : "Disabled"
  }
}

# S3 bucket server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "audit_logs" {
  bucket = aws_s3_bucket.audit_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# S3 bucket public access block (security best practice)
resource "aws_s3_bucket_public_access_block" "audit_logs" {
  bucket = aws_s3_bucket.audit_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket lifecycle configuration
resource "aws_s3_bucket_lifecycle_configuration" "audit_logs" {
  bucket = aws_s3_bucket.audit_logs.id

  rule {
    id     = "transition_to_ia"
    status = "Enabled"

    transition {
      days          = var.s3_lifecycle_transition_days
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = var.s3_lifecycle_transition_days * 2
      storage_class = "GLACIER"
    }

    expiration {
      days = 2555 # ~7 years retention
    }

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

# SNS topic for notifications
resource "aws_sns_topic" "notifications" {
  name = local.sns_topic_name

  # Enable server-side encryption
  kms_master_key_id = "alias/aws/sns"

  tags = merge(local.common_tags, {
    Name = local.sns_topic_name
    Type = "SNSTopic"
  })
}

# SNS topic policy to allow CloudWatch to publish alarms
resource "aws_sns_topic_policy" "notifications" {
  arn = aws_sns_topic.notifications.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "cloudwatch.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.notifications.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

# Optional email subscription for SNS topic
resource "aws_sns_topic_subscription" "email" {
  count     = var.enable_email_notifications && var.notification_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.notifications.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# SQS Dead Letter Queue
resource "aws_sqs_queue" "dlq" {
  name = local.dlq_name

  # Message retention period (14 days)
  message_retention_seconds = var.dlq_message_retention_period

  # Enable server-side encryption
  kms_master_key_id = "alias/aws/sqs"

  tags = merge(local.common_tags, {
    Name = local.dlq_name
    Type = "SQSQueue"
  })
}

# IAM role for Lambda function
resource "aws_iam_role" "lambda_execution" {
  name = local.role_name

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
    Name = local.role_name
    Type = "IAMRole"
  })
}

# Attach AWS managed policy for DynamoDB stream execution
resource "aws_iam_role_policy_attachment" "lambda_dynamodb_execution" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaDynamoDBExecutionRole"
}

# Custom IAM policy for SNS and S3 access
resource "aws_iam_policy" "lambda_custom" {
  name        = local.policy_name
  description = "Custom policy for Lambda stream processor"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.notifications.arn
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:PutObjectAcl"
        ]
        Resource = "${aws_s3_bucket.audit_logs.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage"
        ]
        Resource = aws_sqs_queue.dlq.arn
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = local.policy_name
    Type = "IAMPolicy"
  })
}

# Attach custom policy to Lambda role
resource "aws_iam_role_policy_attachment" "lambda_custom" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = aws_iam_policy.lambda_custom.arn
}

# Create Lambda function code as a zip file
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda_function.zip"
  
  source {
    content = templatefile("${path.module}/lambda_function.py", {
      sns_topic_arn   = aws_sns_topic.notifications.arn
      s3_bucket_name  = aws_s3_bucket.audit_logs.bucket
    })
    filename = "lambda_function.py"
  }
}

# CloudWatch log group for Lambda function
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${local.function_name}"
  retention_in_days = var.cloudwatch_log_retention_days

  tags = merge(local.common_tags, {
    Name = "/aws/lambda/${local.function_name}"
    Type = "CloudWatchLogGroup"
  })
}

# Lambda function
resource "aws_lambda_function" "stream_processor" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = local.function_name
  role            = aws_iam_role.lambda_execution.arn
  handler         = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  description     = "Processes DynamoDB stream records for real-time change processing"

  environment {
    variables = {
      SNS_TOPIC_ARN  = aws_sns_topic.notifications.arn
      S3_BUCKET_NAME = aws_s3_bucket.audit_logs.bucket
    }
  }

  # Dead letter queue configuration
  dead_letter_config {
    target_arn = aws_sqs_queue.dlq.arn
  }

  # VPC configuration (optional - not configured for simplicity)
  # vpc_config {
  #   subnet_ids         = var.subnet_ids
  #   security_group_ids = var.security_group_ids
  # }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_dynamodb_execution,
    aws_iam_role_policy_attachment.lambda_custom,
    aws_cloudwatch_log_group.lambda_logs
  ]

  tags = merge(local.common_tags, {
    Name = local.function_name
    Type = "LambdaFunction"
  })
}

# Event source mapping for DynamoDB stream
resource "aws_lambda_event_source_mapping" "dynamodb_stream" {
  event_source_arn                   = aws_dynamodb_table.user_activities.stream_arn
  function_name                      = aws_lambda_function.stream_processor.arn
  starting_position                  = "LATEST"
  batch_size                         = var.batch_size
  maximum_batching_window_in_seconds = var.maximum_batching_window_in_seconds
  maximum_record_age_in_seconds      = var.maximum_record_age_in_seconds
  bisect_batch_on_function_error     = true
  maximum_retry_attempts             = var.maximum_retry_attempts
  parallelization_factor             = var.parallelization_factor

  # Destination configuration for failed records
  destination_config {
    on_failure {
      destination_arn = aws_sqs_queue.dlq.arn
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_dynamodb_execution,
    aws_iam_role_policy_attachment.lambda_custom
  ]
}

# CloudWatch alarm for Lambda errors
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "${local.function_name}-errors"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "1"
  alarm_description   = "This metric monitors Lambda function errors"
  alarm_actions       = [aws_sns_topic.notifications.arn]

  dimensions = {
    FunctionName = aws_lambda_function.stream_processor.function_name
  }

  tags = merge(local.common_tags, {
    Name = "${local.function_name}-errors"
    Type = "CloudWatchAlarm"
  })
}

# CloudWatch alarm for Dead Letter Queue messages
resource "aws_cloudwatch_metric_alarm" "dlq_messages" {
  alarm_name          = "${local.function_name}-dlq-messages"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "ApproximateNumberOfVisibleMessages"
  namespace           = "AWS/SQS"
  period              = "300"
  statistic           = "Average"
  threshold           = "1"
  alarm_description   = "This metric monitors messages in the dead letter queue"
  alarm_actions       = [aws_sns_topic.notifications.arn]

  dimensions = {
    QueueName = aws_sqs_queue.dlq.name
  }

  tags = merge(local.common_tags, {
    Name = "${local.function_name}-dlq-messages"
    Type = "CloudWatchAlarm"
  })
}

# CloudWatch alarm for Lambda duration
resource "aws_cloudwatch_metric_alarm" "lambda_duration" {
  alarm_name          = "${local.function_name}-duration"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Average"
  threshold           = var.lambda_timeout * 1000 * 0.8 # 80% of timeout in milliseconds
  alarm_description   = "This metric monitors Lambda function duration"
  alarm_actions       = [aws_sns_topic.notifications.arn]

  dimensions = {
    FunctionName = aws_lambda_function.stream_processor.function_name
  }

  tags = merge(local.common_tags, {
    Name = "${local.function_name}-duration"
    Type = "CloudWatchAlarm"
  })
}

# CloudWatch alarm for DynamoDB throttles
resource "aws_cloudwatch_metric_alarm" "dynamodb_throttles" {
  alarm_name          = "${local.table_name}-throttles"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "UserErrors"
  namespace           = "AWS/DynamoDB"
  period              = "300"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "This metric monitors DynamoDB throttling events"
  alarm_actions       = [aws_sns_topic.notifications.arn]

  dimensions = {
    TableName = aws_dynamodb_table.user_activities.name
  }

  tags = merge(local.common_tags, {
    Name = "${local.table_name}-throttles"
    Type = "CloudWatchAlarm"
  })
}