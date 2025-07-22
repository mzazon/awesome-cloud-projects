# Random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Current AWS account and region data
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# S3 bucket for analytics export
resource "aws_s3_bucket" "analytics_export" {
  count = var.enable_analytics_export ? 1 : 0
  
  bucket = var.s3_bucket_name != "" ? var.s3_bucket_name : "${var.project_name}-analytics-${random_id.suffix.hex}"
  force_destroy = var.s3_force_destroy
  
  tags = merge(
    {
      Name = "Pinpoint Analytics Export"
      Purpose = "Store Pinpoint analytics exports"
    },
    var.additional_tags
  )
}

# S3 bucket versioning
resource "aws_s3_bucket_versioning" "analytics_export" {
  count = var.enable_analytics_export ? 1 : 0
  
  bucket = aws_s3_bucket.analytics_export[0].id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "analytics_export" {
  count = var.enable_analytics_export ? 1 : 0
  
  bucket = aws_s3_bucket.analytics_export[0].id
  
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 bucket public access block
resource "aws_s3_bucket_public_access_block" "analytics_export" {
  count = var.enable_analytics_export ? 1 : 0
  
  bucket = aws_s3_bucket.analytics_export[0].id
  
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# IAM role for Pinpoint S3 export
resource "aws_iam_role" "pinpoint_s3_export" {
  count = var.enable_analytics_export ? 1 : 0
  
  name = "PinpointAnalyticsRole-${random_id.suffix.hex}"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "pinpoint.amazonaws.com"
        }
      }
    ]
  })
  
  tags = merge(
    {
      Name = "Pinpoint S3 Export Role"
      Purpose = "Allow Pinpoint to export analytics to S3"
    },
    var.additional_tags
  )
}

# IAM policy for Pinpoint S3 export
resource "aws_iam_role_policy" "pinpoint_s3_export" {
  count = var.enable_analytics_export ? 1 : 0
  
  name = "PinpointS3ExportPolicy"
  role = aws_iam_role.pinpoint_s3_export[0].id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.analytics_export[0].arn,
          "${aws_s3_bucket.analytics_export[0].arn}/*"
        ]
      }
    ]
  })
}

# Kinesis stream for real-time event processing
resource "aws_kinesis_stream" "pinpoint_events" {
  count = var.enable_event_stream ? 1 : 0
  
  name             = "pinpoint-events-${random_id.suffix.hex}"
  shard_count      = var.kinesis_shard_count
  retention_period = var.kinesis_retention_period
  
  encryption_type = "KMS"
  kms_key_id      = "alias/aws/kinesis"
  
  tags = merge(
    {
      Name = "Pinpoint Events Stream"
      Purpose = "Real-time processing of Pinpoint events"
    },
    var.additional_tags
  )
}

# IAM role for Pinpoint Kinesis export
resource "aws_iam_role" "pinpoint_kinesis_export" {
  count = var.enable_event_stream ? 1 : 0
  
  name = "PinpointKinesisRole-${random_id.suffix.hex}"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "pinpoint.amazonaws.com"
        }
      }
    ]
  })
  
  tags = merge(
    {
      Name = "Pinpoint Kinesis Export Role"
      Purpose = "Allow Pinpoint to export events to Kinesis"
    },
    var.additional_tags
  )
}

# IAM policy for Pinpoint Kinesis export
resource "aws_iam_role_policy" "pinpoint_kinesis_export" {
  count = var.enable_event_stream ? 1 : 0
  
  name = "PinpointKinesisExportPolicy"
  role = aws_iam_role.pinpoint_kinesis_export[0].id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kinesis:PutRecord",
          "kinesis:PutRecords",
          "kinesis:DescribeStream"
        ]
        Resource = aws_kinesis_stream.pinpoint_events[0].arn
      }
    ]
  })
}

# Amazon Pinpoint application
resource "aws_pinpoint_app" "mobile_ab_testing" {
  name = "${var.pinpoint_application_name}-${random_id.suffix.hex}"
  
  tags = merge(
    {
      Name = "Mobile AB Testing App"
      Purpose = "A/B testing for mobile applications"
    },
    var.additional_tags
  )
}

