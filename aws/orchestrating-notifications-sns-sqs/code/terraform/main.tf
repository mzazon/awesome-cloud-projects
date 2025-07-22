# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Get current AWS account ID and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  # Use provided suffix or generate random one
  suffix = var.random_suffix != "" ? var.random_suffix : random_string.suffix.result
  
  # Common resource naming
  resource_prefix = "${var.project_name}-${local.suffix}"
  
  # Queue names
  email_queue_name    = "email-notifications-${local.suffix}"
  sms_queue_name      = "sms-notifications-${local.suffix}"
  webhook_queue_name  = "webhook-notifications-${local.suffix}"
  dlq_name           = "notification-dlq-${local.suffix}"
  
  # Lambda function names
  email_lambda_name    = "EmailNotificationHandler-${local.suffix}"
  webhook_lambda_name  = "WebhookNotificationHandler-${local.suffix}"
  dlq_lambda_name      = "DLQProcessor-${local.suffix}"
}

# ==========================================
# SNS Topic for message distribution
# ==========================================
resource "aws_sns_topic" "notifications" {
  name = "${var.sns_topic_name}-${local.suffix}"
  
  # Enable server-side encryption
  kms_master_key_id = "alias/aws/sns"
  
  tags = merge(
    {
      Name = "${var.sns_topic_name}-${local.suffix}"
      Type = "SNS Topic"
    },
    var.additional_tags
  )
}

# SNS Topic Policy for cross-service access
resource "aws_sns_topic_policy" "notifications" {
  arn = aws_sns_topic.notifications.arn
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "*"
        }
        Action = "SNS:Publish"
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

# ==========================================
# SQS Queues for different notification types
# ==========================================

# Dead Letter Queue
resource "aws_sqs_queue" "dlq" {
  name                       = local.dlq_name
  visibility_timeout_seconds = var.sqs_visibility_timeout
  message_retention_seconds  = var.sqs_message_retention_period
  
  # Enable server-side encryption
  sqs_managed_sse_enabled = true
  
  tags = merge(
    {
      Name = local.dlq_name
      Type = "Dead Letter Queue"
    },
    var.additional_tags
  )
}

# Email Processing Queue
resource "aws_sqs_queue" "email_queue" {
  name                       = local.email_queue_name
  visibility_timeout_seconds = var.sqs_visibility_timeout
  message_retention_seconds  = var.sqs_message_retention_period
  
  # Enable server-side encryption
  sqs_managed_sse_enabled = true
  
  # Dead letter queue configuration
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = var.sqs_max_receive_count
  })
  
  tags = merge(
    {
      Name = local.email_queue_name
      Type = "Email Processing Queue"
    },
    var.additional_tags
  )
}

# SMS Processing Queue
resource "aws_sqs_queue" "sms_queue" {
  name                       = local.sms_queue_name
  visibility_timeout_seconds = var.sqs_visibility_timeout
  message_retention_seconds  = var.sqs_message_retention_period
  
  # Enable server-side encryption
  sqs_managed_sse_enabled = true
  
  # Dead letter queue configuration
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = var.sqs_max_receive_count
  })
  
  tags = merge(
    {
      Name = local.sms_queue_name
      Type = "SMS Processing Queue"
    },
    var.additional_tags
  )
}

# Webhook Processing Queue
resource "aws_sqs_queue" "webhook_queue" {
  name                       = local.webhook_queue_name
  visibility_timeout_seconds = var.sqs_visibility_timeout
  message_retention_seconds  = var.sqs_message_retention_period
  
  # Enable server-side encryption
  sqs_managed_sse_enabled = true
  
  # Dead letter queue configuration
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = var.sqs_max_receive_count
  })
  
  tags = merge(
    {
      Name = local.webhook_queue_name
      Type = "Webhook Processing Queue"
    },
    var.additional_tags
  )
}

# ==========================================
# SQS Queue Policies for SNS access
# ==========================================

# Email Queue Policy
resource "aws_sqs_queue_policy" "email_queue_policy" {
  queue_url = aws_sqs_queue.email_queue.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "sns.amazonaws.com"
        }
        Action = "sqs:SendMessage"
        Resource = aws_sqs_queue.email_queue.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
          ArnEquals = {
            "aws:SourceArn" = aws_sns_topic.notifications.arn
          }
        }
      }
    ]
  })
}

