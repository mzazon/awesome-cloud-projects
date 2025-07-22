# AWS Sustainability Intelligence Dashboard Infrastructure
# Comprehensive Terraform configuration for carbon footprint analytics and cost optimization

# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Data source for current AWS account information
data "aws_caller_identity" "current" {}

# Data source for current AWS region
data "aws_region" "current" {}

# Data source for AWS partition (aws, aws-gov, aws-cn)
data "aws_partition" "current" {}

# ============================================================================
# KMS KEY FOR ENCRYPTION
# ============================================================================

# KMS key for encrypting sensitive sustainability data
resource "aws_kms_key" "sustainability_key" {
  description             = "KMS key for sustainability analytics encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = var.kms_key_rotation

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow Lambda and S3 service access"
        Effect = "Allow"
        Principal = {
          Service = [
            "lambda.amazonaws.com",
            "s3.amazonaws.com",
            "logs.amazonaws.com"
          ]
        }
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey",
          "kms:Encrypt",
          "kms:GenerateDataKey",
          "kms:ReEncrypt*"
        ]
        Resource = "*"
      }
    ]
  })

  tags = merge(var.resource_tags, {
    Name        = "${var.project_name}-kms-key-${random_string.suffix.result}"
    Purpose     = "Sustainability analytics data encryption"
    Component   = "Security"
  })
}

# KMS key alias for easier management
resource "aws_kms_alias" "sustainability_key_alias" {
  name          = "alias/${var.project_name}-sustainability-${random_string.suffix.result}"
  target_key_id = aws_kms_key.sustainability_key.key_id
}

# ============================================================================
# S3 DATA LAKE FOR SUSTAINABILITY ANALYTICS
# ============================================================================

# S3 bucket for sustainability data lake
resource "aws_s3_bucket" "sustainability_data_lake" {
  bucket = var.data_lake_bucket_name != "" ? var.data_lake_bucket_name : "${var.project_name}-data-lake-${random_string.suffix.result}"

  tags = merge(var.resource_tags, {
    Name        = "${var.project_name}-data-lake-${random_string.suffix.result}"
    Purpose     = "Sustainability analytics data storage"
    Component   = "DataLake"
    DataType    = "Carbon footprint and cost data"
  })
}

# S3 bucket versioning for data governance
resource "aws_s3_bucket_versioning" "sustainability_data_lake_versioning" {
  bucket = aws_s3_bucket.sustainability_data_lake.id
  versioning_configuration {
    status     = var.enable_versioning ? "Enabled" : "Disabled"
    mfa_delete = var.enable_mfa_delete && var.enable_versioning ? "Enabled" : "Disabled"
  }
}

