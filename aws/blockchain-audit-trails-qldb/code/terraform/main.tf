# Data sources for AWS account and region information
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}

# Local values for consistent naming
locals {
  name_prefix = "${var.project_name}-${var.environment}"
  
  # Resource names with random suffix
  ledger_name               = var.qldb_ledger_name != null ? var.qldb_ledger_name : "${local.name_prefix}-ledger-${random_string.suffix.result}"
  cloudtrail_name          = var.cloudtrail_name != null ? var.cloudtrail_name : "${local.name_prefix}-trail-${random_string.suffix.result}"
  bucket_name              = var.s3_bucket_name != null ? var.s3_bucket_name : "${local.name_prefix}-bucket-${random_string.suffix.result}"
  lambda_function_name     = var.lambda_function_name != null ? var.lambda_function_name : "${local.name_prefix}-processor-${random_string.suffix.result}"
  firehose_stream_name     = var.firehose_delivery_stream_name != null ? var.firehose_delivery_stream_name : "${local.name_prefix}-stream-${random_string.suffix.result}"
  athena_workgroup_name    = var.athena_workgroup_name != null ? var.athena_workgroup_name : "${local.name_prefix}-workgroup-${random_string.suffix.result}"
  dashboard_name           = var.cloudwatch_dashboard_name != null ? var.cloudwatch_dashboard_name : "${local.name_prefix}-dashboard"

  # Common tags
  common_tags = merge(var.additional_tags, {
    Environment     = var.environment
    Project        = var.project_name
    ManagedBy      = "terraform"
    Purpose        = "compliance-audit-system"
    LedgerName     = local.ledger_name
    CreatedDate    = formatdate("YYYY-MM-DD", timestamp())
  })
}

# S3 Bucket for audit reports and CloudTrail logs
resource "aws_s3_bucket" "audit_bucket" {
  bucket        = local.bucket_name
  force_destroy = var.s3_force_destroy

  tags = merge(local.common_tags, {
    Name        = local.bucket_name
    Description = "S3 bucket for compliance audit reports and CloudTrail logs"
  })
}

# S3 Bucket versioning
resource "aws_s3_bucket_versioning" "audit_bucket_versioning" {
  bucket = aws_s3_bucket.audit_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 Bucket server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "audit_bucket_encryption" {
  bucket = aws_s3_bucket.audit_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# S3 Bucket public access block
resource "aws_s3_bucket_public_access_block" "audit_bucket_pab" {
  bucket = aws_s3_bucket.audit_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 Bucket policy for CloudTrail
resource "aws_s3_bucket_policy" "cloudtrail_bucket_policy" {
  bucket = aws_s3_bucket.audit_bucket.id

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
        Resource = aws_s3_bucket.audit_bucket.arn
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = "arn:aws:cloudtrail:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:trail/${local.cloudtrail_name}"
          }
        }
      },
      {
        Sid    = "AWSCloudTrailWrite"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.audit_bucket.arn}/cloudtrail-logs/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
            "AWS:SourceArn" = "arn:aws:cloudtrail:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:trail/${local.cloudtrail_name}"
          }
        }
      }
    ]
  })
}

# KMS Key for QLDB encryption
resource "aws_kms_key" "qldb_key" {
  description             = "KMS key for QLDB ledger encryption"
  deletion_window_in_days = 7

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
        Sid    = "Allow QLDB Service"
        Effect = "Allow"
        Principal = {
          Service = "qldb.amazonaws.com"
        }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = "*"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-qldb-key"
    Description = "KMS key for QLDB ledger encryption"
  })
}

# KMS Key alias
resource "aws_kms_alias" "qldb_key_alias" {
  name          = "alias/${local.name_prefix}-qldb-key"
  target_key_id = aws_kms_key.qldb_key.key_id
}

# QLDB Ledger for immutable audit records
resource "aws_qldb_ledger" "compliance_ledger" {
  name                = local.ledger_name
  permissions_mode    = var.qldb_permissions_mode
  deletion_protection = var.qldb_deletion_protection
  kms_key             = aws_kms_key.qldb_key.arn

  tags = merge(local.common_tags, {
    Name        = local.ledger_name
    Description = "QLDB ledger for immutable compliance audit records"
  })
}

