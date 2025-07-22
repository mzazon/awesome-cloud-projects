# Main Terraform configuration for Amazon Chime SDK video conferencing solution
# This file creates all the necessary AWS resources for a complete video conferencing platform

# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = var.random_suffix_length
  special = false
  upper   = false
}

# Local values for consistent resource naming and configuration
locals {
  name_prefix           = "${var.project_name}-${random_string.suffix.result}"
  common_tags = merge(var.additional_tags, {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
    Purpose     = "VideoConferencing"
  })
}

# Data sources for current AWS account and region information
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# S3 bucket for storing meeting recordings and artifacts
resource "aws_s3_bucket" "recordings" {
  bucket = "${local.name_prefix}-recordings"

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-recordings"
    Description = "S3 bucket for video conference recordings and artifacts"
  })
}

# S3 bucket versioning configuration
resource "aws_s3_bucket_versioning" "recordings" {
  bucket = aws_s3_bucket.recordings.id
  versioning_configuration {
    status = var.s3_bucket_versioning ? "Enabled" : "Disabled"
  }
}

# S3 bucket server-side encryption configuration
resource "aws_s3_bucket_server_side_encryption_configuration" "recordings" {
  bucket = aws_s3_bucket.recordings.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = var.s3_bucket_encryption
    }
    bucket_key_enabled = true
  }
}

# S3 bucket public access block for security
resource "aws_s3_bucket_public_access_block" "recordings" {
  bucket = aws_s3_bucket.recordings.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# DynamoDB table for storing meeting metadata
resource "aws_dynamodb_table" "meetings" {
  name           = "${local.name_prefix}-meetings"
  billing_mode   = "PROVISIONED"
  read_capacity  = var.dynamodb_read_capacity
  write_capacity = var.dynamodb_write_capacity
  hash_key       = "MeetingId"
  range_key      = "CreatedAt"

  attribute {
    name = "MeetingId"
    type = "S"
  }

  attribute {
    name = "CreatedAt"
    type = "S"
  }

  # Global Secondary Index for querying by status
  global_secondary_index {
    name            = "StatusIndex"
    hash_key        = "Status"
    range_key       = "CreatedAt"
    read_capacity   = var.dynamodb_read_capacity
    write_capacity  = var.dynamodb_write_capacity
    projection_type = "ALL"
  }

  attribute {
    name = "Status"
    type = "S"
  }

  # Point-in-time recovery for data protection
  point_in_time_recovery {
    enabled = true
  }

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-meetings"
    Description = "DynamoDB table for storing meeting metadata and status"
  })
}

# SNS topic for Chime SDK event notifications
resource "aws_sns_topic" "events" {
  name              = "${local.name_prefix}-events"
  kms_master_key_id = var.enable_sns_encryption ? "alias/aws/sns" : null

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-events"
    Description = "SNS topic for Chime SDK meeting events and notifications"
  })
}

# SQS queue for processing Chime SDK events
resource "aws_sqs_queue" "event_processing" {
  name                      = "${local.name_prefix}-event-processing"
  delay_seconds             = 0
  max_message_size          = 262144
  message_retention_seconds = 1209600
  receive_wait_time_seconds = 10

  # Dead letter queue configuration
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.event_processing_dlq.arn
    maxReceiveCount     = 3
  })

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-event-processing"
    Description = "SQS queue for processing Chime SDK events"
  })
}

# Dead letter queue for failed event processing
resource "aws_sqs_queue" "event_processing_dlq" {
  name = "${local.name_prefix}-event-processing-dlq"

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-event-processing-dlq"
    Description = "Dead letter queue for failed Chime SDK event processing"
  })
}

# SNS topic subscription to SQS queue
resource "aws_sns_topic_subscription" "events_to_sqs" {
  topic_arn = aws_sns_topic.events.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.event_processing.arn
}

# IAM role for Lambda functions
resource "aws_iam_role" "lambda_execution_role" {
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
    Name        = "${local.name_prefix}-lambda-role"
    Description = "IAM role for Chime SDK Lambda functions"
  })
}

