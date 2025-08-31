# main.tf
# Security Compliance Auditing with VPC Lattice and GuardDuty
# Infrastructure as Code using Terraform

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
      version = "~> 2.4"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "security-compliance-auditing"
      Environment = var.environment
      ManagedBy   = "terraform"
      Recipe      = "security-compliance-auditing-lattice-guardduty"
    }
  }
}

# Get current AWS caller identity for account ID
data "aws_caller_identity" "current" {}

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for resource naming
locals {
  random_suffix                = lower(random_id.suffix.hex)
  bucket_name                 = "${var.bucket_prefix}-${local.random_suffix}"
  lambda_function_name        = var.lambda_function_name
  sns_topic_name             = "${var.sns_topic_prefix}-${local.random_suffix}"
  log_group_name             = var.log_group_name
  cloudwatch_dashboard_name  = var.cloudwatch_dashboard_name
  vpc_lattice_service_network_name = "${var.vpc_lattice_service_network_prefix}-${local.random_suffix}"

  # Common tags to be applied to all resources
  common_tags = {
    Project     = "security-compliance-auditing"
    Environment = var.environment
    ManagedBy   = "terraform"
    Recipe      = "security-compliance-auditing-lattice-guardduty"
  }
}

# ==============================================================================
# S3 BUCKET FOR COMPLIANCE REPORTS
# ==============================================================================

# S3 bucket for storing compliance reports and audit logs
resource "aws_s3_bucket" "compliance_reports" {
  bucket = local.bucket_name

  tags = merge(local.common_tags, {
    Name        = "Security Compliance Reports Bucket"
    Purpose     = "compliance-reports-storage"
    DataClass   = "security-audit-logs"
  })
}

# S3 bucket versioning configuration
resource "aws_s3_bucket_versioning" "compliance_reports" {
  bucket = aws_s3_bucket.compliance_reports.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket server-side encryption configuration
resource "aws_s3_bucket_server_side_encryption_configuration" "compliance_reports" {
  bucket = aws_s3_bucket.compliance_reports.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# S3 bucket public access block
resource "aws_s3_bucket_public_access_block" "compliance_reports" {
  bucket = aws_s3_bucket.compliance_reports.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket lifecycle configuration for cost optimization
resource "aws_s3_bucket_lifecycle_configuration" "compliance_reports" {
  bucket = aws_s3_bucket.compliance_reports.id

  rule {
    id     = "compliance_reports_lifecycle"
    status = "Enabled"

    # Archive compliance reports to IA after 30 days
    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    # Archive to Glacier after 90 days
    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    # Deep Archive after 365 days for long-term retention
    transition {
      days          = 365
      storage_class = "DEEP_ARCHIVE"
    }

    # Expire old compliance reports after 7 years (regulatory requirement)
    expiration {
      days = 2555  # 7 years
    }

    # Clean up incomplete multipart uploads
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# ==============================================================================
# GUARDDUTY DETECTOR
# ==============================================================================

# Enable GuardDuty detector for threat detection
resource "aws_guardduty_detector" "security_monitoring" {
  enable                       = true
  finding_publishing_frequency = var.guardduty_finding_frequency

  # Enable datasources for comprehensive monitoring
  datasources {
    s3_logs {
      enable = true
    }
    kubernetes {
      audit_logs {
        enable = true
      }
    }
    malware_protection {
      scan_ec2_instance_with_findings {
        ebs_volumes {
          enable = true
        }
      }
    }
  }

  tags = merge(local.common_tags, {
    Name    = "Security Compliance GuardDuty Detector"
    Purpose = "threat-detection"
  })
}

# ==============================================================================
# SNS TOPIC FOR SECURITY ALERTS
# ==============================================================================

# SNS topic for security alerts and notifications
resource "aws_sns_topic" "security_alerts" {
  name         = local.sns_topic_name
  display_name = "Security Compliance Alerts"

  # Enable encryption at rest
  kms_master_key_id = "alias/aws/sns"

  tags = merge(local.common_tags, {
    Name    = "Security Alerts SNS Topic"
    Purpose = "security-notifications"
  })
}

# SNS topic policy for secure access
resource "aws_sns_topic_policy" "security_alerts" {
  arn = aws_sns_topic.security_alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action = [
          "SNS:Publish",
          "SNS:Subscribe",
          "SNS:Receive",
          "SNS:GetTopicAttributes"
        ]
        Resource = aws_sns_topic.security_alerts.arn
        Condition = {
          StringEquals = {
            "AWS:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

# Optional email subscription to SNS topic
resource "aws_sns_topic_subscription" "security_alerts_email" {
  count     = var.notification_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.security_alerts.arn
  protocol  = "email"
  endpoint  = var.notification_email

  depends_on = [aws_sns_topic.security_alerts]
}

# ==============================================================================
# CLOUDWATCH LOG GROUP
# ==============================================================================

# CloudWatch log group for VPC Lattice access logs
resource "aws_cloudwatch_log_group" "vpc_lattice_logs" {
  name              = local.log_group_name
  retention_in_days = var.log_retention_days

  # Encryption at rest with CloudWatch Logs default key
  kms_key_id = var.cloudwatch_kms_key_id

  tags = merge(local.common_tags, {
    Name    = "VPC Lattice Security Audit Logs"
    Purpose = "access-logs"
  })
}

# ==============================================================================
# IAM ROLE FOR LAMBDA FUNCTION
# ==============================================================================

# IAM role for the Lambda security processor function
resource "aws_iam_role" "lambda_security_processor" {
  name = "${var.lambda_function_name}-role"

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
    Name    = "Lambda Security Processor Role"
    Purpose = "lambda-execution"
  })
}

# IAM policy for Lambda function with least privilege access
resource "aws_iam_role_policy" "lambda_security_processor" {
  name = "${var.lambda_function_name}-policy"
  role = aws_iam_role.lambda_security_processor.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # CloudWatch Logs permissions
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams",
          "logs:FilterLogEvents"
        ]
        Resource = [
          "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*"
        ]
      },
      # GuardDuty permissions
      {
        Effect = "Allow"
        Action = [
          "guardduty:GetDetector",
          "guardduty:GetFindings",
          "guardduty:ListFindings"
        ]
        Resource = [
          aws_guardduty_detector.security_monitoring.arn,
          "${aws_guardduty_detector.security_monitoring.arn}/*"
        ]
      },
      # S3 permissions for compliance reports
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.compliance_reports.arn,
          "${aws_s3_bucket.compliance_reports.arn}/*"
        ]
      },
      # SNS permissions for alerts
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = [
          aws_sns_topic.security_alerts.arn
        ]
      },
      # CloudWatch metrics permissions
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "cloudwatch:namespace" = "Security/VPCLattice"
          }
        }
      }
    ]
  })
}

