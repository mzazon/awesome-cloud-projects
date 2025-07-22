# Data sources for current AWS account and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

locals {
  # Generate unique names if not provided
  source_bucket_name    = var.source_bucket_name != "" ? var.source_bucket_name : "secure-docs-${random_string.suffix.result}"
  logs_bucket_name      = var.logs_bucket_name != "" ? var.logs_bucket_name : "s3-access-logs-${random_string.suffix.result}"
  cloudtrail_bucket_name = var.cloudtrail_bucket_name != "" ? var.cloudtrail_bucket_name : "cloudtrail-logs-${random_string.suffix.result}"
  
  # Common tags
  common_tags = merge(
    {
      Project     = "S3AccessLoggingSecurityMonitoring"
      Environment = var.environment
      ManagedBy   = "Terraform"
    },
    var.additional_tags
  )
}

# ========================================
# S3 Buckets
# ========================================

# Source bucket to monitor
resource "aws_s3_bucket" "source" {
  bucket = local.source_bucket_name
  
  tags = merge(local.common_tags, {
    Name = "Source Bucket"
    Purpose = "MonitoredBucket"
  })
}

# S3 bucket for access logs
resource "aws_s3_bucket" "logs" {
  bucket = local.logs_bucket_name
  
  tags = merge(local.common_tags, {
    Name = "Access Logs Bucket"
    Purpose = "AccessLogging"
  })
}

# S3 bucket for CloudTrail logs
resource "aws_s3_bucket" "cloudtrail" {
  bucket = local.cloudtrail_bucket_name
  
  tags = merge(local.common_tags, {
    Name = "CloudTrail Logs Bucket"
    Purpose = "CloudTrailLogging"
  })
}

# ========================================
# S3 Bucket Configurations
# ========================================

# Source bucket versioning
resource "aws_s3_bucket_versioning" "source" {
  count  = var.enable_versioning ? 1 : 0
  bucket = aws_s3_bucket.source.id
  
  versioning_configuration {
    status = "Enabled"
  }
}

# Source bucket encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "source" {
  count  = var.enable_server_side_encryption ? 1 : 0
  bucket = aws_s3_bucket.source.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Source bucket public access block
resource "aws_s3_bucket_public_access_block" "source" {
  bucket = aws_s3_bucket.source.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Logs bucket versioning
resource "aws_s3_bucket_versioning" "logs" {
  count  = var.enable_versioning ? 1 : 0
  bucket = aws_s3_bucket.logs.id
  
  versioning_configuration {
    status = "Enabled"
  }
}

# Logs bucket encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  count  = var.enable_server_side_encryption ? 1 : 0
  bucket = aws_s3_bucket.logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Logs bucket public access block
resource "aws_s3_bucket_public_access_block" "logs" {
  bucket = aws_s3_bucket.logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# CloudTrail bucket versioning
resource "aws_s3_bucket_versioning" "cloudtrail" {
  count  = var.enable_versioning ? 1 : 0
  bucket = aws_s3_bucket.cloudtrail.id
  
  versioning_configuration {
    status = "Enabled"
  }
}

# CloudTrail bucket encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail" {
  count  = var.enable_server_side_encryption ? 1 : 0
  bucket = aws_s3_bucket.cloudtrail.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# CloudTrail bucket public access block
resource "aws_s3_bucket_public_access_block" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ========================================
# S3 Access Logging Configuration
# ========================================

# S3 bucket policy for access logging
resource "aws_s3_bucket_policy" "logs" {
  bucket = aws_s3_bucket.logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3ServerAccessLogsPolicy"
        Effect = "Allow"
        Principal = {
          Service = "logging.s3.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.logs.arn}/access-logs/*"
        Condition = {
          ArnLike = {
            "aws:SourceArn" = aws_s3_bucket.source.arn
          }
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

# Enable S3 server access logging
resource "aws_s3_bucket_logging" "source" {
  bucket = aws_s3_bucket.source.id

  target_bucket = aws_s3_bucket.logs.id
  target_prefix = "access-logs/"
  
  target_object_key_format {
    partitioned_prefix {
      partition_date_source = "EventTime"
    }
  }

  depends_on = [aws_s3_bucket_policy.logs]
}

# ========================================
# CloudTrail Configuration
# ========================================

# CloudTrail bucket policy
resource "aws_s3_bucket_policy" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSCloudTrailAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.cloudtrail.arn
      },
      {
        Sid    = "AWSCloudTrailWrite"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.cloudtrail.arn}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      }
    ]
  })
}