# IAM role for Lambda audit processor
resource "aws_iam_role" "lambda_execution_role" {
  name = "${local.lambda_function_name}-role"

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
    Name        = "${local.lambda_function_name}-role"
    Description = "IAM role for Lambda audit processor function"
  })
}

# IAM policy for Lambda execution
resource "aws_iam_role_policy" "lambda_execution_policy" {
  name = "${local.lambda_function_name}-policy"
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
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
      },
      {
        Effect = "Allow"
        Action = [
          "qldb:SendCommand",
          "qldb:GetDigest",
          "qldb:GetBlock",
          "qldb:GetRevision"
        ]
        Resource = aws_qldb_ledger.compliance_ledger.arn
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject"
        ]
        Resource = "${aws_s3_bucket.audit_bucket.arn}/*"
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
        Resource = aws_sns_topic.compliance_alerts.arn
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = aws_kms_key.qldb_key.arn
      }
    ]
  })
}

# Lambda function for audit processing
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "/tmp/audit_processor.zip"
  
  source {
    content = templatefile("${path.module}/lambda_function.py", {
      ledger_name = local.ledger_name
      bucket_name = local.bucket_name
    })
    filename = "lambda_function.py"
  }
}

resource "aws_lambda_function" "audit_processor" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = local.lambda_function_name
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  runtime         = "python3.9"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size

  environment {
    variables = {
      LEDGER_NAME = local.ledger_name
      S3_BUCKET   = local.bucket_name
      REGION      = data.aws_region.current.name
    }
  }

  depends_on = [
    aws_iam_role_policy.lambda_execution_policy,
    aws_cloudwatch_log_group.lambda_logs
  ]

  tags = merge(local.common_tags, {
    Name        = local.lambda_function_name
    Description = "Lambda function for processing compliance audit events"
  })
}

# CloudWatch Log Group for Lambda
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${local.lambda_function_name}"
  retention_in_days = 14

  tags = merge(local.common_tags, {
    Name        = "/aws/lambda/${local.lambda_function_name}"
    Description = "CloudWatch logs for Lambda audit processor"
  })
}

# CloudTrail for API activity logging
resource "aws_cloudtrail" "compliance_trail" {
  name           = local.cloudtrail_name
  s3_bucket_name = aws_s3_bucket.audit_bucket.id
  s3_key_prefix  = "cloudtrail-logs/"

  include_global_service_events = var.cloudtrail_include_global_service_events
  is_multi_region_trail        = var.cloudtrail_is_multi_region_trail
  enable_log_file_validation   = var.enable_cloudtrail_log_file_validation

  depends_on = [aws_s3_bucket_policy.cloudtrail_bucket_policy]

  tags = merge(local.common_tags, {
    Name        = local.cloudtrail_name
    Description = "CloudTrail for compliance audit logging"
  })
}

# EventBridge rule for real-time processing
resource "aws_cloudwatch_event_rule" "compliance_audit_rule" {
  name        = var.eventbridge_rule_name
  description = "Process critical API calls for compliance audit"

  event_pattern = jsonencode({
    source      = ["aws.cloudtrail"]
    detail-type = ["AWS API Call via CloudTrail"]
    detail = {
      eventSource = ["qldb.amazonaws.com", "s3.amazonaws.com", "iam.amazonaws.com"]
      eventName   = ["SendCommand", "PutObject", "CreateRole", "DeleteRole"]
    }
  })

  tags = merge(local.common_tags, {
    Name        = var.eventbridge_rule_name
    Description = "EventBridge rule for compliance audit processing"
  })
}

# EventBridge target for Lambda
resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.compliance_audit_rule.name
  target_id = "ComplianceLambdaTarget"
  arn       = aws_lambda_function.audit_processor.arn
}

# Lambda permission for EventBridge
resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.audit_processor.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.compliance_audit_rule.arn
}

# SNS topic for compliance alerts
resource "aws_sns_topic" "compliance_alerts" {
  name = "${local.name_prefix}-alerts"

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-alerts"
    Description = "SNS topic for compliance audit alerts"
  })
}

