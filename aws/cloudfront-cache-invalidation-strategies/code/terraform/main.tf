# CloudFront Cache Invalidation Strategies - Main Terraform Configuration
# This file creates the complete infrastructure for intelligent CloudFront cache invalidation

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

# Data source for current AWS caller identity
data "aws_caller_identity" "current" {}

# Data source for AWS region
data "aws_region" "current" {}

# Data source for AWS partition
data "aws_partition" "current" {}

# Local values for resource naming and common configurations
locals {
  name_prefix = "${var.project_name}-${random_string.suffix.result}"
  
  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      Recipe      = "cloudfront-cache-invalidation-strategies"
      ManagedBy   = "terraform"
    },
    var.additional_tags
  )
  
  # Calculate TTL for DynamoDB records
  dynamodb_ttl_seconds = var.dynamodb_ttl_days * 24 * 60 * 60
}

# ==========================================
# S3 BUCKET FOR CLOUDFRONT ORIGIN
# ==========================================

# S3 bucket for content storage
resource "aws_s3_bucket" "content" {
  bucket = "${local.name_prefix}-content"
  
  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-content"
    Purpose     = "CloudFront origin content storage"
    Component   = "storage"
  })
}

# S3 bucket versioning
resource "aws_s3_bucket_versioning" "content" {
  bucket = aws_s3_bucket.content.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "content" {
  bucket = aws_s3_bucket.content.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# S3 bucket public access block
resource "aws_s3_bucket_public_access_block" "content" {
  bucket = aws_s3_bucket.content.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket policy for CloudFront Origin Access Control
resource "aws_s3_bucket_policy" "content" {
  bucket = aws_s3_bucket.content.id
  
  depends_on = [
    aws_s3_bucket_public_access_block.content,
    aws_cloudfront_distribution.main
  ]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudFrontServicePrincipal"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.content.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.main.arn
          }
        }
      }
    ]
  })
}

# S3 bucket notification configuration for EventBridge
resource "aws_s3_bucket_notification" "content" {
  count  = var.enable_event_notifications ? 1 : 0
  bucket = aws_s3_bucket.content.id

  eventbridge = true
  
  depends_on = [aws_s3_bucket_policy.content]
}

# Sample content objects (if enabled)
resource "aws_s3_object" "sample_content" {
  for_each = var.create_sample_content ? {
    "index.html" = {
      content      = "<html><body><h1>Home Page</h1><p>Version 1.0</p></body></html>"
      content_type = "text/html"
    }
    "css/style.css" = {
      content      = "body { background: white; font-family: Arial, sans-serif; }"
      content_type = "text/css"
    }
    "js/app.js" = {
      content      = "console.log('App v1.0 - Intelligent cache invalidation demo');"
      content_type = "application/javascript"
    }
    "api/status.json" = {
      content      = jsonencode({ status = "active", version = "1.0" })
      content_type = "application/json"
    }
  } : {}

  bucket       = aws_s3_bucket.content.id
  key          = each.key
  content      = each.value.content
  content_type = each.value.content_type
  etag         = md5(each.value.content)

  tags = merge(local.common_tags, {
    Name      = each.key
    Component = "sample-content"
  })
}

# ==========================================
# CLOUDFRONT DISTRIBUTION
# ==========================================

