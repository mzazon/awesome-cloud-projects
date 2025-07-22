# main.tf
# Main configuration for FSx Intelligent Tiering with Lambda lifecycle management

# Data sources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Get default VPC if not provided
data "aws_vpc" "default" {
  count   = var.vpc_id == "" ? 1 : 0
  default = true
}

# Get default subnet if not provided
data "aws_subnets" "default" {
  count = var.subnet_id == "" ? 1 : 0
  
  filter {
    name   = "vpc-id"
    values = [local.vpc_id]
  }
  
  filter {
    name   = "availability-zone"
    values = [data.aws_availability_zones.available.names[0]]
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

# Random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 4
}

# Local values
locals {
  vpc_id              = var.vpc_id != "" ? var.vpc_id : data.aws_vpc.default[0].id
  subnet_id           = var.subnet_id != "" ? var.subnet_id : data.aws_subnets.default[0].ids[0]
  resource_prefix     = "${var.project_name}-${var.environment}"
  unique_suffix       = random_id.suffix.hex
}

# ============================================================================
# KMS Keys for Encryption
# ============================================================================

# KMS key for FSx encryption
resource "aws_kms_key" "fsx" {
  count = var.enable_kms_encryption ? 1 : 0
  
  description             = "KMS key for FSx file system encryption"
  deletion_window_in_days = var.kms_key_deletion_window
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
        Sid    = "Allow FSx Service"
        Effect = "Allow"
        Principal = {
          Service = "fsx.amazonaws.com"
        }
        Action = [
          "kms:CreateGrant",
          "kms:Decrypt",
          "kms:DescribeKey",
          "kms:Encrypt",
          "kms:GenerateDataKey*",
          "kms:ReEncrypt*"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Name = "${local.resource_prefix}-fsx-key"
  }
}

resource "aws_kms_alias" "fsx" {
  count         = var.enable_kms_encryption ? 1 : 0
  name          = "alias/${local.resource_prefix}-fsx"
  target_key_id = aws_kms_key.fsx[0].key_id
}

# KMS key for CloudWatch Logs
resource "aws_kms_key" "logs" {
  count = var.enable_kms_encryption ? 1 : 0
  
  description             = "KMS key for CloudWatch Logs encryption"
  deletion_window_in_days = var.kms_key_deletion_window
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
        Sid    = "Allow CloudWatch Logs"
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
            "kms:EncryptionContext:aws:logs:arn" = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
          }
        }
      }
    ]
  })

  tags = {
    Name = "${local.resource_prefix}-logs-key"
  }
}

# KMS key for S3 encryption
resource "aws_kms_key" "s3" {
  count = var.enable_kms_encryption ? 1 : 0
  
  description             = "KMS key for S3 bucket encryption"
  deletion_window_in_days = var.kms_key_deletion_window
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
      }
    ]
  })

  tags = {
    Name = "${local.resource_prefix}-s3-key"
  }
}

# KMS key for SNS encryption
resource "aws_kms_key" "sns" {
  count = var.enable_kms_encryption ? 1 : 0
  
  description             = "KMS key for SNS topic encryption"
  deletion_window_in_days = var.kms_key_deletion_window
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
        Sid    = "Allow SNS Service"
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

  tags = {
    Name = "${local.resource_prefix}-sns-key"
  }
}

# ============================================================================
# Security Groups
# ============================================================================

