# =============================================================================
# Email Reports Infrastructure - Main Configuration
# =============================================================================
# This configuration creates a serverless email reporting system using:
# - AWS App Runner for containerized Flask application
# - Amazon SES for email delivery
# - EventBridge Scheduler for automated scheduling
# - CloudWatch for monitoring and alerting

# -----------------------------------------------------------------------------
# Data Sources
# -----------------------------------------------------------------------------

# Get current AWS account ID
data "aws_caller_identity" "current" {}

# Get current AWS region
data "aws_region" "current" {}

# -----------------------------------------------------------------------------
# Random Resources
# -----------------------------------------------------------------------------

# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# -----------------------------------------------------------------------------
# IAM Resources for App Runner Service
# -----------------------------------------------------------------------------

# IAM role for App Runner service to access SES and CloudWatch
resource "aws_iam_role" "app_runner_role" {
  name = "AppRunnerEmailReportsRole-${random_string.suffix.result}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "tasks.apprunner.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(var.common_tags, {
    Name    = "AppRunnerEmailReportsRole-${random_string.suffix.result}"
    Purpose = "Email Reports System"
  })
}

# IAM policy for App Runner to send emails and publish metrics
resource "aws_iam_role_policy" "app_runner_policy" {
  name = "EmailReportsPolicy"
  role = aws_iam_role.app_runner_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ses:SendEmail",
          "ses:SendRawEmail"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# IAM Resources for EventBridge Scheduler
# -----------------------------------------------------------------------------

# IAM role for EventBridge Scheduler to invoke App Runner service
resource "aws_iam_role" "scheduler_role" {
  name = "EventBridgeSchedulerRole-${random_string.suffix.result}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "scheduler.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(var.common_tags, {
    Name    = "EventBridgeSchedulerRole-${random_string.suffix.result}"
    Purpose = "Email Reports Scheduling"
  })
}

# IAM policy for EventBridge Scheduler HTTP invocation
resource "aws_iam_role_policy" "scheduler_policy" {
  name = "SchedulerHttpPolicy"
  role = aws_iam_role.scheduler_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "events:InvokeFunction"
        ]
        Resource = "*"
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# Amazon SES Configuration
# -----------------------------------------------------------------------------

# Verify email identity for sending emails
# Note: Manual verification via email confirmation is required after creation
resource "aws_ses_email_identity" "sender_identity" {
  email = var.ses_verified_email

  tags = merge(var.common_tags, {
    Name    = "EmailReportsSender"
    Purpose = "Email Reports System"
  })
}

# -----------------------------------------------------------------------------
# App Runner Service
# -----------------------------------------------------------------------------

# App Runner service for hosting the Flask email reporting application
resource "aws_apprunner_service" "email_reports_service" {
  service_name = "email-reports-service-${random_string.suffix.result}"

  # Source configuration pointing to GitHub repository
  source_configuration {
    # Repository configuration with GitHub connection
    code_repository {
      repository_url = var.github_repository_url
      
      source_code_version {
        type  = var.source_code_version_type
        value = var.source_code_version_value
      }
      
      # Use apprunner.yaml from repository for build/run configuration
      code_configuration {
        configuration_source = "REPOSITORY"
      }
    }
    
    # Enable automatic deployments on code changes
    auto_deployments_enabled = var.enable_auto_deployments
  }

  # Instance configuration for compute resources and environment
  instance_configuration {
    cpu               = var.app_runner_cpu
    memory            = var.app_runner_memory
    instance_role_arn = aws_iam_role.app_runner_role.arn

    # Environment variables for the application
    environment_variables = {
      SES_VERIFIED_EMAIL = var.ses_verified_email
    }
  }

  # Health check configuration for service monitoring
  health_check_configuration {
    protocol            = "HTTP"
    path                = var.health_check_path
    interval            = var.health_check_interval
    timeout             = var.health_check_timeout
    healthy_threshold   = 1
    unhealthy_threshold = 5
  }

  tags = merge(var.common_tags, {
    Name    = "email-reports-service-${random_string.suffix.result}"
    Purpose = "Email Reports System"
  })

  # Ensure IAM role is created before the service
  depends_on = [
    aws_iam_role_policy.app_runner_policy
  ]
}

# -----------------------------------------------------------------------------
# EventBridge Scheduler
# -----------------------------------------------------------------------------

# EventBridge Schedule for automated daily report generation
resource "aws_scheduler_schedule" "daily_report_schedule" {
  name        = "daily-report-schedule-${random_string.suffix.result}"
  description = "Daily email report generation"
  state       = "ENABLED"

  # Schedule configuration from variables
  schedule_expression          = var.schedule_expression
  schedule_expression_timezone = var.schedule_timezone

  # Flexible time window configuration
  flexible_time_window {
    mode = "OFF"
  }

  # Target configuration for HTTP invocation
  target {
    arn      = "arn:aws:scheduler:::http-invoke"
    role_arn = aws_iam_role.scheduler_role.arn

    # HTTP parameters for App Runner service endpoint
    http_parameters {
      http_method = "POST"
      url         = "https://${aws_apprunner_service.email_reports_service.service_url}/generate-report"
      
      header_parameters = {
        "Content-Type" = "application/json"
      }
    }

    # Retry configuration for failed invocations
    retry_policy {
      maximum_retry_attempts = var.scheduler_retry_attempts
      maximum_event_age      = var.scheduler_max_event_age
    }
  }

  # Ensure App Runner service is available before creating schedule
  depends_on = [
    aws_apprunner_service.email_reports_service,
    aws_iam_role_policy.scheduler_policy
  ]
}

# -----------------------------------------------------------------------------
# CloudWatch Monitoring
# -----------------------------------------------------------------------------

# CloudWatch alarm for monitoring report generation failures
resource "aws_cloudwatch_metric_alarm" "report_generation_failures" {
  count = var.enable_cloudwatch_alarms ? 1 : 0

  alarm_name        = "EmailReports-GenerationFailures-${random_string.suffix.result}"
  alarm_description = "Alert when email report generation fails"
  
  # Metric configuration
  metric_name = "ReportsGenerated"
  namespace   = "EmailReports"
  statistic   = "Sum"
  period      = var.cloudwatch_alarm_period
  
  # Alarm thresholds
  threshold           = var.cloudwatch_alarm_threshold
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  treat_missing_data  = "notBreaching"

  tags = merge(var.common_tags, {
    Name    = "EmailReports-GenerationFailures"
    Purpose = "Email Reports Monitoring"
  })
}

# CloudWatch dashboard for monitoring email reports system
resource "aws_cloudwatch_dashboard" "email_reports_dashboard" {
  count = var.enable_cloudwatch_dashboard ? 1 : 0

  dashboard_name = "EmailReports-Dashboard-${random_string.suffix.result}"

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
            ["EmailReports", "ReportsGenerated"]
          ]
          period = 300
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "Email Reports Generated"
          yAxis = {
            left = {
              min = 0
            }
          }
        }
      },
      {
        type   = "log"
        x      = 0
        y      = 6
        width  = 12
        height = 6

        properties = {
          query = "SOURCE '/aws/apprunner/${aws_apprunner_service.email_reports_service.service_name}' | fields @timestamp, @message | filter @message like /Report sent successfully/ | sort @timestamp desc | limit 20"
          region = data.aws_region.current.name
          title  = "Recent Report Generation Success"
          view   = "table"
        }
      }
    ]
  })
}