# S3 bucket encryption with KMS
resource "aws_s3_bucket_server_side_encryption_configuration" "sustainability_data_lake_encryption" {
  bucket = aws_s3_bucket.sustainability_data_lake.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.sustainability_key.arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

# S3 bucket public access block for security
resource "aws_s3_bucket_public_access_block" "sustainability_data_lake_pab" {
  bucket = aws_s3_bucket.sustainability_data_lake.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket lifecycle configuration for cost optimization
resource "aws_s3_bucket_lifecycle_configuration" "sustainability_data_lake_lifecycle" {
  bucket = aws_s3_bucket.sustainability_data_lake.id

  rule {
    id     = "sustainability_data_lifecycle"
    status = "Enabled"

    # Transition to Infrequent Access after specified days
    transition {
      days          = var.s3_lifecycle_transition_days
      storage_class = "STANDARD_IA"
    }

    # Transition to Glacier Flexible Retrieval after 90 days
    transition {
      days          = max(90, var.s3_lifecycle_transition_days + 60)
      storage_class = "GLACIER"
    }

    # Transition to Glacier Deep Archive after 365 days
    transition {
      days          = max(365, var.s3_lifecycle_transition_days + 335)
      storage_class = "DEEP_ARCHIVE"
    }

    # Optional expiration for compliance
    dynamic "expiration" {
      for_each = var.s3_lifecycle_expiration_days > 0 ? [1] : []
      content {
        days = var.s3_lifecycle_expiration_days
      }
    }

    # Clean up incomplete multipart uploads
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }

    # Clean up non-current versions
    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

# S3 bucket notification for data processing automation
resource "aws_s3_bucket_notification" "sustainability_data_lake_notification" {
  bucket = aws_s3_bucket.sustainability_data_lake.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.sustainability_data_processor.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "raw-data/"
    filter_suffix       = ".json"
  }

  depends_on = [aws_lambda_permission.allow_s3_invoke]
}

# ============================================================================
# IAM ROLES AND POLICIES FOR LAMBDA EXECUTION
# ============================================================================

# Lambda execution role for sustainability data processing
resource "aws_iam_role" "lambda_execution_role" {
  name = "${var.project_name}-lambda-role-${random_string.suffix.result}"

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

  tags = merge(var.resource_tags, {
    Name      = "${var.project_name}-lambda-role-${random_string.suffix.result}"
    Purpose   = "Lambda execution role for sustainability analytics"
    Component = "IAM"
  })
}

# Custom policy for sustainability analytics access
resource "aws_iam_policy" "sustainability_analytics_policy" {
  name        = "${var.project_name}-analytics-policy-${random_string.suffix.result}"
  description = "Policy for accessing sustainability and cost data"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CostExplorerAccess"
        Effect = "Allow"
        Action = [
          "ce:GetCostAndUsage",
          "ce:GetUsageForecast",
          "ce:GetCostCategories",
          "ce:GetDimensionValues",
          "ce:GetReservationCoverage",
          "ce:GetReservationPurchaseRecommendation",
          "ce:GetReservationUtilization",
          "ce:GetRightsizingRecommendation",
          "ce:GetSavingsPlansUtilization",
          "ce:GetSavingsPlansUtilizationDetails",
          "cur:DescribeReportDefinitions",
          "cur:GetClassicReport"
        ]
        Resource = "*"
      },
      {
        Sid    = "SustainabilityDataAccess"
        Effect = "Allow"
        Action = [
          "sustainability:GetCarbonFootprintSummary",
          "bcm-data-exports:*",
          "billing:GetBillingData"
        ]
        Resource = "*"
      },
      {
        Sid    = "S3DataLakeAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetObjectVersion",
          "s3:PutObjectAcl"
        ]
        Resource = [
          aws_s3_bucket.sustainability_data_lake.arn,
          "${aws_s3_bucket.sustainability_data_lake.arn}/*"
        ]
      },
      {
        Sid    = "CloudWatchMetricsAccess"
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData",
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:ListMetrics"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "cloudwatch:namespace" = ["SustainabilityAnalytics", "AWS/Lambda"]
          }
        }
      },
      {
        Sid    = "KMSAccess"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey",
          "kms:Encrypt",
          "kms:GenerateDataKey",
          "kms:ReEncrypt*"
        ]
        Resource = aws_kms_key.sustainability_key.arn
      },
      {
        Sid    = "QuickSightAccess"
        Effect = "Allow"
        Action = [
          "quicksight:CreateDataSet",
          "quicksight:UpdateDataSet",
          "quicksight:DescribeDataSet",
          "quicksight:CreateDashboard",
          "quicksight:UpdateDashboard",
          "quicksight:DescribeDashboard"
        ]
        Resource = "*"
      }
    ]
  })

  tags = merge(var.resource_tags, {
    Name      = "${var.project_name}-analytics-policy-${random_string.suffix.result}"
    Purpose   = "Sustainability analytics access policy"
    Component = "IAM"
  })
}

# Attach AWS managed policy for basic Lambda execution
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Attach custom sustainability analytics policy
resource "aws_iam_role_policy_attachment" "lambda_sustainability_policy" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = aws_iam_policy.sustainability_analytics_policy.arn
}