# Security group for FSx
resource "aws_security_group" "fsx" {
  name_prefix = "${local.resource_prefix}-fsx-"
  description = "Security group for FSx file system"
  vpc_id      = local.vpc_id

  # NFS traffic (port 2049)
  ingress {
    description = "NFS traffic"
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  # Allow traffic within the security group
  ingress {
    description = "Self-referencing rule"
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    self        = true
  }

  # Outbound internet access for updates and monitoring
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.resource_prefix}-fsx-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Security group for Lambda functions
resource "aws_security_group" "lambda" {
  name_prefix = "${local.resource_prefix}-lambda-"
  description = "Security group for Lambda functions"
  vpc_id      = local.vpc_id

  # Outbound HTTPS for AWS API calls
  egress {
    description = "HTTPS outbound"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Outbound HTTP for potential API calls
  egress {
    description = "HTTP outbound"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.resource_prefix}-lambda-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ============================================================================
# S3 Bucket for Reports and Lambda Code
# ============================================================================

# S3 bucket for FSx reports and Lambda deployment packages
resource "aws_s3_bucket" "fsx_reports" {
  bucket        = "${local.resource_prefix}-fsx-reports-${local.unique_suffix}"
  force_destroy = var.environment != "production"

  tags = {
    Name = "${local.resource_prefix}-fsx-reports"
  }
}

# S3 bucket versioning
resource "aws_s3_bucket_versioning" "fsx_reports" {
  bucket = aws_s3_bucket.fsx_reports.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "fsx_reports" {
  bucket = aws_s3_bucket.fsx_reports.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = var.enable_kms_encryption ? aws_kms_key.s3[0].arn : null
      sse_algorithm     = var.enable_kms_encryption ? "aws:kms" : "AES256"
    }
    bucket_key_enabled = var.enable_kms_encryption
  }
}

# S3 bucket public access block
resource "aws_s3_bucket_public_access_block" "fsx_reports" {
  bucket = aws_s3_bucket.fsx_reports.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket lifecycle configuration
resource "aws_s3_bucket_lifecycle_configuration" "fsx_reports" {
  depends_on = [aws_s3_bucket_versioning.fsx_reports]
  bucket     = aws_s3_bucket.fsx_reports.id

  rule {
    id     = "fsx_reports_lifecycle"
    status = "Enabled"

    # Transition current versions
    transition {
      days          = var.s3_reports_lifecycle_days
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = var.s3_reports_glacier_days
      storage_class = "GLACIER"
    }

    # Expire current versions
    expiration {
      days = var.s3_reports_expiration_days
    }

    # Handle non-current versions
    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "STANDARD_IA"
    }

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

# S3 intelligent tiering configuration for cost optimization
resource "aws_s3_bucket_intelligent_tiering_configuration" "fsx_reports" {
  bucket = aws_s3_bucket.fsx_reports.id
  name   = "fsx-reports-intelligent-tiering"

  tiering {
    access_tier = "ARCHIVE_ACCESS"
    days        = 90
  }

  tiering {
    access_tier = "DEEP_ARCHIVE_ACCESS"
    days        = 180
  }
}

# ============================================================================
# SNS Topic for Notifications
# ============================================================================

# SNS topic for FSx lifecycle alerts
resource "aws_sns_topic" "fsx_alerts" {
  name         = "${local.resource_prefix}-fsx-alerts"
  display_name = "FSx Lifecycle Management Alerts"
  
  kms_master_key_id                 = var.enable_kms_encryption ? aws_kms_key.sns[0].id : null
  lambda_success_feedback_role_arn  = aws_iam_role.sns_feedback.arn
  lambda_success_feedback_sample_rate = 100
  lambda_failure_feedback_role_arn  = aws_iam_role.sns_feedback.arn

  tags = {
    Name = "${local.resource_prefix}-fsx-alerts"
  }
}

# SNS topic policy
resource "aws_sns_topic_policy" "fsx_alerts" {
  arn = aws_sns_topic.fsx_alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudWatchAlarmsToPublish"
        Effect = "Allow"
        Principal = {
          Service = "cloudwatch.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.fsx_alerts.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

# SNS email subscriptions
resource "aws_sns_topic_subscription" "email_alerts" {
  count     = length(var.alert_email_addresses)
  topic_arn = aws_sns_topic.fsx_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email_addresses[count.index]
}

# IAM role for SNS delivery status logging
resource "aws_iam_role" "sns_feedback" {
  name_prefix = "${local.resource_prefix}-sns-feedback-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "sns.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${local.resource_prefix}-sns-feedback-role"
  }
}

# IAM policy attachment for SNS feedback
resource "aws_iam_role_policy_attachment" "sns_feedback" {
  role       = aws_iam_role.sns_feedback.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/SNSRole"
}

# ============================================================================
# FSx for OpenZFS File System
# ============================================================================

# FSx for OpenZFS file system with intelligent tiering
resource "aws_fsx_openzfs_file_system" "intelligent_tiering" {
  storage_capacity              = var.fsx_storage_capacity
  subnet_ids                    = [local.subnet_id]
  deployment_type               = var.fsx_deployment_type
  throughput_capacity           = var.fsx_throughput_capacity
  storage_type                  = var.enable_intelligent_tiering ? "INTELLIGENT_TIERING" : "SSD"
  security_group_ids            = [aws_security_group.fsx.id]
  kms_key_id                    = var.enable_kms_encryption ? aws_kms_key.fsx[0].arn : null

  # Backup configuration
  automatic_backup_retention_days   = var.fsx_backup_retention_days
  daily_automatic_backup_start_time = var.fsx_backup_start_time
  copy_tags_to_backups              = true

  # Root volume configuration
  root_volume_configuration {
    data_compression_type  = "LZ4"    # Optimize storage efficiency
    record_size_kib       = 128       # Optimize for general workloads
    copy_tags_to_snapshots = true

    # NFS exports configuration
    nfs_exports {
      client_configurations {
        clients = "*"
        options = ["sync", "crossmount", "no_root_squash"]
      }
    }
  }

  # Disk IOPS configuration (automatic optimization)
  disk_iops_configuration {
    mode = "AUTOMATIC"
  }

  tags = {
    Name = "${local.resource_prefix}-fsx-intelligent-tiering"
  }

  # Allow sufficient time for FSx operations
  timeouts {
    create = "60m"
    update = "60m"
    delete = "60m"
  }
}

# ============================================================================
# Lambda Functions for Lifecycle Management
# ============================================================================

# Create Lambda deployment packages
data "archive_file" "lifecycle_policy_lambda" {
  type        = "zip"
  output_path = "${path.module}/lambda_packages/lifecycle-policy.zip"
  
  source {
    content = templatefile("${path.module}/lambda/lifecycle_policy.py", {
      fsx_file_system_id = aws_fsx_openzfs_file_system.intelligent_tiering.id
      sns_topic_arn      = aws_sns_topic.fsx_alerts.arn
    })
    filename = "lifecycle_policy.py"
  }
}

data "archive_file" "cost_reporting_lambda" {
  type        = "zip"
  output_path = "${path.module}/lambda_packages/cost-reporting.zip"
  
  source {
    content = templatefile("${path.module}/lambda/cost_reporting.py", {
      s3_bucket_name = aws_s3_bucket.fsx_reports.bucket
    })
    filename = "cost_reporting.py"
  }
}

data "archive_file" "alert_handler_lambda" {
  type        = "zip"
  output_path = "${path.module}/lambda_packages/alert-handler.zip"
  
  source {
    content = templatefile("${path.module}/lambda/alert_handler.py", {
      fsx_file_system_id = aws_fsx_openzfs_file_system.intelligent_tiering.id
      sns_topic_arn      = aws_sns_topic.fsx_alerts.arn
    })
    filename = "alert_handler.py"
  }
}

# IAM role for Lambda functions
resource "aws_iam_role" "lambda_execution_role" {
  name_prefix = "${local.resource_prefix}-lambda-execution-"

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

  tags = {
    Name = "${local.resource_prefix}-lambda-execution-role"
  }
}

# Lambda basic execution policy attachment
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Lambda VPC execution policy attachment
resource "aws_iam_role_policy_attachment" "lambda_vpc_execution" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# Custom IAM policy for Lambda FSx and monitoring access
resource "aws_iam_role_policy" "lambda_fsx_policy" {
  name_prefix = "${local.resource_prefix}-lambda-fsx-"
  role        = aws_iam_role.lambda_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "fsx:DescribeFileSystems",
          "fsx:DescribeVolumes",
          "fsx:DescribeSnapshots",
          "fsx:DescribeBackups"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.fsx_alerts.arn
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = "${aws_s3_bucket.fsx_reports.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = aws_s3_bucket.fsx_reports.arn
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = var.enable_kms_encryption ? [
          aws_kms_key.fsx[0].arn,
          aws_kms_key.s3[0].arn,
          aws_kms_key.sns[0].arn,
          aws_kms_key.logs[0].arn
        ] : []
      }
    ]
  })
}

# CloudWatch Log Groups for Lambda functions
resource "aws_cloudwatch_log_group" "lifecycle_policy_logs" {
  name              = "/aws/lambda/${local.resource_prefix}-lifecycle-policy"
  retention_in_days = var.cloudwatch_log_retention_days
  kms_key_id        = var.enable_kms_encryption ? aws_kms_key.logs[0].arn : null

  tags = {
    Name = "${local.resource_prefix}-lifecycle-policy-logs"
  }
}

resource "aws_cloudwatch_log_group" "cost_reporting_logs" {
  name              = "/aws/lambda/${local.resource_prefix}-cost-reporting"
  retention_in_days = var.cloudwatch_log_retention_days
  kms_key_id        = var.enable_kms_encryption ? aws_kms_key.logs[0].arn : null

  tags = {
    Name = "${local.resource_prefix}-cost-reporting-logs"
  }
}

resource "aws_cloudwatch_log_group" "alert_handler_logs" {
  name              = "/aws/lambda/${local.resource_prefix}-alert-handler"
  retention_in_days = var.cloudwatch_log_retention_days
  kms_key_id        = var.enable_kms_encryption ? aws_kms_key.logs[0].arn : null

  tags = {
    Name = "${local.resource_prefix}-alert-handler-logs"
  }
}

# Lambda function for lifecycle policy management
resource "aws_lambda_function" "lifecycle_policy" {
  filename         = data.archive_file.lifecycle_policy_lambda.output_path
  function_name    = "${local.resource_prefix}-lifecycle-policy"
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "lifecycle_policy.lambda_handler"
  runtime         = var.lambda_runtime
  architectures   = [var.lambda_architecture]
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size

  source_code_hash = data.archive_file.lifecycle_policy_lambda.output_base64sha256

  environment {
    variables = {
      FSX_FILE_SYSTEM_ID = aws_fsx_openzfs_file_system.intelligent_tiering.id
      SNS_TOPIC_ARN      = aws_sns_topic.fsx_alerts.arn
      LOG_LEVEL          = "INFO"
    }
  }

  tracing_config {
    mode = "Active"
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_cloudwatch_log_group.lifecycle_policy_logs
  ]

  tags = {
    Name = "${local.resource_prefix}-lifecycle-policy"
  }
}

# Lambda function for cost reporting
resource "aws_lambda_function" "cost_reporting" {
  filename         = data.archive_file.cost_reporting_lambda.output_path
  function_name    = "${local.resource_prefix}-cost-reporting"
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "cost_reporting.lambda_handler"
  runtime         = var.lambda_runtime
  architectures   = [var.lambda_architecture]
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size

  source_code_hash = data.archive_file.cost_reporting_lambda.output_base64sha256

  environment {
    variables = {
      S3_BUCKET_NAME = aws_s3_bucket.fsx_reports.bucket
      LOG_LEVEL      = "INFO"
    }
  }

  tracing_config {
    mode = "Active"
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_cloudwatch_log_group.cost_reporting_logs
  ]

  tags = {
    Name = "${local.resource_prefix}-cost-reporting"
  }
}

# Lambda function for alert handling
resource "aws_lambda_function" "alert_handler" {
  filename         = data.archive_file.alert_handler_lambda.output_path
  function_name    = "${local.resource_prefix}-alert-handler"
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "alert_handler.lambda_handler"
  runtime         = var.lambda_runtime
  architectures   = [var.lambda_architecture]
  timeout         = 60  # Shorter timeout for alert handling
  memory_size     = 128 # Less memory needed for alert processing

  source_code_hash = data.archive_file.alert_handler_lambda.output_base64sha256

  environment {
    variables = {
      FSX_FILE_SYSTEM_ID = aws_fsx_openzfs_file_system.intelligent_tiering.id
      SNS_TOPIC_ARN      = aws_sns_topic.fsx_alerts.arn
      LOG_LEVEL          = "INFO"
    }
  }

  tracing_config {
    mode = "Active"
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_cloudwatch_log_group.alert_handler_logs
  ]

  tags = {
    Name = "${local.resource_prefix}-alert-handler"
  }
}

# ============================================================================
# EventBridge Rules for Scheduled Execution
# ============================================================================

# EventBridge rule for lifecycle policy checks
resource "aws_cloudwatch_event_rule" "lifecycle_policy_schedule" {
  name                = "${local.resource_prefix}-lifecycle-policy-schedule"
  description         = "Triggers FSx lifecycle policy analysis"
  schedule_expression = var.lifecycle_check_schedule
  state              = "ENABLED"

  tags = {
    Name = "${local.resource_prefix}-lifecycle-policy-schedule"
  }
}

# EventBridge rule for cost reporting
resource "aws_cloudwatch_event_rule" "cost_reporting_schedule" {
  name                = "${local.resource_prefix}-cost-reporting-schedule"
  description         = "Triggers FSx cost report generation"
  schedule_expression = var.cost_report_schedule
  state              = "ENABLED"

  tags = {
    Name = "${local.resource_prefix}-cost-reporting-schedule"
  }
}

# EventBridge targets for Lambda functions
resource "aws_cloudwatch_event_target" "lifecycle_policy_target" {
  rule      = aws_cloudwatch_event_rule.lifecycle_policy_schedule.name
  target_id = "LifecyclePolicyLambdaTarget"
  arn       = aws_lambda_function.lifecycle_policy.arn

  retry_policy {
    maximum_retry_attempts       = 3
    maximum_event_age_in_seconds = 3600
  }
}

resource "aws_cloudwatch_event_target" "cost_reporting_target" {
  rule      = aws_cloudwatch_event_rule.cost_reporting_schedule.name
  target_id = "CostReportingLambdaTarget"
  arn       = aws_lambda_function.cost_reporting.arn

  retry_policy {
    maximum_retry_attempts       = 3
    maximum_event_age_in_seconds = 3600
  }
}

# Lambda permissions for EventBridge
resource "aws_lambda_permission" "allow_eventbridge_lifecycle" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lifecycle_policy.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.lifecycle_policy_schedule.arn
}