# CloudFront Origin Access Control
resource "aws_cloudfront_origin_access_control" "main" {
  name                              = "${local.name_prefix}-oac"
  description                       = "Origin Access Control for ${local.name_prefix}"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# CloudFront Distribution
resource "aws_cloudfront_distribution" "main" {
  origin {
    domain_name              = aws_s3_bucket.content.bucket_regional_domain_name
    origin_id                = "S3-${aws_s3_bucket.content.id}"
    origin_access_control_id = aws_cloudfront_origin_access_control.main.id
    
    connection_attempts      = 3
    connection_timeout       = 10
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  comment             = "CloudFront distribution for intelligent cache invalidation - ${var.project_name}"
  price_class         = var.cloudfront_price_class
  http_version        = var.cloudfront_http_version

  # Default cache behavior
  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-${aws_s3_bucket.content.id}"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600   # 1 hour
    max_ttl                = 86400  # 24 hours
    compress               = true

    # Use AWS managed caching policy - Managed-CachingOptimized
    cache_policy_id = "658327ea-f89d-4fab-a63d-7e88639e58f6"
  }

  # Cache behavior for API content (shorter TTL)
  ordered_cache_behavior {
    path_pattern     = "/api/*"
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-${aws_s3_bucket.content.id}"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "https-only"
    min_ttl                = 0
    default_ttl            = 300    # 5 minutes
    max_ttl                = 3600   # 1 hour
    compress               = true

    # Use AWS managed caching policy - Managed-CachingOptimized
    cache_policy_id = "658327ea-f89d-4fab-a63d-7e88639e58f6"
  }

  # Cache behavior for static assets (longer TTL)
  ordered_cache_behavior {
    path_pattern     = "/css/*"
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-${aws_s3_bucket.content.id}"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "https-only"
    min_ttl                = 0
    default_ttl            = 86400   # 24 hours
    max_ttl                = 31536000 # 1 year
    compress               = true

    # Use AWS managed caching policy - Managed-CachingOptimizedForUncompressedObjects
    cache_policy_id = "b2884449-e4de-46a7-ac36-70bc7f1ddd6d"
  }

  # Cache behavior for JavaScript files (longer TTL)
  ordered_cache_behavior {
    path_pattern     = "/js/*"
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-${aws_s3_bucket.content.id}"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "https-only"
    min_ttl                = 0
    default_ttl            = 86400   # 24 hours
    max_ttl                = 31536000 # 1 year
    compress               = true

    # Use AWS managed caching policy - Managed-CachingOptimizedForUncompressedObjects
    cache_policy_id = "b2884449-e4de-46a7-ac36-70bc7f1ddd6d"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
    minimum_protocol_version       = var.cloudfront_minimum_protocol_version
  }

  tags = merge(local.common_tags, {
    Name      = "${local.name_prefix}-distribution"
    Component = "cdn"
  })
}

# ==========================================
# DYNAMODB TABLE FOR INVALIDATION LOGGING
# ==========================================

# DynamoDB table for invalidation audit logs
resource "aws_dynamodb_table" "invalidation_log" {
  name           = "${local.name_prefix}-invalidation-log"
  billing_mode   = var.dynamodb_billing_mode
  hash_key       = "InvalidationId"
  range_key      = "Timestamp"
  stream_enabled = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  attribute {
    name = "InvalidationId"
    type = "S"
  }

  attribute {
    name = "Timestamp"
    type = "S"
  }

  # TTL configuration
  ttl {
    attribute_name = "TTL"
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
    Name      = "${local.name_prefix}-invalidation-log"
    Component = "database"
  })
}

# ==========================================
# SQS QUEUES FOR BATCH PROCESSING
# ==========================================

# Dead letter queue for failed invalidations
resource "aws_sqs_queue" "dead_letter_queue" {
  name                      = "${local.name_prefix}-dlq"
  message_retention_seconds = var.sqs_message_retention_period
  
  tags = merge(local.common_tags, {
    Name      = "${local.name_prefix}-dlq"
    Component = "messaging"
    Purpose   = "dead-letter-queue"
  })
}

# Main batch processing queue
resource "aws_sqs_queue" "batch_queue" {
  name                      = "${local.name_prefix}-batch-queue"
  visibility_timeout_seconds = var.sqs_visibility_timeout
  message_retention_seconds = var.sqs_message_retention_period
  receive_wait_time_seconds = 20
  
  # Dead letter queue configuration
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dead_letter_queue.arn
    maxReceiveCount     = 3
  })

  tags = merge(local.common_tags, {
    Name      = "${local.name_prefix}-batch-queue"
    Component = "messaging"
    Purpose   = "batch-processing"
  })
}

# ==========================================
# EVENTBRIDGE CUSTOM BUS AND RULES
# ==========================================

# Custom EventBridge bus for invalidation events
resource "aws_cloudwatch_event_bus" "invalidation_bus" {
  name = "${local.name_prefix}-invalidation-bus"

  tags = merge(local.common_tags, {
    Name      = "${local.name_prefix}-invalidation-bus"
    Component = "event-processing"
  })
}

# EventBridge rule for S3 content changes
resource "aws_cloudwatch_event_rule" "s3_events" {
  name        = "${local.name_prefix}-s3-rule"
  description = "Rule to capture S3 content changes for invalidation"
  event_bus_name = aws_cloudwatch_event_bus.invalidation_bus.name

  event_pattern = jsonencode({
    source      = ["aws.s3"]
    detail-type = ["Object Created", "Object Deleted"]
    detail = {
      bucket = {
        name = [aws_s3_bucket.content.bucket]
      }
    }
  })

  tags = merge(local.common_tags, {
    Name      = "${local.name_prefix}-s3-rule"
    Component = "event-processing"
    Purpose   = "s3-events"
  })
}