# Attach X-Ray tracing policy if enabled
resource "aws_iam_role_policy_attachment" "lambda_xray_policy" {
  count      = var.enable_xray_tracing ? 1 : 0
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

# ============================================================================
# CLOUDWATCH LOG GROUPS FOR MONITORING
# ============================================================================

# CloudWatch log group for Lambda function
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${local.lambda_function_name}"
  retention_in_days = var.cloudwatch_log_retention_days
  kms_key_id        = aws_kms_key.sustainability_key.arn

  tags = merge(var.resource_tags, {
    Name      = "${var.project_name}-lambda-logs-${random_string.suffix.result}"
    Purpose   = "Lambda function logs for sustainability analytics"
    Component = "Monitoring"
  })
}

# ============================================================================
# LAMBDA FUNCTION FOR DATA PROCESSING
# ============================================================================

# Local values for consistent naming
locals {
  lambda_function_name = var.lambda_function_name != "" ? var.lambda_function_name : "${var.project_name}-processor-${random_string.suffix.result}"
}

# Archive Lambda function code
data "archive_file" "lambda_code" {
  type        = "zip"
  output_path = "${path.module}/sustainability_processor.zip"
  
  source {
    content = templatefile("${path.module}/lambda_function.py.tpl", {
      bucket_name = aws_s3_bucket.sustainability_data_lake.bucket
      kms_key_id  = aws_kms_key.sustainability_key.arn
      region      = data.aws_region.current.name
    })
    filename = "sustainability_processor.py"
  }
  
  source {
    content  = file("${path.module}/requirements.txt")
    filename = "requirements.txt"
  }
}

# Lambda function for sustainability data processing
resource "aws_lambda_function" "sustainability_data_processor" {
  filename         = data.archive_file.lambda_code.output_path
  function_name    = local.lambda_function_name
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "sustainability_processor.lambda_handler"
  runtime         = var.lambda_runtime
  architectures   = [var.lambda_architecture]
  memory_size     = var.lambda_memory_size
  timeout         = var.lambda_timeout
  source_code_hash = data.archive_file.lambda_code.output_base64sha256

  environment {
    variables = {
      BUCKET_NAME              = aws_s3_bucket.sustainability_data_lake.bucket
      KMS_KEY_ID              = aws_kms_key.sustainability_key.arn
      COST_EXPLORER_REGION    = "us-east-1"
      ENVIRONMENT             = var.environment
      LOG_LEVEL               = "INFO"
      ENABLE_XRAY            = var.enable_xray_tracing
    }
  }

  # Enable X-Ray tracing if configured
  dynamic "tracing_config" {
    for_each = var.enable_xray_tracing ? [1] : []
    content {
      mode = "Active"
    }
  }

  # Enhanced logging configuration
  logging_config {
    log_format            = "JSON"
    application_log_level = "INFO"
    system_log_level      = "WARN"
  }

  # Dead letter queue for failed invocations
  dead_letter_config {
    target_arn = aws_sqs_queue.lambda_dlq.arn
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy_attachment.lambda_sustainability_policy,
    aws_cloudwatch_log_group.lambda_logs
  ]

  tags = merge(var.resource_tags, {
    Name        = local.lambda_function_name
    Purpose     = "Process sustainability and cost data for analytics"
    Component   = "DataProcessing"
    Runtime     = var.lambda_runtime
    Architecture = var.lambda_architecture
  })
}

# ============================================================================
# SQS DEAD LETTER QUEUE FOR ERROR HANDLING
# ============================================================================

# Dead letter queue for Lambda failures
resource "aws_sqs_queue" "lambda_dlq" {
  name                      = "${var.project_name}-dlq-${random_string.suffix.result}"
  message_retention_seconds = 1209600  # 14 days
  
  # Enable SQS encryption with KMS
  kms_master_key_id                 = aws_kms_key.sustainability_key.arn
  kms_data_key_reuse_period_seconds = 300

  tags = merge(var.resource_tags, {
    Name      = "${var.project_name}-dlq-${random_string.suffix.result}"
    Purpose   = "Dead letter queue for failed Lambda invocations"
    Component = "ErrorHandling"
  })
}