# Pinpoint application settings
resource "aws_pinpoint_app_settings" "mobile_ab_testing" {
  application_id = aws_pinpoint_app.mobile_ab_testing.application_id
  
  # Campaign hook configuration (optional)
  campaign_hook {
    lambda_function_name = var.create_winner_selection_lambda ? aws_lambda_function.winner_selection[0].function_name : null
    mode                 = "DELIVERY"
  }
  
  # CloudWatch metrics
  cloudwatch_metrics_enabled = true
  
  # Limits
  limits {
    daily                 = var.campaign_daily_limit
    maximum_duration      = 86400
    messages_per_second   = var.campaign_messages_per_second
    total                 = var.campaign_total_limit
  }
  
  # Quiet time (optional - prevents messages during specified hours)
  quiet_time {
    start = "22:00"
    end   = "08:00"
  }
}

# GCM/FCM channel configuration (Android)
resource "aws_pinpoint_gcm_channel" "mobile_ab_testing" {
  count = var.firebase_server_key != "" ? 1 : 0
  
  application_id = aws_pinpoint_app.mobile_ab_testing.application_id
  api_key        = var.firebase_server_key
  enabled        = true
}

# APNS channel configuration (iOS Production)
resource "aws_pinpoint_apns_channel" "mobile_ab_testing" {
  count = var.apns_certificate != "" && var.apns_private_key != "" && !var.enable_apns_sandbox ? 1 : 0
  
  application_id = aws_pinpoint_app.mobile_ab_testing.application_id
  certificate    = var.apns_certificate
  private_key    = var.apns_private_key
  enabled        = true
}

# APNS sandbox channel configuration (iOS Development)
resource "aws_pinpoint_apns_sandbox_channel" "mobile_ab_testing" {
  count = var.apns_certificate != "" && var.apns_private_key != "" && var.enable_apns_sandbox ? 1 : 0
  
  application_id = aws_pinpoint_app.mobile_ab_testing.application_id
  certificate    = var.apns_certificate
  private_key    = var.apns_private_key
  enabled        = true
}

# Event stream configuration
resource "aws_pinpoint_event_stream" "mobile_ab_testing" {
  count = var.enable_event_stream ? 1 : 0
  
  application_id         = aws_pinpoint_app.mobile_ab_testing.application_id
  destination_stream_arn = aws_kinesis_stream.pinpoint_events[0].arn
  role_arn              = aws_iam_role.pinpoint_kinesis_export[0].arn
}

# Active users segment
resource "aws_pinpoint_segment" "active_users" {
  application_id = aws_pinpoint_app.mobile_ab_testing.application_id
  name           = "ActiveUsers"
  
  dimensions {
    demographic {
      app_version {
        dimension_type = "INCLUSIVE"
        values         = var.app_versions
      }
    }
  }
  
  tags = merge(
    {
      Name = "Active Users Segment"
      Purpose = "Target users with specific app versions"
    },
    var.additional_tags
  )
}

# High-value users segment
resource "aws_pinpoint_segment" "high_value_users" {
  application_id = aws_pinpoint_app.mobile_ab_testing.application_id
  name           = "HighValueUsers"
  
  dimensions {
    behavior {
      recency {
        duration     = "DAY_${var.high_value_recency_days}"
        recency_type = "ACTIVE"
      }
    }
    
    metrics {
      session_count {
        comparison_operator = "GREATER_THAN"
        value              = var.high_value_session_threshold
      }
    }
  }
  
  tags = merge(
    {
      Name = "High Value Users Segment"
      Purpose = "Target highly engaged users"
    },
    var.additional_tags
  )
}

