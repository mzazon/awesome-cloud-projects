# =============================================================================
# Automated Application Performance Monitoring with CloudWatch Application Signals and EventBridge
# 
# This Terraform configuration deploys:
# - CloudWatch Application Signals for performance monitoring
# - Lambda function for event processing
# - SNS topic for notifications
# - CloudWatch alarms for performance thresholds
# - EventBridge rules for event-driven automation
# - IAM roles and policies with least privilege
# - CloudWatch dashboard for visualization
# =============================================================================

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.2"
    }
  }
}

# Data sources for account and region information
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# =============================================================================
# Local values for consistent naming and configuration
# =============================================================================

locals {
  # Resource naming
  name_prefix = "${var.project_name}-${random_string.suffix.result}"
  
  # Common tags applied to all resources
  common_tags = merge(var.additional_tags, {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
    Recipe      = "automated-application-performance-monitoring"
  })
  
  # Application services to monitor
  application_services = var.application_services
  
  # Lambda function configuration
  lambda_timeout = 60
  lambda_memory  = 256
}

# =============================================================================
# SNS Topic for Performance Alerts
# =============================================================================

resource "aws_sns_topic" "performance_alerts" {
  name         = "${local.name_prefix}-performance-alerts"
  display_name = "Application Performance Alerts"

  # Enhanced message delivery policy with retry logic
  delivery_policy = jsonencode({
    http = {
      defaultHealthyRetryPolicy = {
        minDelayTarget     = 20
        maxDelayTarget     = 20
        numRetries         = 3
        numMaxDelayRetries = 0
        numMinDelayRetries = 0
        numNoDelayRetries  = 0
        backoffFunction    = "linear"
      }
      disableSubscriptionOverrides = false
    }
  })

  tags = local.common_tags
}

# SNS Topic Policy for EventBridge and Lambda access
resource "aws_sns_topic_policy" "performance_alerts_policy" {
  arn = aws_sns_topic.performance_alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowEventBridgePublish"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action   = "sns:Publish"
        Resource = aws_sns_topic.performance_alerts.arn
      },
      {
        Sid    = "AllowLambdaPublish"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.lambda_execution_role.arn
        }
        Action   = "sns:Publish"
        Resource = aws_sns_topic.performance_alerts.arn
      }
    ]
  })
}

# Email subscription to SNS topic
resource "aws_sns_topic_subscription" "email_notification" {
  count     = var.notification_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.performance_alerts.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# =============================================================================
# IAM Role and Policies for Lambda Function
# =============================================================================

# Lambda execution role
resource "aws_iam_role" "lambda_execution_role" {
  name = "${local.name_prefix}-lambda-execution-role"

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

  tags = local.common_tags
}

# Basic Lambda execution policy attachment
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.lambda_execution_role.name
}

# Custom policy for monitoring and automation capabilities
resource "aws_iam_role_policy" "lambda_monitoring_policy" {
  name = "${local.name_prefix}-lambda-monitoring-policy"
  role = aws_iam_role.lambda_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.performance_alerts.arn
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:DescribeAlarms",
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:ListMetrics"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "autoscaling:DescribeAutoScalingGroups",
          "autoscaling:UpdateAutoScalingGroup"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "application-signals:GetService",
          "application-signals:ListServices"
        ]
        Resource = "*"
      }
    ]
  })
}

# =============================================================================
# Lambda Function for Event Processing
# =============================================================================

# Create Lambda function code archive
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda_function.zip"
  source {
    content = templatefile("${path.module}/lambda_function.py", {
      sns_topic_arn = aws_sns_topic.performance_alerts.arn
    })
    filename = "lambda_function.py"
  }
}

# Lambda function resource
resource "aws_lambda_function" "performance_processor" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "${local.name_prefix}-performance-processor"
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  runtime         = "python3.11"
  timeout         = local.lambda_timeout
  memory_size     = local.lambda_memory

  environment {
    variables = {
      SNS_TOPIC_ARN     = aws_sns_topic.performance_alerts.arn
      PROJECT_NAME      = var.project_name
      ENVIRONMENT       = var.environment
      LOG_LEVEL         = var.lambda_log_level
    }
  }

  tags = local.common_tags

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy.lambda_monitoring_policy,
    aws_cloudwatch_log_group.lambda_logs
  ]
}

# CloudWatch log group for Lambda function
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${local.name_prefix}-performance-processor"
  retention_in_days = var.lambda_log_retention_days

  tags = local.common_tags
}

# =============================================================================
# CloudWatch Application Signals Configuration
# =============================================================================

# Application Signals log group for data collection
resource "aws_cloudwatch_log_group" "application_signals" {
  name              = "/aws/application-signals/data"
  retention_in_days = var.application_signals_log_retention_days

  tags = local.common_tags
}

# =============================================================================
# CloudWatch Alarms for Application Performance
# =============================================================================