# SNS topic subscription
resource "aws_sns_topic_subscription" "email_alerts" {
  topic_arn = aws_sns_topic.compliance_alerts.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# CloudWatch alarm for audit processing failures
resource "aws_cloudwatch_metric_alarm" "audit_errors" {
  alarm_name          = "${local.name_prefix}-audit-errors"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "1"
  alarm_description   = "Alert when audit processing fails"
  alarm_actions       = [aws_sns_topic.compliance_alerts.arn]

  dimensions = {
    FunctionName = aws_lambda_function.audit_processor.function_name
  }

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-audit-errors"
    Description = "CloudWatch alarm for audit processing errors"
  })
}

# IAM role for Kinesis Data Firehose
resource "aws_iam_role" "firehose_delivery_role" {
  name = "${local.name_prefix}-firehose-role"

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

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-firehose-role"
    Description = "IAM role for Kinesis Data Firehose delivery"
  })
}

# IAM policy for Firehose
resource "aws_iam_role_policy" "firehose_delivery_policy" {
  name = "${local.name_prefix}-firehose-policy"
  role = aws_iam_role.firehose_delivery_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.audit_bucket.arn,
          "${aws_s3_bucket.audit_bucket.arn}/*"
        ]
      }
    ]
  })
}

# Kinesis Data Firehose delivery stream
resource "aws_kinesis_firehose_delivery_stream" "compliance_stream" {
  name        = local.firehose_stream_name
  destination = "s3"

  s3_configuration {
    role_arn           = aws_iam_role.firehose_delivery_role.arn
    bucket_arn         = aws_s3_bucket.audit_bucket.arn
    prefix             = "compliance-reports/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/"
    buffer_size        = var.firehose_buffer_size
    buffer_interval    = var.firehose_buffer_interval
    compression_format = "GZIP"
  }

  tags = merge(local.common_tags, {
    Name        = local.firehose_stream_name
    Description = "Kinesis Data Firehose for compliance report delivery"
  })
}

# Athena workgroup for compliance queries
resource "aws_athena_workgroup" "compliance_workgroup" {
  name = local.athena_workgroup_name

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = var.enable_detailed_monitoring

    result_configuration {
      output_location = "s3://${aws_s3_bucket.audit_bucket.bucket}/athena-results/"

      encryption_configuration {
        encryption_option = "SSE_S3"
      }
    }
  }

  tags = merge(local.common_tags, {
    Name        = local.athena_workgroup_name
    Description = "Athena workgroup for compliance audit queries"
  })
}

# Athena database
resource "aws_athena_database" "compliance_database" {
  name   = var.athena_database_name
  bucket = aws_s3_bucket.audit_bucket.bucket

  encryption_configuration {
    encryption_option = "SSE_S3"
  }
}

# CloudWatch dashboard for compliance metrics
resource "aws_cloudwatch_dashboard" "compliance_dashboard" {
  dashboard_name = local.dashboard_name

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
            ["ComplianceAudit", "AuditRecordsProcessed"],
            ["AWS/Lambda", "Invocations", "FunctionName", aws_lambda_function.audit_processor.function_name],
            ["AWS/Lambda", "Errors", "FunctionName", aws_lambda_function.audit_processor.function_name]
          ]
          period = 300
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "Compliance Audit Metrics"
        }
      },
      {
        type   = "log"
        x      = 0
        y      = 6
        width  = 24
        height = 6

        properties = {
          query = "SOURCE '/aws/lambda/${aws_lambda_function.audit_processor.function_name}' | fields @timestamp, @message | filter @message like /audit/ | sort @timestamp desc | limit 100"
          region = data.aws_region.current.name
          title  = "Recent Audit Processing Logs"
        }
      }
    ]
  })
}

# Write Lambda function code to file
resource "local_file" "lambda_function" {
  content = templatefile("${path.module}/lambda_function.py.tpl", {
    ledger_name = local.ledger_name
    bucket_name = local.bucket_name
  })
  filename = "${path.module}/lambda_function.py"
}