resource "aws_lambda_permission" "allow_eventbridge_cost_reporting" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.cost_reporting.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.cost_reporting_schedule.arn
}

# ============================================================================
# CloudWatch Alarms
# ============================================================================

# FSx storage utilization alarm
resource "aws_cloudwatch_metric_alarm" "fsx_storage_utilization" {
  alarm_name          = "${local.resource_prefix}-fsx-storage-utilization-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "StorageUtilization"
  namespace           = "AWS/FSx"
  period              = 300
  statistic           = "Average"
  threshold           = var.storage_utilization_threshold
  alarm_description   = "FSx storage utilization is above ${var.storage_utilization_threshold}%"
  alarm_actions       = [aws_sns_topic.fsx_alerts.arn]
  ok_actions         = [aws_sns_topic.fsx_alerts.arn]
  treat_missing_data = "notBreaching"

  dimensions = {
    FileSystemId = aws_fsx_openzfs_file_system.intelligent_tiering.id
  }

  tags = {
    Name = "${local.resource_prefix}-fsx-storage-utilization-alarm"
  }
}

# FSx cache hit ratio alarm
resource "aws_cloudwatch_metric_alarm" "fsx_cache_hit_ratio" {
  alarm_name          = "${local.resource_prefix}-fsx-cache-hit-ratio-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "FileServerCacheHitRatio"
  namespace           = "AWS/FSx"
  period              = 300
  statistic           = "Average"
  threshold           = var.cache_hit_ratio_threshold
  alarm_description   = "FSx cache hit ratio is below ${var.cache_hit_ratio_threshold}%"
  alarm_actions       = [aws_sns_topic.fsx_alerts.arn]
  ok_actions         = [aws_sns_topic.fsx_alerts.arn]
  treat_missing_data = "notBreaching"

  dimensions = {
    FileSystemId = aws_fsx_openzfs_file_system.intelligent_tiering.id
  }

  tags = {
    Name = "${local.resource_prefix}-fsx-cache-hit-ratio-alarm"
  }
}

