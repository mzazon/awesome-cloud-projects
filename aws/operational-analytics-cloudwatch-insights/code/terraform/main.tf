# Main Terraform configuration for Operational Analytics with CloudWatch Insights
# This file creates all the necessary infrastructure for comprehensive log analytics

# Data sources for current AWS account and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}

# Local values for resource naming and configuration
locals {
  # Resource naming with random suffix
  resource_suffix = random_string.suffix.result
  log_group_name  = "/aws/lambda/${var.project_name}-demo-${local.resource_suffix}"
  
  # Dashboard name with fallback
  dashboard_name = var.dashboard_name != "" ? var.dashboard_name : "${var.project_name}-${local.resource_suffix}"
  
  # SNS topic name
  sns_topic_name = "${var.project_name}-alerts-${local.resource_suffix}"
  
  # Lambda function name
  lambda_function_name = "log-generator-${local.resource_suffix}"
  
  # IAM role name
  lambda_role_name = "LogGeneratorRole-${local.resource_suffix}"
  
  # Common tags
  common_tags = merge(var.tags, {
    Project     = var.project_name
    Environment = var.environment
  })
}

# ========================================
# CloudWatch Log Group for Analytics
# ========================================

resource "aws_cloudwatch_log_group" "operational_analytics" {
  name              = local.log_group_name
  retention_in_days = var.log_retention_days
  log_group_class   = "STANDARD"

  tags = merge(local.common_tags, {
    Name        = "OperationalAnalyticsLogGroup"
    Description = "Log group for operational analytics demonstration"
  })
}

# ========================================
# IAM Role and Policies for Lambda
# ========================================

# IAM role for Lambda function
resource "aws_iam_role" "lambda_role" {
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

  tags = merge(local.common_tags, {
    Name        = "LogGeneratorLambdaRole"
    Description = "IAM role for log generation Lambda function"
  })
}

# Attach basic execution role policy
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# ========================================
# Lambda Function for Log Generation
# ========================================

# Create Lambda deployment package
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/log-generator.zip"
  
  source {
    content = templatefile("${path.module}/lambda_function.py", {
      log_group_name = local.log_group_name
    })
    filename = "lambda_function.py"
  }
}

# Lambda function for generating sample log data
resource "aws_lambda_function" "log_generator" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = local.lambda_function_name
  role            = aws_iam_role.lambda_role.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = "python3.9"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      LOG_GROUP_NAME = local.log_group_name
      ENVIRONMENT    = var.environment
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_cloudwatch_log_group.operational_analytics
  ]

  tags = merge(local.common_tags, {
    Name        = "LogGeneratorFunction"
    Description = "Lambda function for generating operational log data"
  })
}

# ========================================
# SNS Topic for Alerts
# ========================================

# SNS topic for operational alerts
resource "aws_sns_topic" "operational_alerts" {
  name         = local.sns_topic_name
  display_name = "Operational Analytics Alerts"

  tags = merge(local.common_tags, {
    Name        = "OperationalAlertstopic"
    Description = "SNS topic for operational analytics alerts"
  })
}

