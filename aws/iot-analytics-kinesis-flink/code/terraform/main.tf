# Real-Time IoT Analytics Infrastructure
# This file creates the complete infrastructure for IoT analytics pipeline
# including Kinesis, Lambda, Flink, S3, SNS, and monitoring components

# Get current AWS account ID and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource names
resource "random_password" "suffix" {
  length  = 6
  special = false
  upper   = false
}

locals {
  # Resource naming with random suffix
  resource_prefix = "${var.project_name}-${random_password.suffix.result}"
  
  # Common tags for all resources
  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Recipe      = "real-time-iot-analytics-kinesis-iot-analytics"
    },
    var.additional_tags
  )
}

# ===================================
# S3 BUCKET FOR DATA STORAGE
# ===================================

# S3 bucket for storing raw data, processed data, and analytics results
resource "aws_s3_bucket" "data_bucket" {
  bucket = "${local.resource_prefix}-data-${data.aws_caller_identity.current.account_id}"
  
  tags = merge(local.common_tags, {
    Name = "IoT Analytics Data Bucket"
    Purpose = "Data storage for IoT analytics pipeline"
  })
}

# S3 bucket versioning configuration
resource "aws_s3_bucket_versioning" "data_bucket_versioning" {
  bucket = aws_s3_bucket.data_bucket.id
  versioning_configuration {
    status = var.s3_versioning_enabled ? "Enabled" : "Disabled"
  }
}

# S3 bucket server-side encryption configuration
resource "aws_s3_bucket_server_side_encryption_configuration" "data_bucket_encryption" {
  bucket = aws_s3_bucket.data_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 bucket public access block
resource "aws_s3_bucket_public_access_block" "data_bucket_pab" {
  bucket = aws_s3_bucket.data_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket lifecycle configuration
resource "aws_s3_bucket_lifecycle_configuration" "data_bucket_lifecycle" {
  count  = var.s3_lifecycle_enabled ? 1 : 0
  bucket = aws_s3_bucket.data_bucket.id

  rule {
    id     = "iot_data_lifecycle"
    status = "Enabled"

    transition {
      days          = var.s3_transition_to_ia_days
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = var.s3_transition_to_glacier_days
      storage_class = "GLACIER"
    }

    expiration {
      days = var.s3_expiration_days
    }
  }
}

# Create folder structure in S3 bucket
resource "aws_s3_object" "raw_data_folder" {
  bucket = aws_s3_bucket.data_bucket.id
  key    = "raw-data/"
  
  tags = local.common_tags
}

resource "aws_s3_object" "processed_data_folder" {
  bucket = aws_s3_bucket.data_bucket.id
  key    = "processed-data/"
  
  tags = local.common_tags
}

resource "aws_s3_object" "analytics_results_folder" {
  bucket = aws_s3_bucket.data_bucket.id
  key    = "analytics-results/"
  
  tags = local.common_tags
}

# ===================================
# KINESIS DATA STREAM
# ===================================

# Kinesis Data Stream for IoT data ingestion
resource "aws_kinesis_stream" "iot_stream" {
  name        = "${local.resource_prefix}-stream"
  shard_count = var.kinesis_shard_count
  
  retention_period = var.kinesis_retention_period
  
  stream_mode_details {
    stream_mode = "PROVISIONED"
  }
  
  shard_level_metrics = [
    "IncomingRecords",
    "OutgoingRecords",
    "IncomingBytes",
    "OutgoingBytes"
  ]
  
  tags = merge(local.common_tags, {
    Name = "IoT Data Stream"
    Purpose = "Data ingestion for IoT sensors"
  })
}

# ===================================
# SNS TOPIC FOR ALERTS
# ===================================

# SNS topic for sending alerts
resource "aws_sns_topic" "alerts" {
  name = "${local.resource_prefix}-alerts"
  
  tags = merge(local.common_tags, {
    Name = "IoT Analytics Alerts"
    Purpose = "Anomaly detection alerts"
  })
}

# SNS topic policy for publishing from Lambda
resource "aws_sns_topic_policy" "alerts_policy" {
  arn = aws_sns_topic.alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.lambda_role.arn
        }
        Action = "sns:Publish"
        Resource = aws_sns_topic.alerts.arn
      }
    ]
  })
}