# CloudWatch dashboard
resource "aws_cloudwatch_dashboard" "pinpoint_ab_testing" {
  count = var.create_cloudwatch_dashboard ? 1 : 0
  
  dashboard_name = "${var.dashboard_name}-${random_id.suffix.hex}"
  
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
            ["AWS/Pinpoint", "DirectMessagesSent", "ApplicationId", aws_pinpoint_app.mobile_ab_testing.application_id],
            [".", "DirectMessagesDelivered", ".", "."],
            [".", "DirectMessagesBounced", ".", "."],
            [".", "DirectMessagesOpened", ".", "."]
          ]
          period = 300
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "Campaign Delivery Metrics"
          view   = "timeSeries"
          yAxis = {
            left = {
              min = 0
            }
          }
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
            ["AWS/Pinpoint", "CustomEvents", "ApplicationId", aws_pinpoint_app.mobile_ab_testing.application_id, "EventType", "conversion"]
          ]
          period = 300
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "Conversion Events"
          view   = "timeSeries"
          yAxis = {
            left = {
              min = 0
            }
          }
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
            ["AWS/Pinpoint", "DirectMessagesClickthrough", "ApplicationId", aws_pinpoint_app.mobile_ab_testing.application_id],
            [".", "DirectMessagesOptOut", ".", "."]
          ]
          period = 300
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "User Engagement Metrics"
          view   = "timeSeries"
          yAxis = {
            left = {
              min = 0
            }
          }
        }
      }
    ]
  })
}

# Lambda function for automated winner selection
resource "aws_lambda_function" "winner_selection" {
  count = var.create_winner_selection_lambda ? 1 : 0
  
  function_name = "${var.lambda_function_name}-${random_id.suffix.hex}"
  role          = aws_iam_role.lambda_execution[0].arn
  handler       = "index.lambda_handler"
  runtime       = "python3.9"
  timeout       = 60
  
  filename         = data.archive_file.winner_selection_zip[0].output_path
  source_code_hash = data.archive_file.winner_selection_zip[0].output_base64sha256
  
  environment {
    variables = {
      PINPOINT_APP_ID = aws_pinpoint_app.mobile_ab_testing.application_id
    }
  }
  
  tags = merge(
    {
      Name = "Winner Selection Lambda"
      Purpose = "Automated A/B test winner selection"
    },
    var.additional_tags
  )
}

# Lambda function code
data "archive_file" "winner_selection_zip" {
  count = var.create_winner_selection_lambda ? 1 : 0
  
  type        = "zip"
  output_path = "${path.module}/winner_selection.zip"
  
  source {
    content = file("${path.module}/winner_selection.py")
    filename = "index.py"
  }
}

# Lambda execution role
resource "aws_iam_role" "lambda_execution" {
  count = var.create_winner_selection_lambda ? 1 : 0
  
  name = "WinnerSelectionLambdaRole-${random_id.suffix.hex}"
  
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
  
  tags = merge(
    {
      Name = "Winner Selection Lambda Role"
      Purpose = "Execution role for winner selection Lambda"
    },
    var.additional_tags
  )
}

# Lambda execution policy
resource "aws_iam_role_policy" "lambda_execution" {
  count = var.create_winner_selection_lambda ? 1 : 0
  
  name = "WinnerSelectionLambdaPolicy"
  role = aws_iam_role.lambda_execution[0].id
  
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
          "mobiletargeting:GetCampaign",
          "mobiletargeting:GetCampaignActivities",
          "mobiletargeting:UpdateCampaign",
          "mobiletargeting:GetApplicationSettings"
        ]
        Resource = [
          aws_pinpoint_app.mobile_ab_testing.arn,
          "${aws_pinpoint_app.mobile_ab_testing.arn}/*"
        ]
      }
    ]
  })
}

# Create Lambda function source file
resource "local_file" "winner_selection_lambda" {
  count = var.create_winner_selection_lambda ? 1 : 0
  
  content = templatefile("${path.module}/winner_selection_template.py", {
    application_id = aws_pinpoint_app.mobile_ab_testing.application_id
  })
  
  filename = "${path.module}/winner_selection.py"
}

# CloudWatch log group for Lambda
resource "aws_cloudwatch_log_group" "winner_selection_logs" {
  count = var.create_winner_selection_lambda ? 1 : 0
  
  name              = "/aws/lambda/${var.lambda_function_name}-${random_id.suffix.hex}"
  retention_in_days = 14
  
  tags = merge(
    {
      Name = "Winner Selection Lambda Logs"
      Purpose = "Log group for winner selection Lambda"
    },
    var.additional_tags
  )
}

# Wait for IAM role propagation
resource "time_sleep" "iam_propagation" {
  depends_on = [
    aws_iam_role.pinpoint_s3_export,
    aws_iam_role.pinpoint_kinesis_export,
    aws_iam_role.lambda_execution
  ]
  
  create_duration = "30s"
}