# IAM policy for Lambda functions with Chime SDK permissions
resource "aws_iam_policy" "lambda_chime_policy" {
  name        = "${local.name_prefix}-lambda-chime-policy"
  description = "IAM policy for Lambda functions to access Chime SDK and related services"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "chime:CreateMeeting",
          "chime:DeleteMeeting",
          "chime:GetMeeting",
          "chime:ListMeetings",
          "chime:CreateAttendee",
          "chime:DeleteAttendee",
          "chime:GetAttendee",
          "chime:ListAttendees",
          "chime:BatchCreateAttendee",
          "chime:BatchDeleteAttendee",
          "chime:StartMeetingTranscription",
          "chime:StopMeetingTranscription"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = [
          aws_dynamodb_table.meetings.arn,
          "${aws_dynamodb_table.meetings.arn}/index/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject"
        ]
        Resource = "${aws_s3_bucket.recordings.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.events.arn
      },
      {
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = aws_sqs_queue.event_processing.arn
      }
    ]
  })

  tags = local.common_tags
}

# Attach AWS managed policy for Lambda basic execution
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.lambda_execution_role.name
}

# Attach custom Chime SDK policy
resource "aws_iam_role_policy_attachment" "lambda_chime_policy" {
  policy_arn = aws_iam_policy.lambda_chime_policy.arn
  role       = aws_iam_role.lambda_execution_role.name
}

# CloudWatch Log Groups for Lambda functions
resource "aws_cloudwatch_log_group" "meeting_handler_logs" {
  name              = "/aws/lambda/${local.name_prefix}-meeting-handler"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-meeting-handler-logs"
    Description = "CloudWatch log group for meeting handler Lambda function"
  })
}

resource "aws_cloudwatch_log_group" "attendee_handler_logs" {
  name              = "/aws/lambda/${local.name_prefix}-attendee-handler"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-attendee-handler-logs"
    Description = "CloudWatch log group for attendee handler Lambda function"
  })
}

# Lambda function package for meeting handler
data "archive_file" "meeting_handler_zip" {
  type        = "zip"
  output_path = "${path.module}/meeting-handler.zip"
  
  source {
    content = templatefile("${path.module}/function_code/meeting-handler.js", {
      table_name    = aws_dynamodb_table.meetings.name
      sns_topic_arn = aws_sns_topic.events.arn
      aws_region    = data.aws_region.current.name
    })
    filename = "meeting-handler.js"
  }
  
  source {
    content = file("${path.module}/function_code/package.json")
    filename = "package.json"
  }
}

# Meeting management Lambda function
resource "aws_lambda_function" "meeting_handler" {
  filename         = data.archive_file.meeting_handler_zip.output_path
  function_name    = "${local.name_prefix}-meeting-handler"
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "meeting-handler.handler"
  source_code_hash = data.archive_file.meeting_handler_zip.output_base64sha256
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size

  environment {
    variables = {
      TABLE_NAME    = aws_dynamodb_table.meetings.name
      SNS_TOPIC_ARN = aws_sns_topic.events.arn
      AWS_REGION    = data.aws_region.current.name
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.meeting_handler_logs,
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy_attachment.lambda_chime_policy
  ]

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-meeting-handler"
    Description = "Lambda function for managing Chime SDK meetings"
  })
}

# Lambda function package for attendee handler
data "archive_file" "attendee_handler_zip" {
  type        = "zip"
  output_path = "${path.module}/attendee-handler.zip"
  
  source {
    content = file("${path.module}/function_code/attendee-handler.js")
    filename = "attendee-handler.js"
  }
  
  source {
    content = file("${path.module}/function_code/package.json")
    filename = "package.json"
  }
}

# Attendee management Lambda function
resource "aws_lambda_function" "attendee_handler" {
  filename         = data.archive_file.attendee_handler_zip.output_path
  function_name    = "${local.name_prefix}-attendee-handler"
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "attendee-handler.handler"
  source_code_hash = data.archive_file.attendee_handler_zip.output_base64sha256
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size

  environment {
    variables = {
      AWS_REGION = data.aws_region.current.name
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.attendee_handler_logs,
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy_attachment.lambda_chime_policy
  ]

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-attendee-handler"
    Description = "Lambda function for managing Chime SDK attendees"
  })
}

# API Gateway REST API
resource "aws_api_gateway_rest_api" "video_conferencing_api" {
  name        = "${local.name_prefix}-api"
  description = "REST API for video conferencing with Amazon Chime SDK"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-api"
    Description = "API Gateway for Chime SDK video conferencing backend"
  })
}

# API Gateway resource: /meetings
resource "aws_api_gateway_resource" "meetings" {
  rest_api_id = aws_api_gateway_rest_api.video_conferencing_api.id
  parent_id   = aws_api_gateway_rest_api.video_conferencing_api.root_resource_id
  path_part   = "meetings"
}

# API Gateway resource: /meetings/{meetingId}
resource "aws_api_gateway_resource" "meeting_id" {
  rest_api_id = aws_api_gateway_rest_api.video_conferencing_api.id
  parent_id   = aws_api_gateway_resource.meetings.id
  path_part   = "{meetingId}"
}

