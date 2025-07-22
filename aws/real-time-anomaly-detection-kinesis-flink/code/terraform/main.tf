# Real-time Anomaly Detection Infrastructure with AWS Managed Service for Apache Flink
# This Terraform configuration deploys a complete real-time anomaly detection system
# using Kinesis Data Streams, Managed Service for Apache Flink, CloudWatch, and SNS

# Data sources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  name_prefix = "${var.project_name}-${var.environment}"
  name_suffix = random_id.suffix.hex
  
  common_tags = merge(var.tags, {
    Project     = var.project_name
    Environment = var.environment
    CreatedBy   = "terraform"
    Recipe      = "real-time-anomaly-detection-kinesis-data-analytics"
  })
}

# ================================
# S3 Bucket for Application Artifacts and Data Storage
# ================================

# S3 bucket for storing Flink application JAR and processed data
resource "aws_s3_bucket" "anomaly_data" {
  bucket = "${local.name_prefix}-anomaly-data-${local.name_suffix}"
  
  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-anomaly-data-${local.name_suffix}"
    Purpose     = "Data storage and application artifacts"
    Component   = "Storage"
  })
}

# S3 bucket versioning configuration
resource "aws_s3_bucket_versioning" "anomaly_data_versioning" {
  bucket = aws_s3_bucket.anomaly_data.id
  versioning_configuration {
    status = var.s3_bucket_versioning ? "Enabled" : "Disabled"
  }
}

# S3 bucket server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "anomaly_data_encryption" {
  count  = var.enable_s3_encryption ? 1 : 0
  bucket = aws_s3_bucket.anomaly_data.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# S3 bucket public access block
resource "aws_s3_bucket_public_access_block" "anomaly_data_pab" {
  bucket = aws_s3_bucket.anomaly_data.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Create application folder structure in S3
resource "aws_s3_object" "applications_folder" {
  bucket = aws_s3_bucket.anomaly_data.id
  key    = "applications/"
  content_type = "application/x-directory"
  
  tags = local.common_tags
}

# ================================
# Kinesis Data Stream
# ================================

# Kinesis Data Stream for ingesting transaction data
resource "aws_kinesis_stream" "transaction_stream" {
  name             = "${local.name_prefix}-transaction-stream-${local.name_suffix}"
  shard_count      = var.kinesis_stream_shard_count
  retention_period = var.kinesis_stream_retention_period

  # Enable server-side encryption
  encryption_type = "KMS"
  kms_key_id      = "alias/aws/kinesis"

  # Enable enhanced fan-out for improved performance
  shard_level_metrics = var.enable_enhanced_monitoring ? [
    "IncomingRecords",
    "IncomingBytes",
    "OutgoingRecords",
    "OutgoingBytes",
    "WriteProvisionedThroughputExceeded",
    "ReadProvisionedThroughputExceeded",
    "IteratorAgeMilliseconds"
  ] : []

  tags = merge(local.common_tags, {
    Name      = "${local.name_prefix}-transaction-stream-${local.name_suffix}"
    Purpose   = "Transaction data ingestion"
    Component = "Streaming"
  })
}

# ================================
# Kinesis Data Firehose for Data Archival
# ================================

# IAM role for Kinesis Data Firehose
resource "aws_iam_role" "firehose_delivery_role" {
  name = "${local.name_prefix}-firehose-delivery-role-${local.name_suffix}"

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

# IAM policy for Kinesis Data Firehose S3 delivery
resource "aws_iam_role_policy" "firehose_delivery_policy" {
  name = "${local.name_prefix}-firehose-delivery-policy-${local.name_suffix}"
  role = aws_iam_role.firehose_delivery_role.id

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
          aws_s3_bucket.anomaly_data.arn,
          "${aws_s3_bucket.anomaly_data.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
      }
    ]
  })
}

# Kinesis Data Firehose delivery stream for data archival
resource "aws_kinesis_firehose_delivery_stream" "anomaly_data_stream" {
  name        = "${local.name_prefix}-anomaly-firehose-${local.name_suffix}"
  destination = "s3"

  s3_configuration {
    role_arn           = aws_iam_role.firehose_delivery_role.arn
    bucket_arn         = aws_s3_bucket.anomaly_data.arn
    prefix             = "processed-data/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/hour=!{timestamp:HH}/"
    error_output_prefix = "error-data/"
    buffer_size        = 5
    buffer_interval    = 300
    compression_format = "GZIP"
  }

  tags = merge(local.common_tags, {
    Name      = "${local.name_prefix}-anomaly-firehose-${local.name_suffix}"
    Purpose   = "Data archival"
    Component = "Streaming"
  })
}