# ==============================================================================
# LAMBDA FUNCTION
# ==============================================================================

# Create ZIP archive for Lambda function
data "archive_file" "lambda_security_processor" {
  type        = "zip"
  source_file = "${path.module}/lambda/security_processor.py"
  output_path = "${path.module}/lambda/security_processor.zip"
}

# Lambda function for processing security logs and compliance reporting
resource "aws_lambda_function" "security_processor" {
  filename      = data.archive_file.lambda_security_processor.output_path
  function_name = local.lambda_function_name
  role          = aws_iam_role.lambda_security_processor.arn
  handler       = "security_processor.lambda_handler"
  runtime       = var.lambda_runtime
  timeout       = var.lambda_timeout
  memory_size   = var.lambda_memory_size

  # Environment variables for the Lambda function
  environment {
    variables = {
      GUARDDUTY_DETECTOR_ID = aws_guardduty_detector.security_monitoring.id
      BUCKET_NAME          = aws_s3_bucket.compliance_reports.bucket
      SNS_TOPIC_ARN        = aws_sns_topic.security_alerts.arn
      LOG_LEVEL            = var.lambda_log_level
    }
  }

  # Lambda function depends on the ZIP file being created
  source_code_hash = data.archive_file.lambda_security_processor.output_base64sha256

  # Dead letter queue configuration
  dead_letter_config {
    target_arn = aws_sns_topic.security_alerts.arn
  }

  tags = merge(local.common_tags, {
    Name    = "Security Compliance Processor"
    Purpose = "log-processing"
  })

  depends_on = [
    aws_iam_role_policy.lambda_security_processor,
    aws_cloudwatch_log_group.lambda_logs
  ]
}

# CloudWatch log group for Lambda function
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${local.lambda_function_name}"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, {
    Name    = "Lambda Security Processor Logs"
    Purpose = "lambda-logs"
  })
}

# ==============================================================================
# CLOUDWATCH LOG SUBSCRIPTION FILTER
# ==============================================================================