# Lambda error rate alarm
resource "aws_cloudwatch_metric_alarm" "lambda_error_rate" {
  alarm_name          = "${local.resource_prefix}-lambda-error-rate-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  threshold           = 5
  alarm_description   = "Lambda function error rate is too high"
  alarm_actions       = [aws_sns_topic.fsx_alerts.arn]
  treat_missing_data = "notBreaching"

  metric_query {
    id          = "error_rate"
    return_data = true
    expression  = "errors / invocations * 100"
    label       = "Error Rate (%)"
  }

  metric_query {
    id = "errors"
    metric {
      metric_name = "Errors"
      namespace   = "AWS/Lambda"
      period      = 300
      stat        = "Sum"
      dimensions = {
        FunctionName = aws_lambda_function.lifecycle_policy.function_name
      }
    }
  }

  metric_query {
    id = "invocations"
    metric {
      metric_name = "Invocations"
      namespace   = "AWS/Lambda"
      period      = 300
      stat        = "Sum"
      dimensions = {
        FunctionName = aws_lambda_function.lifecycle_policy.function_name
      }
    }
  }

  tags = {
    Name = "${local.resource_prefix}-lambda-error-rate-alarm"
  }
}

# SNS subscription for alert handler Lambda
resource "aws_sns_topic_subscription" "alert_handler_subscription" {
  topic_arn = aws_sns_topic.fsx_alerts.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.alert_handler.arn
}