# ============================================================================
# EVENTBRIDGE FOR AUTOMATED SCHEDULING
# ============================================================================

# EventBridge rule for scheduled data processing
resource "aws_cloudwatch_event_rule" "sustainability_data_processing" {
  name                = "${var.project_name}-scheduler-${random_string.suffix.result}"
  description         = "Scheduled sustainability data collection and processing"
  schedule_expression = var.data_processing_schedule
  state               = "ENABLED"

  tags = merge(var.resource_tags, {
    Name      = "${var.project_name}-scheduler-${random_string.suffix.result}"
    Purpose   = "Automated sustainability data processing"
    Component = "Automation"
  })
}

# EventBridge target for Lambda function
resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.sustainability_data_processing.name
  target_id = "SustainabilityProcessorTarget"
  arn       = aws_lambda_function.sustainability_data_processor.arn

  input = jsonencode({
    source        = "eventbridge-scheduler"
    detail_type   = "Scheduled Carbon Data Processing"
    environment   = var.environment
    trigger_time  = timestamp()
  })
}

# Lambda permission for EventBridge invocation
resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.sustainability_data_processor.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.sustainability_data_processing.arn
}

# Lambda permission for S3 bucket notification
resource "aws_lambda_permission" "allow_s3_invoke" {
  statement_id  = "AllowExecutionFromS3"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.sustainability_data_processor.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.sustainability_data_lake.arn
}

# ============================================================================
# SNS TOPIC FOR NOTIFICATIONS
# ============================================================================

# SNS topic for sustainability alerts
resource "aws_sns_topic" "sustainability_alerts" {
  name              = "${var.project_name}-alerts-${random_string.suffix.result}"
  display_name      = "Sustainability Analytics Alerts"
  kms_master_key_id = aws_kms_key.sustainability_key.arn

  tags = merge(var.resource_tags, {
    Name      = "${var.project_name}-alerts-${random_string.suffix.result}"
    Purpose   = "Sustainability analytics notifications"
    Component = "Notifications"
  })
}