# CloudWatch log group for CloudTrail
resource "aws_cloudwatch_log_group" "cloudtrail" {
  count             = var.enable_cloudwatch_logs ? 1 : 0
  name              = "/aws/cloudtrail/${var.cloudtrail_name}"
  retention_in_days = var.cloudwatch_logs_retention_days
  
  tags = merge(local.common_tags, {
    Name = "CloudTrail Log Group"
  })
}

# IAM role for CloudTrail CloudWatch integration
resource "aws_iam_role" "cloudtrail_logs" {
  count = var.enable_cloudwatch_logs ? 1 : 0
  name  = "CloudTrailLogsRole-${random_string.suffix.result}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
  
  tags = merge(local.common_tags, {
    Name = "CloudTrail Logs Role"
  })
}

# IAM policy for CloudTrail CloudWatch integration
resource "aws_iam_role_policy" "cloudtrail_logs" {
  count = var.enable_cloudwatch_logs ? 1 : 0
  name  = "CloudTrailLogsPolicy"
  role  = aws_iam_role.cloudtrail_logs[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = "${aws_cloudwatch_log_group.cloudtrail[0].arn}*"
      }
    ]
  })
}

# CloudTrail trail
resource "aws_cloudtrail" "main" {
  name                          = var.cloudtrail_name
  s3_bucket_name               = aws_s3_bucket.cloudtrail.bucket
  s3_key_prefix                = "cloudtrail-logs/"
  include_global_service_events = var.include_global_service_events
  is_multi_region_trail        = var.is_multi_region_trail
  enable_log_file_validation   = var.enable_log_file_validation

  # CloudWatch Logs integration
  cloud_watch_logs_group_arn = var.enable_cloudwatch_logs ? "${aws_cloudwatch_log_group.cloudtrail[0].arn}:*" : null
  cloud_watch_logs_role_arn  = var.enable_cloudwatch_logs ? aws_iam_role.cloudtrail_logs[0].arn : null

  # S3 data events for the source bucket
  event_selector {
    read_write_type                 = "All"
    include_management_events       = true

    data_resource {
      type   = "AWS::S3::Object"
      values = ["${aws_s3_bucket.source.arn}/*"]
    }
  }

  depends_on = [
    aws_s3_bucket_policy.cloudtrail,
    aws_iam_role_policy.cloudtrail_logs
  ]
  
  tags = merge(local.common_tags, {
    Name = "S3 Security Monitoring Trail"
  })
}

# ========================================
# SNS Topic for Security Alerts
# ========================================

# SNS topic for security alerts
resource "aws_sns_topic" "security_alerts" {
  count = var.enable_security_monitoring ? 1 : 0
  name  = "s3-security-alerts-${random_string.suffix.result}"
  
  tags = merge(local.common_tags, {
    Name = "S3 Security Alerts Topic"
  })
}

# SNS topic policy
resource "aws_sns_topic_policy" "security_alerts" {
  count = var.enable_security_monitoring ? 1 : 0
  arn   = aws_sns_topic.security_alerts[0].arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action   = "sns:Publish"
        Resource = aws_sns_topic.security_alerts[0].arn
      }
    ]
  })
}

# SNS email subscription (optional)
resource "aws_sns_topic_subscription" "email_alerts" {
  count     = var.enable_security_monitoring && var.security_alert_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.security_alerts[0].arn
  protocol  = "email"
  endpoint  = var.security_alert_email
}

# ========================================
# EventBridge Rules for Security Monitoring
# ========================================

# EventBridge rule for unauthorized access attempts
resource "aws_cloudwatch_event_rule" "unauthorized_access" {
  count       = var.enable_security_monitoring ? 1 : 0
  name        = "S3UnauthorizedAccess-${random_string.suffix.result}"
  description = "Detect unauthorized S3 access attempts"

  event_pattern = jsonencode({
    source      = ["aws.s3"]
    detail-type = ["AWS API Call via CloudTrail"]
    detail = {
      eventName = ["GetObject", "PutObject", "DeleteObject"]
      errorCode = ["AccessDenied", "SignatureDoesNotMatch"]
    }
  })
  
  tags = merge(local.common_tags, {
    Name = "S3 Unauthorized Access Rule"
  })
}

# EventBridge target for SNS
resource "aws_cloudwatch_event_target" "sns_target" {
  count     = var.enable_security_monitoring ? 1 : 0
  rule      = aws_cloudwatch_event_rule.unauthorized_access[0].name
  target_id = "SecurityAlertTarget"
  arn       = aws_sns_topic.security_alerts[0].arn
}