# ================================
# IAM Roles and Policies for Flink Application
# ================================

# IAM role for Managed Service for Apache Flink
resource "aws_iam_role" "flink_service_role" {
  name = "${local.name_prefix}-flink-service-role-${local.name_suffix}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "kinesisanalytics.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name      = "${local.name_prefix}-flink-service-role-${local.name_suffix}"
    Purpose   = "Flink application execution"
    Component = "IAM"
  })
}

# IAM policy for Flink application permissions
resource "aws_iam_role_policy" "flink_service_policy" {
  name = "${local.name_prefix}-flink-service-policy-${local.name_suffix}"
  role = aws_iam_role.flink_service_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kinesis:DescribeStream",
          "kinesis:GetShardIterator",
          "kinesis:GetRecords",
          "kinesis:ListShards",
          "kinesis:DescribeStreamSummary"
        ]
        Resource = aws_kinesis_stream.transaction_stream.arn
      },
      {
        Effect = "Allow"
        Action = [
          "firehose:DeliveryStartPosition",
          "firehose:DescribeDeliveryStream",
          "firehose:PutRecord",
          "firehose:PutRecordBatch"
        ]
        Resource = aws_kinesis_firehose_delivery_stream.anomaly_data_stream.arn
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.anomaly_data.arn,
          "${aws_s3_bucket.anomaly_data.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/kinesis-analytics/*"
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
          "sns:Publish"
        ]
        Resource = aws_sns_topic.anomaly_alerts.arn
      }
    ]
  })
}

# ================================
# CloudWatch Log Group for Flink Application
# ================================

# CloudWatch log group for Flink application logs
resource "aws_cloudwatch_log_group" "flink_app_logs" {
  name              = "/aws/kinesis-analytics/${local.name_prefix}-anomaly-detector-${local.name_suffix}"
  retention_in_days = var.cloudwatch_log_retention_days
  kms_key_id        = aws_kms_key.log_encryption_key.arn

  tags = merge(local.common_tags, {
    Name      = "/aws/kinesis-analytics/${local.name_prefix}-anomaly-detector-${local.name_suffix}"
    Purpose   = "Flink application logging"
    Component = "Logging"
  })
}

# KMS key for log encryption
resource "aws_kms_key" "log_encryption_key" {
  description             = "KMS key for CloudWatch log encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true

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
        Effect = "Allow"
        Principal = {
          Service = "logs.${data.aws_region.current.name}.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
        Condition = {
          ArnEquals = {
            "kms:EncryptionContext:aws:logs:arn" = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/kinesis-analytics/${local.name_prefix}-anomaly-detector-${local.name_suffix}"
          }
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name      = "${local.name_prefix}-log-encryption-key-${local.name_suffix}"
    Purpose   = "Log encryption"
    Component = "Security"
  })
}

# KMS key alias
resource "aws_kms_alias" "log_encryption_key_alias" {
  name          = "alias/${local.name_prefix}-log-encryption-${local.name_suffix}"
  target_key_id = aws_kms_key.log_encryption_key.key_id
}

# ================================
# Managed Service for Apache Flink Application
# ================================