# SNS topic policy for CloudWatch alarms
resource "aws_sns_topic_policy" "sustainability_alerts_policy" {
  arn = aws_sns_topic.sustainability_alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudWatchAlarmsToPublish"
        Effect = "Allow"
        Principal = {
          Service = "cloudwatch.amazonaws.com"
        }
        Action   = "sns:Publish"
        Resource = aws_sns_topic.sustainability_alerts.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

# Optional email subscription for notifications
resource "aws_sns_topic_subscription" "email_notification" {
  count     = var.notification_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.sustainability_alerts.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# ============================================================================
# CLOUDWATCH ALARMS FOR MONITORING
# ============================================================================

# Alarm for Lambda function errors
resource "aws_cloudwatch_metric_alarm" "lambda_error_alarm" {
  alarm_name          = "${var.project_name}-lambda-errors-${random_string.suffix.result}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Lambda function sustainability data processor errors"
  alarm_actions       = [aws_sns_topic.sustainability_alerts.arn]
  ok_actions          = [aws_sns_topic.sustainability_alerts.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.sustainability_data_processor.function_name
  }

  tags = merge(var.resource_tags, {
    Name      = "${var.project_name}-lambda-errors-${random_string.suffix.result}"
    Purpose   = "Monitor Lambda function errors"
    Component = "Monitoring"
  })
}

# Alarm for Lambda function duration
resource "aws_cloudwatch_metric_alarm" "lambda_duration_alarm" {
  alarm_name          = "${var.project_name}-lambda-duration-${random_string.suffix.result}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Average"
  threshold           = var.lambda_timeout * 1000 * 0.8  # Alert at 80% of timeout
  alarm_description   = "Lambda function execution duration approaching timeout"
  alarm_actions       = [aws_sns_topic.sustainability_alerts.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.sustainability_data_processor.function_name
  }

  tags = merge(var.resource_tags, {
    Name      = "${var.project_name}-lambda-duration-${random_string.suffix.result}"
    Purpose   = "Monitor Lambda function duration"
    Component = "Monitoring"
  })
}

# Custom alarm for data processing success
resource "aws_cloudwatch_metric_alarm" "data_processing_success_alarm" {
  count               = var.enable_enhanced_monitoring ? 1 : 0
  alarm_name          = "${var.project_name}-processing-success-${random_string.suffix.result}"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "DataProcessingSuccess"
  namespace           = "SustainabilityAnalytics"
  period              = 86400  # Daily check
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "Daily sustainability data processing success check"
  alarm_actions       = [aws_sns_topic.sustainability_alerts.arn]
  treat_missing_data  = "breaching"

  tags = merge(var.resource_tags, {
    Name      = "${var.project_name}-processing-success-${random_string.suffix.result}"
    Purpose   = "Monitor daily data processing success"
    Component = "Monitoring"
  })
}

# ============================================================================
# QUICKSIGHT RESOURCES (BASIC CONFIGURATION)
# ============================================================================

# QuickSight data source for S3
resource "aws_quicksight_data_source" "sustainability_data_source" {
  data_source_id = "${var.project_name}-datasource-${random_string.suffix.result}"
  name           = "Sustainability Analytics Data Source"
  
  parameters {
    s3 {
      manifest_file_location {
        bucket = aws_s3_bucket.sustainability_data_lake.bucket
        key    = "manifests/sustainability-manifest.json"
      }
    }
  }
  
  type = "S3"

  # Conditional permissions based on provided user ARNs
  dynamic "permission" {
    for_each = var.quicksight_user_arns
    content {
      actions = [
        "quicksight:DescribeDataSource",
        "quicksight:DescribeDataSourcePermissions",
        "quicksight:PassDataSource"
      ]
      principal = permission.value
    }
  }

  tags = merge(var.resource_tags, {
    Name      = "${var.project_name}-datasource-${random_string.suffix.result}"
    Purpose   = "QuickSight data source for sustainability analytics"
    Component = "BusinessIntelligence"
  })
}

# ============================================================================
# ADDITIONAL RESOURCES FOR COMPLETENESS
# ============================================================================

# S3 object for QuickSight manifest file
resource "aws_s3_object" "quicksight_manifest" {
  bucket       = aws_s3_bucket.sustainability_data_lake.bucket
  key          = "manifests/sustainability-manifest.json"
  content_type = "application/json"
  kms_key_id   = aws_kms_key.sustainability_key.arn

  content = jsonencode({
    fileLocations = [
      {
        URIPrefixes = [
          "s3://${aws_s3_bucket.sustainability_data_lake.bucket}/sustainability-analytics/"
        ]
      }
    ]
    globalUploadSettings = {
      format          = "JSON"
      delimiter       = ","
      textqualifier   = "\""
      containsHeader  = "true"
    }
  })

  tags = merge(var.resource_tags, {
    Name      = "quicksight-manifest"
    Purpose   = "QuickSight data discovery manifest"
    Component = "BusinessIntelligence"
  })
}

# CloudWatch dashboard for operational metrics
resource "aws_cloudwatch_dashboard" "sustainability_dashboard" {
  dashboard_name = "${var.project_name}-ops-dashboard-${random_string.suffix.result}"

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
            ["AWS/Lambda", "Duration", "FunctionName", aws_lambda_function.sustainability_data_processor.function_name],
            [".", "Errors", ".", "."],
            [".", "Invocations", ".", "."],
            [".", "Throttles", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "Lambda Function Metrics"
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
            ["SustainabilityAnalytics", "DataProcessingSuccess"],
            [".", "DataProcessingError"]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "Data Processing Metrics"
          period  = 3600
        }
      }
    ]
  })
}