# High latency alarm for each application service
resource "aws_cloudwatch_metric_alarm" "high_latency" {
  for_each = toset(local.application_services)

  alarm_name          = "${local.name_prefix}-${each.key}-high-latency"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.latency_evaluation_periods
  metric_name         = "Latency"
  namespace           = "AWS/ApplicationSignals"
  period              = var.alarm_period
  statistic           = "Average"
  threshold           = var.latency_threshold_ms
  alarm_description   = "This metric monitors average latency for ${each.key} service"
  alarm_unit          = "Milliseconds"

  dimensions = {
    Service = each.key
  }

  alarm_actions = [aws_sns_topic.performance_alerts.arn]
  ok_actions    = [aws_sns_topic.performance_alerts.arn]

  tags = merge(local.common_tags, {
    Service = each.key
    Type    = "Latency"
  })
}

# High error rate alarm for each application service
resource "aws_cloudwatch_metric_alarm" "high_error_rate" {
  for_each = toset(local.application_services)

  alarm_name          = "${local.name_prefix}-${each.key}-high-error-rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.error_rate_evaluation_periods
  metric_name         = "ErrorRate"
  namespace           = "AWS/ApplicationSignals"
  period              = var.alarm_period
  statistic           = "Average"
  threshold           = var.error_rate_threshold_percent
  alarm_description   = "This metric monitors error rate for ${each.key} service"
  alarm_unit          = "Percent"

  dimensions = {
    Service = each.key
  }

  alarm_actions = [aws_sns_topic.performance_alerts.arn]
  ok_actions    = [aws_sns_topic.performance_alerts.arn]

  tags = merge(local.common_tags, {
    Service = each.key
    Type    = "ErrorRate"
  })
}

# Low throughput alarm for each application service
resource "aws_cloudwatch_metric_alarm" "low_throughput" {
  for_each = toset(local.application_services)

  alarm_name          = "${local.name_prefix}-${each.key}-low-throughput"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = var.throughput_evaluation_periods
  metric_name         = "CallCount"
  namespace           = "AWS/ApplicationSignals"
  period              = var.alarm_period
  statistic           = "Sum"
  threshold           = var.throughput_threshold_requests
  alarm_description   = "This metric monitors request throughput for ${each.key} service"
  alarm_unit          = "Count"

  dimensions = {
    Service = each.key
  }

  alarm_actions = [aws_sns_topic.performance_alerts.arn]
  ok_actions    = [aws_sns_topic.performance_alerts.arn]

  tags = merge(local.common_tags, {
    Service = each.key
    Type    = "Throughput"
  })
}

# =============================================================================
# EventBridge Rules for Event-Driven Automation
# =============================================================================

# EventBridge rule for CloudWatch alarm state changes
resource "aws_cloudwatch_event_rule" "alarm_state_change" {
  name        = "${local.name_prefix}-alarm-state-change"
  description = "Route CloudWatch alarm state changes to Lambda processor"

  event_pattern = jsonencode({
    source      = ["aws.cloudwatch"]
    detail-type = ["CloudWatch Alarm State Change"]
    detail = {
      state = {
        value = ["ALARM", "OK"]
      }
    }
  })

  tags = local.common_tags
}

# EventBridge target - Lambda function
resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.alarm_state_change.name
  target_id = "PerformanceProcessorTarget"
  arn       = aws_lambda_function.performance_processor.arn
}

# Permission for EventBridge to invoke Lambda function
resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.performance_processor.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.alarm_state_change.arn
}

# =============================================================================
# CloudWatch Dashboard for Performance Monitoring
# =============================================================================

resource "aws_cloudwatch_dashboard" "performance_monitoring" {
  dashboard_name = "${local.name_prefix}-performance-monitoring"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6

        properties = {
          metrics = flatten([
            for service in local.application_services : [
              ["AWS/ApplicationSignals", "Latency", "Service", service],
              [".", "ErrorRate", ".", "."],
              [".", "CallCount", ".", "."]
            ]
          ])
          view      = "timeSeries"
          stacked   = false
          region    = data.aws_region.current.name
          title     = "Application Performance Metrics"
          period    = 300
          stat      = "Average"
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
            ["AWS/Events", "InvocationsCount", "RuleName", aws_cloudwatch_event_rule.alarm_state_change.name],
            ["AWS/Lambda", "Invocations", "FunctionName", aws_lambda_function.performance_processor.function_name],
            [".", "Duration", ".", "."],
            [".", "Errors", ".", "."]
          ]
          view      = "timeSeries"
          stacked   = false
          region    = data.aws_region.current.name
          title     = "Event Processing Metrics"
          period    = 300
          stat      = "Sum"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 24
        height = 6

        properties = {
          metrics = flatten([
            for service in local.application_services : [
              ["AWS/ApplicationSignals", "Latency", "Service", service, { "stat": "Maximum" }],
              [".", "Latency", ".", ".", { "stat": "Average" }],
              [".", "Latency", ".", ".", { "stat": "p95" }]
            ]
          ])
          view      = "timeSeries"
          stacked   = false
          region    = data.aws_region.current.name
          title     = "Latency Distribution (Max, Average, P95)"
          period    = 300
          yAxis = {
            left = {
              min = 0
            }
          }
        }
      }
    ]
  })

  tags = local.common_tags
}