# EventBridge rule for bucket policy changes
resource "aws_cloudwatch_event_rule" "bucket_policy_changes" {
  count       = var.enable_security_monitoring ? 1 : 0
  name        = "S3BucketPolicyChanges-${random_string.suffix.result}"
  description = "Detect S3 bucket policy changes"

  event_pattern = jsonencode({
    source      = ["aws.s3"]
    detail-type = ["AWS API Call via CloudTrail"]
    detail = {
      eventName = ["PutBucketPolicy", "DeleteBucketPolicy", "PutBucketAcl"]
    }
  })
  
  tags = merge(local.common_tags, {
    Name = "S3 Bucket Policy Changes Rule"
  })
}

# EventBridge target for bucket policy changes
resource "aws_cloudwatch_event_target" "bucket_policy_sns_target" {
  count     = var.enable_security_monitoring ? 1 : 0
  rule      = aws_cloudwatch_event_rule.bucket_policy_changes[0].name
  target_id = "BucketPolicyChangeTarget"
  arn       = aws_sns_topic.security_alerts[0].arn
}

# ========================================
# Lambda Function for Advanced Security Monitoring
# ========================================

# Lambda execution role
resource "aws_iam_role" "lambda_execution" {
  count = var.enable_lambda_monitoring ? 1 : 0
  name  = "S3SecurityMonitorLambdaRole-${random_string.suffix.result}"

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
  })
}

# Lambda execution policy
resource "aws_iam_role_policy" "lambda_execution" {
  count = var.enable_lambda_monitoring ? 1 : 0
  name  = "S3SecurityMonitorLambdaPolicy"
  role  = aws_iam_role.lambda_execution[0].id

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
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/*"
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = var.enable_security_monitoring ? aws_sns_topic.security_alerts[0].arn : "*"
      }
    ]
  })
}

# Lambda function for security monitoring
resource "aws_lambda_function" "security_monitor" {
  count         = var.enable_lambda_monitoring ? 1 : 0
  filename      = "security_monitor.zip"
  function_name = "s3-security-monitor-${random_string.suffix.result}"
  role          = aws_iam_role.lambda_execution[0].arn
  handler       = "index.lambda_handler"
  runtime       = "python3.9"
  timeout       = var.lambda_timeout

  source_code_hash = data.archive_file.lambda_zip[0].output_base64sha256

  environment {
    variables = {
      SNS_TOPIC_ARN = var.enable_security_monitoring ? aws_sns_topic.security_alerts[0].arn : ""
    }
  }
  
  tags = merge(local.common_tags, {
    Name = "S3 Security Monitor Lambda"
  })
}

# Lambda source code
data "archive_file" "lambda_zip" {
  count       = var.enable_lambda_monitoring ? 1 : 0
  type        = "zip"
  output_path = "security_monitor.zip"
  
  source {
    content = templatefile("${path.module}/lambda_template.py", {
      sns_topic_arn = var.enable_security_monitoring ? aws_sns_topic.security_alerts[0].arn : ""
    })
    filename = "index.py"
  }
}

# Lambda permission for EventBridge
resource "aws_lambda_permission" "eventbridge_lambda" {
  count         = var.enable_lambda_monitoring ? 1 : 0
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.security_monitor[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.unauthorized_access[0].arn
}

# EventBridge target for Lambda
resource "aws_cloudwatch_event_target" "lambda_target" {
  count     = var.enable_lambda_monitoring ? 1 : 0
  rule      = aws_cloudwatch_event_rule.unauthorized_access[0].name
  target_id = "SecurityAnalysisTarget"
  arn       = aws_lambda_function.security_monitor[0].arn
}

# ========================================
# CloudWatch Dashboard
# ========================================

# CloudWatch dashboard for S3 security monitoring
resource "aws_cloudwatch_dashboard" "s3_security" {
  count          = var.enable_dashboard ? 1 : 0
  dashboard_name = var.dashboard_name

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
            ["AWS/S3", "BucketSizeBytes", "BucketName", aws_s3_bucket.source.bucket, "StorageType", "StandardStorage"],
            ["AWS/S3", "NumberOfObjects", "BucketName", aws_s3_bucket.source.bucket, "StorageType", "AllStorageTypes"]
          ]
          period = 300
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "S3 Bucket Metrics"
          view   = "timeSeries"
        }
      },
      {
        type   = "log"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          query = var.enable_cloudwatch_logs ? "SOURCE '${aws_cloudwatch_log_group.cloudtrail[0].name}' | fields @timestamp, eventName, sourceIPAddress, userIdentity.type | filter eventName like /GetObject|PutObject|DeleteObject/ | stats count() by eventName | sort count desc" : "No CloudWatch logs enabled"
          region = data.aws_region.current.name
          title  = "Top S3 API Calls"
          view   = "table"
        }
      }
    ]
  })
}