# SMS Queue Policy
resource "aws_sqs_queue_policy" "sms_queue_policy" {
  queue_url = aws_sqs_queue.sms_queue.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "sns.amazonaws.com"
        }
        Action = "sqs:SendMessage"
        Resource = aws_sqs_queue.sms_queue.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
          ArnEquals = {
            "aws:SourceArn" = aws_sns_topic.notifications.arn
          }
        }
      }
    ]
  })
}

# Webhook Queue Policy
resource "aws_sqs_queue_policy" "webhook_queue_policy" {
  queue_url = aws_sqs_queue.webhook_queue.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "sns.amazonaws.com"
        }
        Action = "sqs:SendMessage"
        Resource = aws_sqs_queue.webhook_queue.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
          ArnEquals = {
            "aws:SourceArn" = aws_sns_topic.notifications.arn
          }
        }
      }
    ]
  })
}

# ==========================================
# SNS Topic Subscriptions with message filtering
# ==========================================

# Email Queue Subscription
resource "aws_sns_topic_subscription" "email_subscription" {
  topic_arn              = aws_sns_topic.notifications.arn
  protocol               = "sqs"
  endpoint              = aws_sqs_queue.email_queue.arn
  raw_message_delivery  = true
  
  filter_policy = jsonencode({
    notification_type = ["email", "all"]
  })
  
  depends_on = [aws_sqs_queue_policy.email_queue_policy]
}

# SMS Queue Subscription
resource "aws_sns_topic_subscription" "sms_subscription" {
  topic_arn              = aws_sns_topic.notifications.arn
  protocol               = "sqs"
  endpoint              = aws_sqs_queue.sms_queue.arn
  raw_message_delivery  = true
  
  filter_policy = jsonencode({
    notification_type = ["sms", "all"]
  })
  
  depends_on = [aws_sqs_queue_policy.sms_queue_policy]
}

# Webhook Queue Subscription
resource "aws_sns_topic_subscription" "webhook_subscription" {
  topic_arn              = aws_sns_topic.notifications.arn
  protocol               = "sqs"
  endpoint              = aws_sqs_queue.webhook_queue.arn
  raw_message_delivery  = true
  
  filter_policy = jsonencode({
    notification_type = ["webhook", "all"]
  })
  
  depends_on = [aws_sqs_queue_policy.webhook_queue_policy]
}

# ==========================================
# IAM Role for Lambda Functions
# ==========================================

# Lambda execution role
resource "aws_iam_role" "lambda_role" {
  name = "NotificationLambdaRole-${local.suffix}"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
  
  tags = merge(
    {
      Name = "NotificationLambdaRole-${local.suffix}"
      Type = "IAM Role"
    },
    var.additional_tags
  )
}

# Attach basic Lambda execution policy
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Custom policy for SQS access
resource "aws_iam_role_policy" "lambda_sqs_policy" {
  name = "SQSAccessPolicy-${local.suffix}"
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
          aws_sqs_queue.email_queue.arn,
          aws_sqs_queue.sms_queue.arn,
          aws_sqs_queue.webhook_queue.arn,
          aws_sqs_queue.dlq.arn
        ]
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

# ==========================================
# Lambda Function Code Archives
# ==========================================

# Email handler function code
data "archive_file" "email_handler" {
  type        = "zip"
  output_path = "${path.module}/email_handler.zip"
  
  source {
    content = templatefile("${path.module}/lambda_functions/email_handler.py.tpl", {
      test_email = var.test_email
    })
    filename = "email_handler.py"
  }
}

# Webhook handler function code
data "archive_file" "webhook_handler" {
  type        = "zip"
  output_path = "${path.module}/webhook_handler.zip"
  
  source {
    content = templatefile("${path.module}/lambda_functions/webhook_handler.py.tpl", {
      webhook_url = var.webhook_url
    })
    filename = "webhook_handler.py"
  }
}

# DLQ processor function code
data "archive_file" "dlq_processor" {
  type        = "zip"
  output_path = "${path.module}/dlq_processor.zip"
  
  source {
    content = file("${path.module}/lambda_functions/dlq_processor.py")
    filename = "dlq_processor.py"
  }
}

# ==========================================
# Lambda Functions
# ==========================================

# Email notification handler
resource "aws_lambda_function" "email_handler" {
  filename         = data.archive_file.email_handler.output_path
  function_name    = local.email_lambda_name
  role            = aws_iam_role.lambda_role.arn
  handler         = "email_handler.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  
  source_code_hash = data.archive_file.email_handler.output_base64sha256
  
  environment {
    variables = {
      LOG_LEVEL        = "INFO"
      PROJECT_NAME     = var.project_name
      ENVIRONMENT      = var.environment
      DEFAULT_EMAIL    = var.test_email
    }
  }
  
  tags = merge(
    {
      Name = local.email_lambda_name
      Type = "Lambda Function"
      Purpose = "Email Notification Handler"
    },
    var.additional_tags
  )
}