# Managed Service for Apache Flink application for anomaly detection
resource "aws_kinesisanalyticsv2_application" "anomaly_detector" {
  name                   = "${local.name_prefix}-anomaly-detector-${local.name_suffix}"
  runtime_environment    = "FLINK-1_18"
  service_execution_role = aws_iam_role.flink_service_role.arn
  description           = "Real-time anomaly detection for transaction data using Apache Flink"

  application_configuration {
    # Application code configuration
    application_code_configuration {
      code_content {
        # Note: In production, you would upload your JAR file to S3
        # For this demo, we're creating a placeholder configuration
        text_content = "// Placeholder for Flink application code"
      }
      code_content_type = "PLAINTEXT"
    }

    # Environment properties for the Flink application
    environment_properties {
      property_group {
        property_group_id = "kinesis.analytics.flink.run.options"
        property_map = {
          "python.fn-execution.bundle.size" = "1000"
          "python.fn-execution.bundle.time" = "1000"
        }
      }
      
      property_group {
        property_group_id = "anomaly.detection.config"
        property_map = {
          "threshold.multiplier" = tostring(var.anomaly_threshold_multiplier)
          "window.size.minutes"  = "5"
          "kinesis.stream.name"  = aws_kinesis_stream.transaction_stream.name
          "sns.topic.arn"        = aws_sns_topic.anomaly_alerts.arn
        }
      }
    }

    # Flink application configuration
    flink_application_configuration {
      # Checkpoint configuration for fault tolerance
      checkpoint_configuration {
        configuration_type                = "CUSTOM"
        checkpointing_enabled            = true
        checkpoint_interval              = var.checkpoint_interval_ms
        min_pause_between_checkpoints    = 5000
        checkpoint_timeout               = 60000
      }

      # Monitoring configuration
      monitoring_configuration {
        configuration_type = "CUSTOM"
        log_level         = "INFO"
        metrics_level     = "APPLICATION"
      }

      # Parallelism configuration for performance tuning
      parallelism_configuration {
        configuration_type   = "CUSTOM"
        parallelism         = var.flink_parallelism
        parallelism_per_kpu = var.flink_parallelism_per_kpu
        auto_scaling_enabled = true
      }
    }

    # SQL-based application configuration (alternative to Java)
    sql_application_configuration {
      input {
        name_prefix = "SOURCE_SQL_STREAM"
        input_parallelism {
          count = var.flink_parallelism
        }
        input_schema {
          record_column {
            name     = "userId"
            sql_type = "VARCHAR(32)"
            mapping  = "$.userId"
          }
          record_column {
            name     = "amount"
            sql_type = "DOUBLE"
            mapping  = "$.amount"
          }
          record_column {
            name     = "timestamp"
            sql_type = "BIGINT"
            mapping  = "$.timestamp"
          }
          record_column {
            name     = "transactionId"
            sql_type = "VARCHAR(64)"
            mapping  = "$.transactionId"
          }
          record_column {
            name     = "merchantId"
            sql_type = "VARCHAR(32)"
            mapping  = "$.merchantId"
          }
          record_format {
            record_format_type = "JSON"
            mapping_parameters {
              json_mapping_parameters {
                record_row_path = "$"
              }
            }
          }
        }
        kinesis_streams_input {
          resource_arn = aws_kinesis_stream.transaction_stream.arn
        }
      }

      output {
        name = "DESTINATION_SQL_STREAM"
        destination_schema {
          record_format_type = "JSON"
        }
        kinesis_firehose_output {
          resource_arn = aws_kinesis_firehose_delivery_stream.anomaly_data_stream.arn
        }
      }

      reference_data_source {
        table_name = "anomaly_thresholds"
        reference_schema {
          record_column {
            name     = "userId"
            sql_type = "VARCHAR(32)"
            mapping  = "$.userId"
          }
          record_column {
            name     = "threshold"
            sql_type = "DOUBLE"
            mapping  = "$.threshold"
          }
          record_format {
            record_format_type = "JSON"
            mapping_parameters {
              json_mapping_parameters {
                record_row_path = "$"
              }
            }
          }
        }
        s3_reference_data_source {
          bucket_arn = aws_s3_bucket.anomaly_data.arn
          file_key   = "reference-data/thresholds.json"
        }
      }
    }

    # VPC configuration (optional - uncomment if VPC deployment is required)
    # vpc_configuration {
    #   security_group_ids = [aws_security_group.flink_app.id]
    #   subnet_ids         = data.aws_subnets.private.ids
    # }
  }

  tags = merge(local.common_tags, {
    Name      = "${local.name_prefix}-anomaly-detector-${local.name_suffix}"
    Purpose   = "Real-time anomaly detection"
    Component = "Analytics"
  })

  depends_on = [
    aws_iam_role_policy.flink_service_policy,
    aws_cloudwatch_log_group.flink_app_logs
  ]
}

# ================================
# SNS Topic for Anomaly Alerts
# ================================