# Lambda permission for SNS
resource "aws_lambda_permission" "allow_sns_invoke" {
  statement_id  = "AllowExecutionFromSNS"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.alert_handler.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.fsx_alerts.arn
}

# ============================================================================
# CloudWatch Dashboard
# ============================================================================

resource "aws_cloudwatch_dashboard" "fsx_lifecycle_dashboard" {
  dashboard_name = "${local.resource_prefix}-fsx-lifecycle-dashboard"

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
            ["AWS/FSx", "FileServerCacheHitRatio", "FileSystemId", aws_fsx_openzfs_file_system.intelligent_tiering.id],
            ["AWS/FSx", "StorageUtilization", "FileSystemId", aws_fsx_openzfs_file_system.intelligent_tiering.id],
            ["AWS/FSx", "NetworkThroughputUtilization", "FileSystemId", aws_fsx_openzfs_file_system.intelligent_tiering.id]
          ]
          period = 300
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "FSx Performance Metrics"
          yAxis = {
            left = {
              min = 0
              max = 100
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
            ["AWS/FSx", "DataReadBytes", "FileSystemId", aws_fsx_openzfs_file_system.intelligent_tiering.id],
            ["AWS/FSx", "DataWriteBytes", "FileSystemId", aws_fsx_openzfs_file_system.intelligent_tiering.id]
          ]
          period = 300
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "FSx Data Transfer"
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
            ["AWS/Lambda", "Duration", "FunctionName", aws_lambda_function.lifecycle_policy.function_name],
            ["AWS/Lambda", "Errors", "FunctionName", aws_lambda_function.lifecycle_policy.function_name],
            ["AWS/Lambda", "Invocations", "FunctionName", aws_lambda_function.lifecycle_policy.function_name]
          ]
          period = 300
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "Lambda Function Metrics"
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