# Webhook notification handler
resource "aws_lambda_function" "webhook_handler" {
  filename         = data.archive_file.webhook_handler.output_path
  function_name    = local.webhook_lambda_name
  role            = aws_iam_role.lambda_role.arn
  handler         = "webhook_handler.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  
  source_code_hash = data.archive_file.webhook_handler.output_base64sha256
  
  environment {
    variables = {
      LOG_LEVEL        = "INFO"
      PROJECT_NAME     = var.project_name
      ENVIRONMENT      = var.environment
      DEFAULT_WEBHOOK  = var.webhook_url
    }
  }
  
  tags = merge(
    {
      Name = local.webhook_lambda_name
      Type = "Lambda Function"
      Purpose = "Webhook Notification Handler"
    },
    var.additional_tags
  )
}

# Dead Letter Queue processor
resource "aws_lambda_function" "dlq_processor" {
  filename         = data.archive_file.dlq_processor.output_path
  function_name    = local.dlq_lambda_name
  role            = aws_iam_role.lambda_role.arn
  handler         = "dlq_processor.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  
  source_code_hash = data.archive_file.dlq_processor.output_base64sha256
  
  environment {
    variables = {
      LOG_LEVEL     = "INFO"
      PROJECT_NAME  = var.project_name
      ENVIRONMENT   = var.environment
    }
  }
  
  tags = merge(
    {
      Name = local.dlq_lambda_name
      Type = "Lambda Function"
      Purpose = "Dead Letter Queue Processor"
    },
    var.additional_tags
  )
}

# ==========================================
# Lambda Event Source Mappings
# ==========================================

# Email queue event source mapping
resource "aws_lambda_event_source_mapping" "email_queue_mapping" {
  event_source_arn                   = aws_sqs_queue.email_queue.arn
  function_name                      = aws_lambda_function.email_handler.arn
  batch_size                         = var.event_source_batch_size
  maximum_batching_window_in_seconds = var.event_source_max_batching_window
  
  depends_on = [aws_iam_role_policy.lambda_sqs_policy]
}

# Webhook queue event source mapping
resource "aws_lambda_event_source_mapping" "webhook_queue_mapping" {
  event_source_arn                   = aws_sqs_queue.webhook_queue.arn
  function_name                      = aws_lambda_function.webhook_handler.arn
  batch_size                         = var.event_source_batch_size
  maximum_batching_window_in_seconds = var.event_source_max_batching_window
  
  depends_on = [aws_iam_role_policy.lambda_sqs_policy]
}

# DLQ event source mapping
resource "aws_lambda_event_source_mapping" "dlq_mapping" {
  event_source_arn                   = aws_sqs_queue.dlq.arn
  function_name                      = aws_lambda_function.dlq_processor.arn
  batch_size                         = var.event_source_batch_size
  maximum_batching_window_in_seconds = var.event_source_max_batching_window
  
  depends_on = [aws_iam_role_policy.lambda_sqs_policy]
}

# ==========================================
# CloudWatch Log Groups for Lambda Functions
# ==========================================

# Email handler log group
resource "aws_cloudwatch_log_group" "email_handler_logs" {
  name              = "/aws/lambda/${local.email_lambda_name}"
  retention_in_days = 30
  
  tags = merge(
    {
      Name = "/aws/lambda/${local.email_lambda_name}"
      Type = "CloudWatch Log Group"
    },
    var.additional_tags
  )
}

# Webhook handler log group
resource "aws_cloudwatch_log_group" "webhook_handler_logs" {
  name              = "/aws/lambda/${local.webhook_lambda_name}"
  retention_in_days = 30
  
  tags = merge(
    {
      Name = "/aws/lambda/${local.webhook_lambda_name}"
      Type = "CloudWatch Log Group"
    },
    var.additional_tags
  )
}

# DLQ processor log group
resource "aws_cloudwatch_log_group" "dlq_processor_logs" {
  name              = "/aws/lambda/${local.dlq_lambda_name}"
  retention_in_days = 30
  
  tags = merge(
    {
      Name = "/aws/lambda/${local.dlq_lambda_name}"
      Type = "CloudWatch Log Group"
    },
    var.additional_tags
  )
}