# SNS topic for anomaly notifications
resource "aws_sns_topic" "anomaly_alerts" {
  name         = "${local.name_prefix}-anomaly-alerts-${local.name_suffix}"
  display_name = "Anomaly Detection Alerts"

  # Enable encryption for sensitive alerts
  kms_master_key_id = aws_kms_key.sns_encryption_key.id

  tags = merge(local.common_tags, {
    Name      = "${local.name_prefix}-anomaly-alerts-${local.name_suffix}"
    Purpose   = "Anomaly notifications"
    Component = "Notifications"
  })
}

# KMS key for SNS encryption
resource "aws_kms_key" "sns_encryption_key" {
  description             = "KMS key for SNS topic encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true

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
        Effect = "Allow"
        Principal = {
          Service = "sns.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name      = "${local.name_prefix}-sns-encryption-key-${local.name_suffix}"
    Purpose   = "SNS encryption"
    Component = "Security"
  })
}

# KMS key alias for SNS
resource "aws_kms_alias" "sns_encryption_key_alias" {
  name          = "alias/${local.name_prefix}-sns-encryption-${local.name_suffix}"
  target_key_id = aws_kms_key.sns_encryption_key.key_id
}

# SNS topic policy for enhanced security
resource "aws_sns_topic_policy" "anomaly_alerts_policy" {
  arn = aws_sns_topic.anomaly_alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowAccountOwnerAccess"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action = [
          "SNS:GetTopicAttributes",
          "SNS:SetTopicAttributes",
          "SNS:AddPermission",
          "SNS:RemovePermission",
          "SNS:DeleteTopic",
          "SNS:Subscribe",
          "SNS:ListSubscriptionsByTopic",
          "SNS:Publish"
        ]
        Resource = aws_sns_topic.anomaly_alerts.arn
      },
      {
        Sid    = "AllowFlinkApplicationPublish"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.flink_service_role.arn
        }
        Action = "SNS:Publish"
        Resource = aws_sns_topic.anomaly_alerts.arn
      },
      {
        Sid    = "AllowLambdaFunctionPublish"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.lambda_execution_role.arn
        }
        Action = "SNS:Publish"
        Resource = aws_sns_topic.anomaly_alerts.arn
      }
    ]
  })
}

# Optional: Email subscription to SNS topic (if email provided)
resource "aws_sns_topic_subscription" "email_alerts" {
  count     = var.notification_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.anomaly_alerts.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# ================================
# Lambda Function for Anomaly Processing
# ================================

# IAM role for Lambda function
resource "aws_iam_role" "lambda_execution_role" {
  name = "${local.name_prefix}-lambda-execution-role-${local.name_suffix}"

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
    Name      = "${local.name_prefix}-lambda-execution-role-${local.name_suffix}"
    Purpose   = "Lambda function execution"
    Component = "IAM"
  })
}

# IAM policy for Lambda function
resource "aws_iam_role_policy" "lambda_execution_policy" {
  name = "${local.name_prefix}-lambda-execution-policy-${local.name_suffix}"
  role = aws_iam_role.lambda_execution_role.id

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
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${local.name_prefix}-anomaly-processor-${local.name_suffix}:*"
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
          "sns:Publish"
        ]
        Resource = aws_sns_topic.anomaly_alerts.arn
      },
      {
        Effect = "Allow"
        Action = [
          "kinesis:DescribeStream",
          "kinesis:GetShardIterator",
          "kinesis:GetRecords",
          "kinesis:ListShards"
        ]
        Resource = aws_kinesis_stream.transaction_stream.arn
      }
    ]
  })
}

# Archive the Lambda function code
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/anomaly_processor.zip"
  
  source {
    content = templatefile("${path.module}/lambda_code.py", {
      sns_topic_arn = aws_sns_topic.anomaly_alerts.arn
    })
    filename = "lambda_function.py"
  }
}