# Lambda permission for CloudWatch Logs to invoke the function
resource "aws_lambda_permission" "cloudwatch_logs_invoke" {
  statement_id  = "AllowExecutionFromCloudWatchLogs"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.security_processor.function_name
  principal     = "logs.amazonaws.com"
  source_arn    = "${aws_cloudwatch_log_group.vpc_lattice_logs.arn}:*"
}

# CloudWatch log subscription filter to trigger Lambda function
resource "aws_cloudwatch_log_subscription_filter" "security_compliance_filter" {
  name            = "SecurityComplianceFilter"
  log_group_name  = aws_cloudwatch_log_group.vpc_lattice_logs.name
  filter_pattern  = ""  # Process all log events
  destination_arn = aws_lambda_function.security_processor.arn

  depends_on = [aws_lambda_permission.cloudwatch_logs_invoke]
}

# ==============================================================================
# CLOUDWATCH DASHBOARD
# ==============================================================================

# CloudWatch dashboard for security monitoring
resource "aws_cloudwatch_dashboard" "security_compliance" {
  dashboard_name = local.cloudwatch_dashboard_name

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
            ["Security/VPCLattice", "RequestCount"],
            [".", "ErrorCount"]
          ]
          period = 300
          stat   = "Sum"
          region = var.aws_region
          title  = "VPC Lattice Traffic Overview"
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
            ["Security/VPCLattice", "AverageResponseTime"]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
          title  = "Average Response Time"
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
        width  = 24
        height = 6
        properties = {
          query  = "SOURCE '/aws/lambda/${local.lambda_function_name}' | fields @timestamp, @message\n| filter @message like /SECURITY_VIOLATION/\n| sort @timestamp desc\n| limit 20"
          region = var.aws_region
          title  = "Recent Security Alerts"
          view   = "table"
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
            ["AWS/Lambda", "Invocations", "FunctionName", local.lambda_function_name],
            [".", "Errors", ".", "."],
            [".", "Duration", ".", "."]
          ]
          period = 300
          stat   = "Sum"
          region = var.aws_region
          title  = "Lambda Function Metrics"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 12
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/GuardDuty", "FindingCount"]
          ]
          period = 300
          stat   = "Sum"
          region = var.aws_region
          title  = "GuardDuty Findings"
        }
      }
    ]
  })

  depends_on = [aws_lambda_function.security_processor]
}

# ==============================================================================
# VPC LATTICE RESOURCES (DEMO)
# ==============================================================================

# VPC Lattice service network for demonstration
resource "aws_vpclattice_service_network" "security_demo" {
  count = var.create_demo_vpc_lattice ? 1 : 0
  name  = local.vpc_lattice_service_network_name

  tags = merge(local.common_tags, {
    Name    = "Security Demo Service Network"
    Purpose = "demonstration"
  })
}

# VPC Lattice access log subscription
resource "aws_vpclattice_access_log_subscription" "security_demo" {
  count                = var.create_demo_vpc_lattice ? 1 : 0
  resource_identifier  = aws_vpclattice_service_network.security_demo[0].id
  destination_arn     = aws_cloudwatch_log_group.vpc_lattice_logs.arn

  tags = merge(local.common_tags, {
    Name    = "Security Demo Access Log Subscription"
    Purpose = "access-logging"
  })
}

# ==============================================================================
# CLOUDWATCH ALARMS
# ==============================================================================

# CloudWatch alarm for high error rates
resource "aws_cloudwatch_metric_alarm" "high_error_rate" {
  alarm_name          = "security-compliance-high-error-rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "ErrorCount"
  namespace           = "Security/VPCLattice"
  period              = "300"
  statistic           = "Sum"
  threshold           = var.error_rate_threshold
  alarm_description   = "This metric monitors VPC Lattice error rate for security compliance"
  alarm_actions       = [aws_sns_topic.security_alerts.arn]
  ok_actions          = [aws_sns_topic.security_alerts.arn]

  tags = merge(local.common_tags, {
    Name    = "High Error Rate Alarm"
    Purpose = "security-monitoring"
  })
}

# CloudWatch alarm for Lambda function errors
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "security-compliance-lambda-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "This metric monitors Lambda function errors in security processing"
  alarm_actions       = [aws_sns_topic.security_alerts.arn]

  dimensions = {
    FunctionName = aws_lambda_function.security_processor.function_name
  }

  tags = merge(local.common_tags, {
    Name    = "Lambda Errors Alarm"
    Purpose = "function-monitoring"
  })
}