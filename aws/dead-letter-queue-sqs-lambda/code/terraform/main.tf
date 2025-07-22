# Dead Letter Queue Processing with SQS Infrastructure

# Data sources for current AWS account and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Resource naming with random suffix
  main_queue_name = var.main_queue_name != "" ? var.main_queue_name : "${var.project_name}-${random_id.suffix.hex}"
  dlq_name        = var.dlq_name != "" ? var.dlq_name : "${var.project_name}-dlq-${random_id.suffix.hex}"
  
  # Common tags
  common_tags = merge(var.tags, {
    Project     = var.project_name
    Environment = var.environment
    Recipe      = "dead-letter-queue-processing-sqs-lambda"
  })
}

# Dead Letter Queue (created first for main queue dependency)
resource "aws_sqs_queue" "dlq" {
  name                      = local.dlq_name
  visibility_timeout_seconds = var.dlq_visibility_timeout
  message_retention_seconds = var.message_retention_period
  
  tags = merge(local.common_tags, {
    Name = local.dlq_name
    Type = "DeadLetterQueue"
  })
}

# Main Processing Queue with DLQ configuration
resource "aws_sqs_queue" "main" {
  name                      = local.main_queue_name
  visibility_timeout_seconds = var.main_queue_visibility_timeout
  message_retention_seconds = var.message_retention_period
  
  # Dead letter queue redrive policy
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = var.max_receive_count
  })
  
  tags = merge(local.common_tags, {
    Name = local.main_queue_name
    Type = "MainProcessingQueue"
  })
}

# IAM role for Lambda functions
resource "aws_iam_role" "lambda_role" {
  name = "${var.project_name}-lambda-role-${random_id.suffix.hex}"
  
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
    Name = "${var.project_name}-lambda-role-${random_id.suffix.hex}"
  })
}

# IAM policy for Lambda functions to access SQS and CloudWatch
resource "aws_iam_role_policy" "lambda_policy" {
  name = "${var.project_name}-lambda-policy-${random_id.suffix.hex}"
  role = aws_iam_role.lambda_role.id
  
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
          aws_sqs_queue.main.arn,
          aws_sqs_queue.dlq.arn
        ]
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
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
      }
    ]
  })
}

# Lambda function code for main processor
data "archive_file" "main_processor_zip" {
  type        = "zip"
  output_path = "${path.module}/main_processor.zip"
  
  source {
    content = templatefile("${path.module}/lambda_functions/main_processor.py", {
      failure_rate = var.failure_simulation_rate
    })
    filename = "main_processor.py"
  }
}

# Main order processing Lambda function
resource "aws_lambda_function" "main_processor" {
  filename         = data.archive_file.main_processor_zip.output_path
  function_name    = "${var.project_name}-processor-${random_id.suffix.hex}"
  role            = aws_iam_role.lambda_role.arn
  handler         = "main_processor.lambda_handler"
  runtime         = "python3.9"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.main_processor_zip.output_base64sha256
  
  environment {
    variables = {
      QUEUE_URL      = aws_sqs_queue.main.url
      DLQ_URL        = aws_sqs_queue.dlq.url
      FAILURE_RATE   = var.failure_simulation_rate
    }
  }
  
  tags = merge(local.common_tags, {
    Name = "${var.project_name}-processor-${random_id.suffix.hex}"
    Type = "MainProcessor"
  })
  
  depends_on = [
    aws_iam_role_policy.lambda_policy,
    aws_cloudwatch_log_group.main_processor_logs
  ]
}

# Lambda function code for DLQ monitor
data "archive_file" "dlq_monitor_zip" {
  type        = "zip"
  output_path = "${path.module}/dlq_monitor.zip"
  
  source {
    content = templatefile("${path.module}/lambda_functions/dlq_monitor.py", {
      main_queue_url        = aws_sqs_queue.main.url
      max_retry_attempts    = var.max_retry_attempts
      high_value_threshold  = var.high_value_order_threshold
    })
    filename = "dlq_monitor.py"
  }
}