# Lambda function for anomaly processing
resource "aws_lambda_function" "anomaly_processor" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "${local.name_prefix}-anomaly-processor-${local.name_suffix}"
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = "python3.11"
  timeout         = var.lambda_timeout_seconds
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      SNS_TOPIC_ARN           = aws_sns_topic.anomaly_alerts.arn
      ANOMALY_THRESHOLD       = var.anomaly_threshold_multiplier
      CLOUDWATCH_NAMESPACE    = "AnomalyDetection"
      LOG_LEVEL              = "INFO"
    }
  }

  # Enable X-Ray tracing for monitoring
  tracing_config {
    mode = "Active"
  }

  tags = merge(local.common_tags, {
    Name      = "${local.name_prefix}-anomaly-processor-${local.name_suffix}"
    Purpose   = "Anomaly processing and alerting"
    Component = "Compute"
  })

  depends_on = [
    aws_iam_role_policy.lambda_execution_policy,
    aws_cloudwatch_log_group.lambda_logs
  ]
}

# CloudWatch log group for Lambda function
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${local.name_prefix}-anomaly-processor-${local.name_suffix}"
  retention_in_days = var.cloudwatch_log_retention_days
  kms_key_id        = aws_kms_key.log_encryption_key.arn

  tags = merge(local.common_tags, {
    Name      = "/aws/lambda/${local.name_prefix}-anomaly-processor-${local.name_suffix}"
    Purpose   = "Lambda function logging"
    Component = "Logging"
  })
}

# ================================
# CloudWatch Monitoring and Alarms
# ================================

# CloudWatch metric alarm for anomaly detection
resource "aws_cloudwatch_metric_alarm" "anomaly_detection_alarm" {
  alarm_name          = "${local.name_prefix}-anomaly-detection-alarm-${local.name_suffix}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "AnomalyCount"
  namespace           = "AnomalyDetection"
  period              = "300"
  statistic           = "Sum"
  threshold           = "1"
  alarm_description   = "This metric monitors anomaly detection events"
  alarm_actions       = [aws_sns_topic.anomaly_alerts.arn]
  ok_actions          = [aws_sns_topic.anomaly_alerts.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    Source = "FlinkApp"
  }

  tags = merge(local.common_tags, {
    Name      = "${local.name_prefix}-anomaly-detection-alarm-${local.name_suffix}"
    Purpose   = "Anomaly detection monitoring"
    Component = "Monitoring"
  })
}

# CloudWatch dashboard for monitoring
resource "aws_cloudwatch_dashboard" "anomaly_detection_dashboard" {
  dashboard_name = "${local.name_prefix}-anomaly-detection-dashboard-${local.name_suffix}"

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
            ["AWS/Kinesis", "IncomingRecords", "StreamName", aws_kinesis_stream.transaction_stream.name],
            [".", "IncomingBytes", ".", "."],
            [".", "OutgoingRecords", ".", "."],
            [".", "OutgoingBytes", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          title   = "Kinesis Stream Metrics"
          period  = 300
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["AnomalyDetection", "AnomalyCount", "Source", "FlinkApp"]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          title   = "Anomaly Detection Count"
          period  = 300
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 12
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["AWS/Lambda", "Duration", "FunctionName", aws_lambda_function.anomaly_processor.function_name],
            [".", "Invocations", ".", "."],
            [".", "Errors", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          title   = "Lambda Function Metrics"
          period  = 300
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name      = "${local.name_prefix}-anomaly-detection-dashboard-${local.name_suffix}"
    Purpose   = "Monitoring dashboard"
    Component = "Monitoring"
  })
}

# ================================
# Lambda Function Code Template
# ================================

# Create the Lambda function code file
resource "local_file" "lambda_code" {
  content = templatefile("${path.module}/lambda_code_template.py", {
    sns_topic_arn = aws_sns_topic.anomaly_alerts.arn
  })
  filename = "${path.module}/lambda_code.py"
}