# SNS email subscription (optional)
resource "aws_sns_topic_subscription" "email_alert" {
  count     = var.alert_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ===================================
# IAM ROLES AND POLICIES
# ===================================

# IAM role for Lambda function
resource "aws_iam_role" "lambda_role" {
  name = "${local.resource_prefix}-lambda-role"

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
    Name = "Lambda Execution Role"
    Purpose = "IAM role for Lambda IoT processor"
  })
}

# IAM policy for Lambda function
resource "aws_iam_role_policy" "lambda_policy" {
  name = "${local.resource_prefix}-lambda-policy"
  role = aws_iam_role.lambda_role.id

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
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
      },
      {
        Effect = "Allow"
        Action = [
          "kinesis:DescribeStream",
          "kinesis:GetRecords",
          "kinesis:GetShardIterator",
          "kinesis:ListStreams"
        ]
        Resource = aws_kinesis_stream.iot_stream.arn
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject"
        ]
        Resource = "${aws_s3_bucket.data_bucket.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.alerts.arn
      }
    ]
  })
}

# IAM role for Flink application
resource "aws_iam_role" "flink_role" {
  name = "${local.resource_prefix}-flink-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "kinesisanalytics.amazonaws.com"
        }
      }
    ]
  })
  
  tags = merge(local.common_tags, {
    Name = "Flink Execution Role"
    Purpose = "IAM role for Flink application"
  })
}

# IAM policy for Flink application
resource "aws_iam_role_policy" "flink_policy" {
  name = "${local.resource_prefix}-flink-policy"
  role = aws_iam_role.flink_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kinesis:DescribeStream",
          "kinesis:GetRecords",
          "kinesis:GetShardIterator",
          "kinesis:ListStreams"
        ]
        Resource = aws_kinesis_stream.iot_stream.arn
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.data_bucket.arn,
          "${aws_s3_bucket.data_bucket.arn}/*"
        ]
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

# ===================================
# LAMBDA FUNCTION
# ===================================

# CloudWatch Log Group for Lambda
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${local.resource_prefix}-processor"
  retention_in_days = var.cloudwatch_log_retention_days
  
  tags = merge(local.common_tags, {
    Name = "Lambda Log Group"
    Purpose = "Logs for IoT processor Lambda"
  })
}

# Lambda function for IoT data processing
resource "aws_lambda_function" "iot_processor" {
  filename         = "iot-processor.zip"
  function_name    = "${local.resource_prefix}-processor"
  role            = aws_iam_role.lambda_role.arn
  handler         = "iot-processor.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  
  environment {
    variables = {
      S3_BUCKET_NAME      = aws_s3_bucket.data_bucket.id
      SNS_TOPIC_ARN       = aws_sns_topic.alerts.arn
      TEMPERATURE_THRESHOLD = var.temperature_threshold
      PRESSURE_THRESHOLD   = var.pressure_threshold
      VIBRATION_THRESHOLD  = var.vibration_threshold
      FLOW_THRESHOLD      = var.flow_threshold
    }
  }
  
  depends_on = [
    aws_cloudwatch_log_group.lambda_logs,
    data.archive_file.lambda_zip
  ]
  
  tags = merge(local.common_tags, {
    Name = "IoT Data Processor"
    Purpose = "Process IoT sensor data"
  })
}

# Create Lambda deployment package
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "iot-processor.zip"
  source {
    content = templatefile("${path.module}/lambda/iot-processor.py", {
      temperature_threshold = var.temperature_threshold
      pressure_threshold   = var.pressure_threshold
      vibration_threshold  = var.vibration_threshold
      flow_threshold      = var.flow_threshold
    })
    filename = "iot-processor.py"
  }
}

# Lambda event source mapping for Kinesis
resource "aws_lambda_event_source_mapping" "kinesis_lambda" {
  event_source_arn  = aws_kinesis_stream.iot_stream.arn
  function_name     = aws_lambda_function.iot_processor.function_name
  starting_position = "LATEST"
  batch_size        = var.lambda_batch_size
  maximum_batching_window_in_seconds = var.lambda_batch_window
}

# ===================================
# FLINK APPLICATION
# ===================================