# DLQ monitoring Lambda function
resource "aws_lambda_function" "dlq_monitor" {
  filename         = data.archive_file.dlq_monitor_zip.output_path
  function_name    = "${var.project_name}-dlq-monitor-${random_id.suffix.hex}"
  role            = aws_iam_role.lambda_role.arn
  handler         = "dlq_monitor.lambda_handler"
  runtime         = "python3.9"
  timeout         = var.dlq_monitor_timeout
  memory_size     = var.dlq_monitor_memory_size
  source_code_hash = data.archive_file.dlq_monitor_zip.output_base64sha256
  
  environment {
    variables = {
      MAIN_QUEUE_URL       = aws_sqs_queue.main.url
      DLQ_URL              = aws_sqs_queue.dlq.url
      MAX_RETRY_ATTEMPTS   = var.max_retry_attempts
      HIGH_VALUE_THRESHOLD = var.high_value_order_threshold
    }
  }
  
  tags = merge(local.common_tags, {
    Name = "${var.project_name}-dlq-monitor-${random_id.suffix.hex}"
    Type = "DLQMonitor"
  })
  
  depends_on = [
    aws_iam_role_policy.lambda_policy,
    aws_cloudwatch_log_group.dlq_monitor_logs
  ]
}

# CloudWatch Log Groups for Lambda functions
resource "aws_cloudwatch_log_group" "main_processor_logs" {
  name              = "/aws/lambda/${var.project_name}-processor-${random_id.suffix.hex}"
  retention_in_days = 14
  
  tags = merge(local.common_tags, {
    Name = "${var.project_name}-processor-logs"
  })
}

resource "aws_cloudwatch_log_group" "dlq_monitor_logs" {
  name              = "/aws/lambda/${var.project_name}-dlq-monitor-${random_id.suffix.hex}"
  retention_in_days = 14
  
  tags = merge(local.common_tags, {
    Name = "${var.project_name}-dlq-monitor-logs"
  })
}

# Event source mapping for main queue
resource "aws_lambda_event_source_mapping" "main_queue_mapping" {
  event_source_arn                   = aws_sqs_queue.main.arn
  function_name                      = aws_lambda_function.main_processor.arn
  batch_size                         = var.main_queue_batch_size
  maximum_batching_window_in_seconds = var.main_queue_batching_window
  
  depends_on = [aws_iam_role_policy.lambda_policy]
}

# Event source mapping for DLQ
resource "aws_lambda_event_source_mapping" "dlq_mapping" {
  event_source_arn                   = aws_sqs_queue.dlq.arn
  function_name                      = aws_lambda_function.dlq_monitor.arn
  batch_size                         = var.dlq_batch_size
  maximum_batching_window_in_seconds = var.dlq_batching_window
  
  depends_on = [aws_iam_role_policy.lambda_policy]
}

# CloudWatch Alarms (conditional creation)
resource "aws_cloudwatch_metric_alarm" "dlq_messages" {
  count = var.enable_cloudwatch_alarms ? 1 : 0
  
  alarm_name          = "${var.project_name}-dlq-messages-${random_id.suffix.hex}"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "ApproximateNumberOfVisibleMessages"
  namespace           = "AWS/SQS"
  period              = "300"
  statistic           = "Sum"
  threshold           = var.dlq_alarm_threshold
  alarm_description   = "Alert when messages appear in dead letter queue"
  
  dimensions = {
    QueueName = aws_sqs_queue.dlq.name
  }
  
  tags = merge(local.common_tags, {
    Name = "${var.project_name}-dlq-alarm"
  })
}

resource "aws_cloudwatch_metric_alarm" "error_rate" {
  count = var.enable_cloudwatch_alarms ? 1 : 0
  
  alarm_name          = "${var.project_name}-error-rate-${random_id.suffix.hex}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "FailedMessages"
  namespace           = "DLQ/Processing"
  period              = "300"
  statistic           = "Sum"
  threshold           = var.error_rate_alarm_threshold
  alarm_description   = "Alert on high error rate in DLQ processing"
  
  tags = merge(local.common_tags, {
    Name = "${var.project_name}-error-rate-alarm"
  })
}