# API Gateway resource: /meetings/{meetingId}/attendees
resource "aws_api_gateway_resource" "attendees" {
  rest_api_id = aws_api_gateway_rest_api.video_conferencing_api.id
  parent_id   = aws_api_gateway_resource.meeting_id.id
  path_part   = "attendees"
}

# API Gateway resource: /meetings/{meetingId}/attendees/{attendeeId}
resource "aws_api_gateway_resource" "attendee_id" {
  rest_api_id = aws_api_gateway_rest_api.video_conferencing_api.id
  parent_id   = aws_api_gateway_resource.attendees.id
  path_part   = "{attendeeId}"
}

# CORS configuration for API Gateway
module "cors" {
  source = "squidfunk/api-gateway-enable-cors/aws"
  version = "0.3.3"

  api_id          = aws_api_gateway_rest_api.video_conferencing_api.id
  api_resource_id = aws_api_gateway_rest_api.video_conferencing_api.root_resource_id
  allow_origins   = var.cors_allowed_origins
  allow_methods   = var.cors_allowed_methods
  allow_headers   = var.cors_allowed_headers
}

# Meeting API methods and integrations
resource "aws_api_gateway_method" "create_meeting" {
  rest_api_id   = aws_api_gateway_rest_api.video_conferencing_api.id
  resource_id   = aws_api_gateway_resource.meetings.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "create_meeting" {
  rest_api_id = aws_api_gateway_rest_api.video_conferencing_api.id
  resource_id = aws_api_gateway_resource.meetings.id
  http_method = aws_api_gateway_method.create_meeting.http_method

  integration_http_method = "POST"
  type                   = "AWS_PROXY"
  uri                    = aws_lambda_function.meeting_handler.invoke_arn
}

resource "aws_api_gateway_method" "get_meeting" {
  rest_api_id   = aws_api_gateway_rest_api.video_conferencing_api.id
  resource_id   = aws_api_gateway_resource.meeting_id.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "get_meeting" {
  rest_api_id = aws_api_gateway_rest_api.video_conferencing_api.id
  resource_id = aws_api_gateway_resource.meeting_id.id
  http_method = aws_api_gateway_method.get_meeting.http_method

  integration_http_method = "POST"
  type                   = "AWS_PROXY"
  uri                    = aws_lambda_function.meeting_handler.invoke_arn
}

resource "aws_api_gateway_method" "delete_meeting" {
  rest_api_id   = aws_api_gateway_rest_api.video_conferencing_api.id
  resource_id   = aws_api_gateway_resource.meeting_id.id
  http_method   = "DELETE"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "delete_meeting" {
  rest_api_id = aws_api_gateway_rest_api.video_conferencing_api.id
  resource_id = aws_api_gateway_resource.meeting_id.id
  http_method = aws_api_gateway_method.delete_meeting.http_method

  integration_http_method = "POST"
  type                   = "AWS_PROXY"
  uri                    = aws_lambda_function.meeting_handler.invoke_arn
}

# Attendee API methods and integrations
resource "aws_api_gateway_method" "create_attendee" {
  rest_api_id   = aws_api_gateway_rest_api.video_conferencing_api.id
  resource_id   = aws_api_gateway_resource.attendees.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "create_attendee" {
  rest_api_id = aws_api_gateway_rest_api.video_conferencing_api.id
  resource_id = aws_api_gateway_resource.attendees.id
  http_method = aws_api_gateway_method.create_attendee.http_method

  integration_http_method = "POST"
  type                   = "AWS_PROXY"
  uri                    = aws_lambda_function.attendee_handler.invoke_arn
}

resource "aws_api_gateway_method" "get_attendee" {
  rest_api_id   = aws_api_gateway_rest_api.video_conferencing_api.id
  resource_id   = aws_api_gateway_resource.attendee_id.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "get_attendee" {
  rest_api_id = aws_api_gateway_rest_api.video_conferencing_api.id
  resource_id = aws_api_gateway_resource.attendee_id.id
  http_method = aws_api_gateway_method.get_attendee.http_method

  integration_http_method = "POST"
  type                   = "AWS_PROXY"
  uri                    = aws_lambda_function.attendee_handler.invoke_arn
}

resource "aws_api_gateway_method" "delete_attendee" {
  rest_api_id   = aws_api_gateway_rest_api.video_conferencing_api.id
  resource_id   = aws_api_gateway_resource.attendee_id.id
  http_method   = "DELETE"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "delete_attendee" {
  rest_api_id = aws_api_gateway_rest_api.video_conferencing_api.id
  resource_id = aws_api_gateway_resource.attendee_id.id
  http_method = aws_api_gateway_method.delete_attendee.http_method

  integration_http_method = "POST"
  type                   = "AWS_PROXY"
  uri                    = aws_lambda_function.attendee_handler.invoke_arn
}

# Lambda permissions for API Gateway
resource "aws_lambda_permission" "api_gateway_meeting_handler" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.meeting_handler.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.video_conferencing_api.execution_arn}/*/*"
}

resource "aws_lambda_permission" "api_gateway_attendee_handler" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.attendee_handler.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.video_conferencing_api.execution_arn}/*/*"
}

# API Gateway deployment
resource "aws_api_gateway_deployment" "video_conferencing_api" {
  rest_api_id = aws_api_gateway_rest_api.video_conferencing_api.id

  triggers = {
    # Redeploy when any of these resources change
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.meetings.id,
      aws_api_gateway_resource.meeting_id.id,
      aws_api_gateway_resource.attendees.id,
      aws_api_gateway_resource.attendee_id.id,
      aws_api_gateway_method.create_meeting.id,
      aws_api_gateway_method.get_meeting.id,
      aws_api_gateway_method.delete_meeting.id,
      aws_api_gateway_method.create_attendee.id,
      aws_api_gateway_method.get_attendee.id,
      aws_api_gateway_method.delete_attendee.id,
      aws_api_gateway_integration.create_meeting.id,
      aws_api_gateway_integration.get_meeting.id,
      aws_api_gateway_integration.delete_meeting.id,
      aws_api_gateway_integration.create_attendee.id,
      aws_api_gateway_integration.get_attendee.id,
      aws_api_gateway_integration.delete_attendee.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

# API Gateway stage
resource "aws_api_gateway_stage" "video_conferencing_api" {
  deployment_id = aws_api_gateway_deployment.video_conferencing_api.id
  rest_api_id   = aws_api_gateway_rest_api.video_conferencing_api.id
  stage_name    = var.api_gateway_stage_name

  # Enable detailed CloudWatch metrics if requested
  xray_tracing_enabled = var.enable_detailed_monitoring

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-api-${var.api_gateway_stage_name}"
    Description = "API Gateway stage for video conferencing API"
  })
}

# API Gateway method settings for throttling
resource "aws_api_gateway_method_settings" "video_conferencing_api" {
  rest_api_id = aws_api_gateway_rest_api.video_conferencing_api.id
  stage_name  = aws_api_gateway_stage.video_conferencing_api.stage_name
  method_path = "*/*"

  settings {
    metrics_enabled = var.enable_detailed_monitoring
    logging_level   = var.enable_detailed_monitoring ? "INFO" : "OFF"
    
    throttling_rate_limit  = var.api_gateway_throttle_rate_limit
    throttling_burst_limit = var.api_gateway_throttle_burst_limit
  }
}

# CloudWatch alarms for monitoring (if detailed monitoring is enabled)
resource "aws_cloudwatch_metric_alarm" "api_gateway_4xx_errors" {
  count = var.enable_detailed_monitoring ? 1 : 0
  
  alarm_name          = "${local.name_prefix}-api-4xx-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "4XXError"
  namespace           = "AWS/ApiGateway"
  period              = "300"
  statistic           = "Sum"
  threshold           = "10"
  alarm_description   = "This metric monitors 4XX errors from API Gateway"
  alarm_actions       = [aws_sns_topic.events.arn]

  dimensions = {
    ApiName   = aws_api_gateway_rest_api.video_conferencing_api.name
    Stage     = aws_api_gateway_stage.video_conferencing_api.stage_name
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "api_gateway_5xx_errors" {
  count = var.enable_detailed_monitoring ? 1 : 0
  
  alarm_name          = "${local.name_prefix}-api-5xx-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "5XXError"
  namespace           = "AWS/ApiGateway"
  period              = "300"
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "This metric monitors 5XX errors from API Gateway"
  alarm_actions       = [aws_sns_topic.events.arn]

  dimensions = {
    ApiName   = aws_api_gateway_rest_api.video_conferencing_api.name
    Stage     = aws_api_gateway_stage.video_conferencing_api.stage_name
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  count = var.enable_detailed_monitoring ? 1 : 0
  
  alarm_name          = "${local.name_prefix}-lambda-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "This metric monitors Lambda function errors"
  alarm_actions       = [aws_sns_topic.events.arn]

  tags = local.common_tags
}