# Lambda function code template (embedded)
resource "local_file" "lambda_code_template" {
  content = <<-EOF
import json
import boto3
import os
from datetime import datetime
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(os.environ.get('LOG_LEVEL', 'INFO'))

def lambda_handler(event, context):
    """
    Process anomaly detection events and send notifications.
    
    This function receives anomaly events, enriches them with metadata,
    publishes metrics to CloudWatch, and sends notifications via SNS.
    """
    # Initialize AWS clients
    cloudwatch = boto3.client('cloudwatch')
    sns = boto3.client('sns')
    
    try:
        # Process each record in the event
        for record in event.get('Records', []):
            # Parse the anomaly data
            message_body = record.get('body', '{}')
            
            try:
                anomaly_data = json.loads(message_body)
            except json.JSONDecodeError:
                # Handle plain text messages
                anomaly_data = {'message': message_body}
            
            # Extract anomaly details
            user_id = anomaly_data.get('userId', 'unknown')
            amount = anomaly_data.get('amount', 0)
            threshold = anomaly_data.get('threshold', 0)
            timestamp = anomaly_data.get('timestamp', int(datetime.utcnow().timestamp() * 1000))
            
            # Determine anomaly severity
            severity = determine_severity(amount, threshold)
            
            # Create enriched notification message
            notification_message = create_notification_message(
                user_id, amount, threshold, severity, timestamp
            )
            
            # Send custom metric to CloudWatch
            try:
                cloudwatch.put_metric_data(
                    Namespace=os.environ.get('CLOUDWATCH_NAMESPACE', 'AnomalyDetection'),
                    MetricData=[
                        {
                            'MetricName': 'AnomalyCount',
                            'Value': 1,
                            'Unit': 'Count',
                            'Timestamp': datetime.utcnow(),
                            'Dimensions': [
                                {
                                    'Name': 'Severity',
                                    'Value': severity
                                },
                                {
                                    'Name': 'UserId',
                                    'Value': user_id
                                }
                            ]
                        },
                        {
                            'MetricName': 'AnomalyAmount',
                            'Value': float(amount),
                            'Unit': 'None',
                            'Timestamp': datetime.utcnow(),
                            'Dimensions': [
                                {
                                    'Name': 'Severity',
                                    'Value': severity
                                }
                            ]
                        }
                    ]
                )
                logger.info(f"CloudWatch metrics published for user {user_id}")
            except Exception as e:
                logger.error(f"Failed to publish CloudWatch metrics: {str(e)}")
            
            # Send notification via SNS
            try:
                sns.publish(
                    TopicArn=os.environ['SNS_TOPIC_ARN'],
                    Message=notification_message,
                    Subject=f'[{severity.upper()}] Transaction Anomaly Alert - User {user_id}',
                    MessageAttributes={
                        'severity': {
                            'DataType': 'String',
                            'StringValue': severity
                        },
                        'userId': {
                            'DataType': 'String',
                            'StringValue': user_id
                        },
                        'amount': {
                            'DataType': 'Number',
                            'StringValue': str(amount)
                        }
                    }
                )
                logger.info(f"SNS notification sent for anomaly: {user_id}")
            except Exception as e:
                logger.error(f"Failed to send SNS notification: {str(e)}")
                raise
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Anomalies processed successfully',
                'processedRecords': len(event.get('Records', []))
            })
        }
        
    except Exception as e:
        logger.error(f"Error processing anomaly event: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': 'Failed to process anomaly event',
                'details': str(e)
            })
        }

def determine_severity(amount, threshold):
    """Determine the severity level of the anomaly."""
    if amount > threshold * 5:
        return 'critical'
    elif amount > threshold * 3:
        return 'high'
    elif amount > threshold * 2:
        return 'medium'
    else:
        return 'low'

def create_notification_message(user_id, amount, threshold, severity, timestamp):
    """Create a formatted notification message."""
    formatted_time = datetime.fromtimestamp(timestamp / 1000).strftime('%Y-%m-%d %H:%M:%S UTC')
    
    message = f"""
🚨 ANOMALY DETECTED - {severity.upper()} SEVERITY

📊 Transaction Details:
   • User ID: {user_id}
   • Amount: ${amount:,.2f}
   • Threshold: ${threshold:,.2f}
   • Deviation: {((amount / threshold - 1) * 100):.1f}% above normal
   • Timestamp: {formatted_time}

⚠️  Recommended Actions:
   • Review transaction history for user {user_id}
   • Verify merchant and transaction details
   • Consider temporary account restrictions if severity is HIGH or CRITICAL
   • Monitor for additional anomalous activity

🔗 Investigation Links:
   • CloudWatch Dashboard: [View Metrics]
   • Transaction Logs: [View Details]
   • User Profile: [Review Account]

This alert was generated by the real-time anomaly detection system.
For questions or to modify alert settings, contact your security team.
"""
    return message.strip()
EOF
  filename = "${path.module}/lambda_code_template.py"
}