# SNS topic policy for CloudWatch alarms
resource "aws_sns_topic_policy" "operational_alerts_policy" {
  arn = aws_sns_topic.operational_alerts.arn

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
        Resource = aws_sns_topic.operational_alerts.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

# Optional email subscription for alerts
resource "aws_sns_topic_subscription" "email_alerts" {
  count     = var.notification_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.operational_alerts.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# ========================================
# CloudWatch Metric Filters
# ========================================

# Metric filter for error rate monitoring
resource "aws_cloudwatch_log_metric_filter" "error_rate" {
  name           = "ErrorRateFilter"
  log_group_name = aws_cloudwatch_log_group.operational_analytics.name
  pattern        = "[timestamp, requestId, level=\"ERROR\", ...]"

  metric_transformation {
    name          = "ErrorRate"
    namespace     = "OperationalAnalytics"
    value         = "1"
    default_value = "0"
  }
}

# Metric filter for log volume monitoring
resource "aws_cloudwatch_log_metric_filter" "log_volume" {
  name           = "LogVolumeFilter"
  log_group_name = aws_cloudwatch_log_group.operational_analytics.name
  pattern        = ""

  metric_transformation {
    name          = "LogVolume"
    namespace     = "OperationalAnalytics"
    value         = "1"
    default_value = "0"
  }
}

# ========================================
# CloudWatch Alarms
# ========================================

# Alarm for high error rate
resource "aws_cloudwatch_metric_alarm" "high_error_rate" {
  alarm_name          = "HighErrorRate-${local.resource_suffix}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "ErrorRate"
  namespace           = "OperationalAnalytics"
  period              = "300"
  statistic           = "Sum"
  threshold           = var.error_rate_threshold
  alarm_description   = "Alert when error rate exceeds threshold"
  alarm_actions       = [aws_sns_topic.operational_alerts.arn]
  ok_actions          = [aws_sns_topic.operational_alerts.arn]
  treat_missing_data  = "notBreaching"

  tags = merge(local.common_tags, {
    Name        = "HighErrorRateAlarm"
    Description = "CloudWatch alarm for monitoring error rate"
  })
}

# Alarm for high log volume (cost monitoring)
resource "aws_cloudwatch_metric_alarm" "high_log_volume" {
  alarm_name          = "HighLogVolume-${local.resource_suffix}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "LogVolume"
  namespace           = "OperationalAnalytics"
  period              = "3600"
  statistic           = "Sum"
  threshold           = var.log_volume_threshold
  alarm_description   = "Alert when log volume exceeds budget threshold"
  alarm_actions       = [aws_sns_topic.operational_alerts.arn]
  treat_missing_data  = "notBreaching"

  tags = merge(local.common_tags, {
    Name        = "HighLogVolumeAlarm"
    Description = "CloudWatch alarm for monitoring log volume costs"
  })
}

# ========================================
# CloudWatch Anomaly Detection
# ========================================

# Anomaly detector for log ingestion patterns
resource "aws_cloudwatch_anomaly_detector" "log_ingestion" {
  count       = var.enable_anomaly_detection ? 1 : 0
  namespace   = "AWS/Logs"
  metric_name = "IncomingBytes"
  stat        = "Average"

  dimensions = {
    LogGroupName = aws_cloudwatch_log_group.operational_analytics.name
  }

  tags = merge(local.common_tags, {
    Name        = "LogIngestionAnomalyDetector"
    Description = "Anomaly detector for log ingestion patterns"
  })
}

# Anomaly alarm for log ingestion
resource "aws_cloudwatch_metric_alarm" "log_ingestion_anomaly" {
  count                     = var.enable_anomaly_detection ? 1 : 0
  alarm_name                = "LogIngestionAnomaly-${local.resource_suffix}"
  comparison_operator       = "LessThanLowerOrGreaterThanUpperThreshold"
  evaluation_periods        = var.alarm_evaluation_periods
  threshold_metric_id       = "e1"
  alarm_description         = "Detect anomalies in log ingestion patterns"
  alarm_actions            = [aws_sns_topic.operational_alerts.arn]
  ok_actions               = [aws_sns_topic.operational_alerts.arn]
  insufficient_data_actions = []
  treat_missing_data       = "breaching"

  metric_query {
    id = "e1"
    expression = "ANOMALY_DETECTION_FUNCTION(m1, ${var.anomaly_detection_threshold})"
    label      = "Log Ingestion (expected)"
    return_data = "true"
  }

  metric_query {
    id = "m1"
    return_data = "true"
    metric {
      metric_name = "IncomingBytes"
      namespace   = "AWS/Logs"
      period      = "300"
      stat        = "Average"

      dimensions = {
        LogGroupName = aws_cloudwatch_log_group.operational_analytics.name
      }
    }
  }

  tags = merge(local.common_tags, {
    Name        = "LogIngestionAnomalyAlarm"
    Description = "CloudWatch alarm for log ingestion anomaly detection"
  })
}

# ========================================
# CloudWatch Dashboard
# ========================================

# CloudWatch dashboard for operational analytics
resource "aws_cloudwatch_dashboard" "operational_analytics" {
  dashboard_name = local.dashboard_name

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "log"
        x      = 0
        y      = 0
        width  = 12
        height = 6

        properties = {
          title = "Error Analysis"
          query = "SOURCE '${local.log_group_name}' | fields @timestamp, @message\n| filter @message like /ERROR/\n| stats count() as error_count by bin(5m)\n| sort @timestamp desc\n| limit 50"
          region = data.aws_region.current.name
          view   = "table"
          stacked = false
        }
      },
      {
        type   = "log"
        x      = 12
        y      = 0
        width  = 12
        height = 6

        properties = {
          title = "Performance Metrics"
          query = "SOURCE '${local.log_group_name}' | fields @timestamp, @message\n| filter @message like /response_time/\n| parse @message '\"response_time\": *' as response_time\n| stats avg(response_time) as avg_response_time, max(response_time) as max_response_time by bin(1m)\n| sort @timestamp desc"
          region = data.aws_region.current.name
          view   = "table"
          stacked = false
        }
      },
      {
        type   = "log"
        x      = 0
        y      = 6
        width  = 24
        height = 6

        properties = {
          title = "Top Active Users"
          query = "SOURCE '${local.log_group_name}' | fields @timestamp, @message\n| filter @message like /user_id/\n| parse @message '\"user_id\": \"*\"' as user_id\n| stats count() as activity_count by user_id\n| sort activity_count desc\n| limit 20"
          region = data.aws_region.current.name
          view   = "table"
          stacked = false
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 12
        width  = 12
        height = 6

        properties = {
          title   = "Error Rate Trend"
          view    = "timeSeries"
          stacked = false
          metrics = [
            ["OperationalAnalytics", "ErrorRate", { "stat": "Sum" }]
          ]
          period = 300
          region = data.aws_region.current.name
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
        y      = 12
        width  = 12
        height = 6

        properties = {
          title   = "Log Volume Monitoring"
          view    = "timeSeries"
          stacked = false
          metrics = [
            ["OperationalAnalytics", "LogVolume", { "stat": "Sum" }]
          ]
          period = 3600
          region = data.aws_region.current.name
          yAxis = {
            left = {
              min = 0
            }
          }
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name        = "OperationalAnalyticsDashboard"
    Description = "CloudWatch dashboard for operational analytics insights"
  })
}