# EventBridge rule for deployment events
resource "aws_cloudwatch_event_rule" "deployment_events" {
  name        = "${local.name_prefix}-deployment-rule"
  description = "Rule to capture deployment events for invalidation"
  event_bus_name = aws_cloudwatch_event_bus.invalidation_bus.name

  event_pattern = jsonencode({
    source      = ["aws.codedeploy", "custom.app"]
    detail-type = ["Deployment State-change Notification", "Application Deployment"]
  })

  tags = merge(local.common_tags, {
    Name      = "${local.name_prefix}-deployment-rule"
    Component = "event-processing"
    Purpose   = "deployment-events"
  })
}

# ==========================================
# LAMBDA FUNCTION FOR INVALIDATION PROCESSING
# ==========================================

# CloudWatch Log Group for Lambda function
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${local.name_prefix}-invalidation-processor"
  retention_in_days = var.log_retention_in_days

  tags = merge(local.common_tags, {
    Name      = "${local.name_prefix}-lambda-logs"
    Component = "logging"
  })
}

# IAM role for Lambda function
resource "aws_iam_role" "lambda_role" {
  name = "${local.name_prefix}-lambda-role"

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
    Name      = "${local.name_prefix}-lambda-role"
    Component = "security"
  })
}

# IAM policy for Lambda function
resource "aws_iam_role_policy" "lambda_policy" {
  name = "${local.name_prefix}-lambda-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "cloudfront:CreateInvalidation",
          "cloudfront:GetInvalidation",
          "cloudfront:ListInvalidations"
        ]
        Resource = "*"
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
        Resource = aws_dynamodb_table.invalidation_log.arn
      },
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage",
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = [
          aws_sqs_queue.batch_queue.arn,
          aws_sqs_queue.dead_letter_queue.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.lambda_logs.arn}:*"
      }
    ]
  })
}

# Attach basic execution role policy
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Attach X-Ray tracing policy (if enabled)
resource "aws_iam_role_policy_attachment" "lambda_xray_execution" {
  count      = var.enable_xray_tracing ? 1 : 0
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

# Create Lambda function deployment package
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda_function.zip"
  
  source {
    content = templatefile("${path.module}/lambda_function.js", {
      DDB_TABLE_NAME  = aws_dynamodb_table.invalidation_log.name
      QUEUE_URL       = aws_sqs_queue.batch_queue.url
      DISTRIBUTION_ID = aws_cloudfront_distribution.main.id
      DLQ_URL         = aws_sqs_queue.dead_letter_queue.url
    })
    filename = "index.js"
  }
  
  source {
    content = jsonencode({
      name = "cloudfront-invalidation"
      version = "1.0.0"
      description = "Intelligent CloudFront cache invalidation"
      main = "index.js"
      dependencies = {
        "aws-sdk" = "^2.1000.0"
      }
    })
    filename = "package.json"
  }
}

# Lambda function
resource "aws_lambda_function" "invalidation_processor" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "${local.name_prefix}-invalidation-processor"
  role            = aws_iam_role.lambda_role.arn
  handler         = "index.handler"
  runtime         = "nodejs18.x"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      DDB_TABLE_NAME  = aws_dynamodb_table.invalidation_log.name
      QUEUE_URL       = aws_sqs_queue.batch_queue.url
      DISTRIBUTION_ID = aws_cloudfront_distribution.main.id
      DLQ_URL         = aws_sqs_queue.dead_letter_queue.url
    }
  }

  dynamic "tracing_config" {
    for_each = var.enable_xray_tracing ? [1] : []
    content {
      mode = "Active"
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.lambda_logs,
    aws_iam_role_policy.lambda_policy,
    aws_iam_role_policy_attachment.lambda_basic_execution
  ]

  tags = merge(local.common_tags, {
    Name      = "${local.name_prefix}-invalidation-processor"
    Component = "compute"
  })
}

# Lambda permission for EventBridge
resource "aws_lambda_permission" "eventbridge_invoke" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.invalidation_processor.function_name
  principal     = "events.amazonaws.com"
  source_arn    = "arn:${data.aws_partition.current.partition}:events:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:rule/${aws_cloudwatch_event_bus.invalidation_bus.name}/*"
}