# Upload Flink application code to S3
resource "aws_s3_object" "flink_app" {
  bucket = aws_s3_bucket.data_bucket.id
  key    = "flink-app.zip"
  source = data.archive_file.flink_zip.output_path
  etag   = data.archive_file.flink_zip.output_md5
  
  tags = local.common_tags
}

# Create Flink application deployment package
data "archive_file" "flink_zip" {
  type        = "zip"
  output_path = "flink-app.zip"
  source {
    content = templatefile("${path.module}/flink/flink-app.py", {
      kinesis_stream_name = aws_kinesis_stream.iot_stream.name
      s3_bucket_name     = aws_s3_bucket.data_bucket.id
      aws_region         = data.aws_region.current.name
    })
    filename = "flink-app.py"
  }
}

# Flink application for stream analytics
resource "aws_kinesisanalyticsv2_application" "flink_app" {
  name                   = "${local.resource_prefix}-flink-app"
  runtime_environment   = var.flink_runtime_environment
  service_execution_role = aws_iam_role.flink_role.arn
  
  application_configuration {
    application_code_configuration {
      code_content {
        s3_content_location {
          bucket_arn = aws_s3_bucket.data_bucket.arn
          file_key   = aws_s3_object.flink_app.key
        }
      }
      code_content_type = "ZIPFILE"
    }
    
    environment_properties {
      property_group {
        property_group_id = "kinesis.analytics.flink.run.options"
        property_map = {
          python = "flink-app.py"
        }
      }
    }
    
    flink_application_configuration {
      checkpoint_configuration {
        configuration_type = "CUSTOM"
        checkpointing_enabled = true
        checkpoint_interval = var.flink_checkpoint_interval
        min_pause_between_checkpoints = 5000
      }
      
      monitoring_configuration {
        configuration_type = "CUSTOM"
        log_level         = "INFO"
        metrics_level     = "APPLICATION"
      }
      
      parallelism_configuration {
        configuration_type = "CUSTOM"
        parallelism       = var.flink_parallelism
        parallelism_per_kpu = 1
        auto_scaling_enabled = true
      }
    }
  }
  
  tags = merge(local.common_tags, {
    Name = "IoT Analytics Flink App"
    Purpose = "Stream processing for IoT data"
  })
}

# ===================================
# CLOUDWATCH ALARMS
# ===================================

# CloudWatch alarm for Kinesis stream records
resource "aws_cloudwatch_metric_alarm" "kinesis_records" {
  alarm_name          = "${local.resource_prefix}-kinesis-records"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "IncomingRecords"
  namespace           = "AWS/Kinesis"
  period              = "300"
  statistic           = "Sum"
  threshold           = var.kinesis_records_threshold
  alarm_description   = "This metric monitors Kinesis stream incoming records"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  
  dimensions = {
    StreamName = aws_kinesis_stream.iot_stream.name
  }
  
  tags = merge(local.common_tags, {
    Name = "Kinesis Records Alarm"
  })
}

# CloudWatch alarm for Lambda errors
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "${local.resource_prefix}-lambda-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = var.lambda_errors_threshold
  alarm_description   = "This metric monitors Lambda function errors"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  
  dimensions = {
    FunctionName = aws_lambda_function.iot_processor.function_name
  }
  
  tags = merge(local.common_tags, {
    Name = "Lambda Errors Alarm"
  })
}

# ===================================
# CLOUDWATCH DASHBOARD
# ===================================

# CloudWatch dashboard for monitoring
resource "aws_cloudwatch_dashboard" "iot_analytics" {
  dashboard_name = "${local.resource_prefix}-analytics"
  
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
            ["AWS/Kinesis", "IncomingRecords", "StreamName", aws_kinesis_stream.iot_stream.name],
            [".", "OutgoingRecords", ".", "."]
          ]
          period = 300
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "Kinesis Stream Metrics"
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
            ["AWS/Lambda", "Invocations", "FunctionName", aws_lambda_function.iot_processor.function_name],
            [".", "Errors", ".", "."],
            [".", "Duration", ".", "."]
          ]
          period = 300
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "Lambda Function Metrics"
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
            ["AWS/KinesisAnalytics", "numRecordsOut", "Application", aws_kinesisanalyticsv2_application.flink_app.name],
            [".", "numRecordsIn", ".", "."]
          ]
          period = 300
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "Flink Application Metrics"
        }
      }
    ]
  })
}