# SQS event source mapping for Lambda
resource "aws_lambda_event_source_mapping" "sqs_trigger" {
  event_source_arn = aws_sqs_queue.batch_queue.arn
  function_name    = aws_lambda_function.invalidation_processor.arn
  batch_size       = var.sqs_batch_size
  maximum_batching_window_in_seconds = var.sqs_maximum_batching_window
}

# ==========================================
# EVENTBRIDGE TARGETS
# ==========================================

# EventBridge target for S3 events
resource "aws_cloudwatch_event_target" "s3_lambda" {
  rule      = aws_cloudwatch_event_rule.s3_events.name
  target_id = "S3EventTarget"
  arn       = aws_lambda_function.invalidation_processor.arn
  event_bus_name = aws_cloudwatch_event_bus.invalidation_bus.name
}

# EventBridge target for deployment events
resource "aws_cloudwatch_event_target" "deployment_lambda" {
  rule      = aws_cloudwatch_event_rule.deployment_events.name
  target_id = "DeploymentEventTarget"
  arn       = aws_lambda_function.invalidation_processor.arn
  event_bus_name = aws_cloudwatch_event_bus.invalidation_bus.name
}

# ==========================================
# CLOUDWATCH MONITORING
# ==========================================

# SNS topic for notifications (if email provided)
resource "aws_sns_topic" "notifications" {
  count = var.sns_notification_email != "" ? 1 : 0
  name  = "${local.name_prefix}-notifications"

  tags = merge(local.common_tags, {
    Name      = "${local.name_prefix}-notifications"
    Component = "notifications"
  })
}

# SNS topic subscription (if email provided)
resource "aws_sns_topic_subscription" "email_notifications" {
  count     = var.sns_notification_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.notifications[0].arn
  protocol  = "email"
  endpoint  = var.sns_notification_email
}

# CloudWatch alarms for monitoring
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  count               = var.sns_notification_email != "" ? 1 : 0
  alarm_name          = "${local.name_prefix}-lambda-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "This metric monitors lambda errors"
  alarm_actions       = [aws_sns_topic.notifications[0].arn]

  dimensions = {
    FunctionName = aws_lambda_function.invalidation_processor.function_name
  }

  tags = merge(local.common_tags, {
    Name      = "${local.name_prefix}-lambda-errors-alarm"
    Component = "monitoring"
  })
}

# CloudWatch Dashboard for monitoring
resource "aws_cloudwatch_dashboard" "monitoring" {
  count          = var.enable_monitoring_dashboard ? 1 : 0
  dashboard_name = "${local.name_prefix}-monitoring"

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
            ["AWS/CloudFront", "Requests", "DistributionId", aws_cloudfront_distribution.main.id],
            [".", "CacheHitRate", ".", "."]
          ]
          period = 300
          stat   = "Average"
          region = "us-east-1"
          title  = "CloudFront Performance"
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
            ["AWS/Lambda", "Duration", "FunctionName", aws_lambda_function.invalidation_processor.function_name],
            [".", "Invocations", ".", "."],
            [".", "Errors", ".", "."]
          ]
          period = 300
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "Invalidation Function Performance"
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
            ["AWS/Events", "MatchedEvents", "EventBusName", aws_cloudwatch_event_bus.invalidation_bus.name],
            ["AWS/SQS", "NumberOfMessagesSent", "QueueName", aws_sqs_queue.batch_queue.name],
            [".", "NumberOfMessagesReceived", ".", "."]
          ]
          period = 300
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "Event Processing Volume"
        }
      }
    ]
  })
}

# Create the Lambda function JavaScript code as a template
resource "local_file" "lambda_function_js" {
  filename = "${path.module}/lambda_function.js"
  content = templatefile("${path.module}/lambda_function.js.tpl", {
    DDB_TABLE_NAME  = aws_dynamodb_table.invalidation_log.name
    QUEUE_URL       = aws_sqs_queue.batch_queue.url
    DISTRIBUTION_ID = aws_cloudfront_distribution.main.id
    DLQ_URL         = aws_sqs_queue.dead_letter_queue.url
  })
  
  depends_on = [
    aws_dynamodb_table.invalidation_log,
    aws_sqs_queue.batch_queue,
    aws_cloudfront_distribution.main,
    aws_sqs_queue.dead_letter_queue
  ]
}