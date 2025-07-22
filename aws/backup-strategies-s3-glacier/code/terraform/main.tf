# main.tf
# Main Terraform configuration for backup strategies with S3 and Glacier

# Data sources
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Common naming and tagging
  name_suffix = random_id.suffix.hex
  backup_bucket_name = "${var.backup_bucket_prefix}-${var.environment}-${local.name_suffix}"
  dr_bucket_name = "${var.backup_bucket_prefix}-dr-${var.environment}-${local.name_suffix}"
  
  # Common tags
  common_tags = merge(var.tags, {
    Project     = "backup-strategies-s3-glacier"
    Environment = var.environment
    Owner       = var.owner
    ManagedBy   = "terraform"
  })
}

# Primary S3 bucket for backups
resource "aws_s3_bucket" "backup_bucket" {
  bucket = local.backup_bucket_name

  tags = merge(local.common_tags, {
    Name = "Primary Backup Bucket"
    Type = "BackupStorage"
  })
}

# S3 bucket versioning configuration
resource "aws_s3_bucket_versioning" "backup_bucket_versioning" {
  bucket = aws_s3_bucket.backup_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "backup_bucket_encryption" {
  bucket = aws_s3_bucket.backup_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# S3 bucket public access block
resource "aws_s3_bucket_public_access_block" "backup_bucket_pab" {
  bucket = aws_s3_bucket.backup_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket lifecycle configuration
resource "aws_s3_bucket_lifecycle_configuration" "backup_bucket_lifecycle" {
  bucket = aws_s3_bucket.backup_bucket.id

  rule {
    id     = "backup-lifecycle-rule"
    status = "Enabled"

    # Current version transitions
    transition {
      days          = var.lifecycle_transition_ia_days
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = var.lifecycle_transition_glacier_days
      storage_class = "GLACIER"
    }

    transition {
      days          = var.lifecycle_transition_deep_archive_days
      storage_class = "DEEP_ARCHIVE"
    }

    # Noncurrent version transitions
    noncurrent_version_transition {
      noncurrent_days = var.lifecycle_transition_ia_days
      storage_class   = "STANDARD_IA"
    }

    noncurrent_version_transition {
      noncurrent_days = var.lifecycle_transition_glacier_days
      storage_class   = "GLACIER"
    }

    # Noncurrent version expiration
    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_expiration_days
    }
  }
}

# S3 Intelligent Tiering configuration (optional)
resource "aws_s3_bucket_intelligent_tiering_configuration" "backup_bucket_intelligent_tiering" {
  count  = var.enable_intelligent_tiering ? 1 : 0
  bucket = aws_s3_bucket.backup_bucket.id
  name   = "backup-intelligent-tiering"

  status = "Enabled"

  filter {
    prefix = "intelligent-tier/"
  }

  tiering {
    access_tier = "ARCHIVE_ACCESS"
    days        = 1
  }

  tiering {
    access_tier = "DEEP_ARCHIVE_ACCESS"
    days        = 90
  }
}

# Disaster Recovery S3 bucket (for cross-region replication)
resource "aws_s3_bucket" "dr_bucket" {
  count    = var.enable_cross_region_replication ? 1 : 0
  provider = aws.dr
  bucket   = local.dr_bucket_name

  tags = merge(local.common_tags, {
    Name    = "Disaster Recovery Backup Bucket"
    Type    = "BackupStorage"
    Purpose = "DisasterRecovery"
  })
}

# DR bucket versioning
resource "aws_s3_bucket_versioning" "dr_bucket_versioning" {
  count    = var.enable_cross_region_replication ? 1 : 0
  provider = aws.dr
  bucket   = aws_s3_bucket.dr_bucket[0].id
  
  versioning_configuration {
    status = "Enabled"
  }
}

# DR bucket encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "dr_bucket_encryption" {
  count    = var.enable_cross_region_replication ? 1 : 0
  provider = aws.dr
  bucket   = aws_s3_bucket.dr_bucket[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# IAM role for S3 cross-region replication
resource "aws_iam_role" "replication_role" {
  count = var.enable_cross_region_replication ? 1 : 0
  name  = "s3-replication-role-${local.name_suffix}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "S3 Replication Role"
  })
}

# IAM policy for S3 cross-region replication
resource "aws_iam_role_policy" "replication_policy" {
  count = var.enable_cross_region_replication ? 1 : 0
  name  = "ReplicationPolicy"
  role  = aws_iam_role.replication_role[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObjectVersionForReplication",
          "s3:GetObjectVersionAcl"
        ]
        Resource = "${aws_s3_bucket.backup_bucket.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = aws_s3_bucket.backup_bucket.arn
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ReplicateObject",
          "s3:ReplicateDelete"
        ]
        Resource = "${aws_s3_bucket.dr_bucket[0].arn}/*"
      }
    ]
  })
}

# S3 bucket replication configuration
resource "aws_s3_bucket_replication_configuration" "backup_bucket_replication" {
  count      = var.enable_cross_region_replication ? 1 : 0
  depends_on = [aws_s3_bucket_versioning.backup_bucket_versioning]

  role   = aws_iam_role.replication_role[0].arn
  bucket = aws_s3_bucket.backup_bucket.id

  rule {
    id     = "backup-replication-rule"
    status = "Enabled"

    priority = 1

    filter {
      prefix = "backups/"
    }

    destination {
      bucket        = aws_s3_bucket.dr_bucket[0].arn
      storage_class = "STANDARD_IA"
    }
  }
}

# SNS topic for backup notifications
resource "aws_sns_topic" "backup_notifications" {
  name = "backup-notifications-${local.name_suffix}"

  tags = merge(local.common_tags, {
    Name = "Backup Notifications Topic"
  })
}

# SNS topic subscription (email)
resource "aws_sns_topic_subscription" "backup_email_notification" {
  count     = var.notification_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.backup_notifications.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# IAM role for Lambda backup function
resource "aws_iam_role" "backup_lambda_role" {
  name = "backup-lambda-role-${local.name_suffix}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "Backup Lambda Execution Role"
  })
}

# IAM policy for Lambda backup function
resource "aws_iam_role_policy" "backup_lambda_policy" {
  name = "BackupExecutionPolicy"
  role = aws_iam_role.backup_lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetBucketLocation",
          "s3:GetBucketVersioning",
          "s3:RestoreObject"
        ]
        Resource = [
          aws_s3_bucket.backup_bucket.arn,
          "${aws_s3_bucket.backup_bucket.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.backup_notifications.arn
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:${data.aws_partition.current.partition}:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*"
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

# Attach basic Lambda execution role
resource "aws_iam_role_policy_attachment" "backup_lambda_basic_execution" {
  role       = aws_iam_role.backup_lambda_role.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# CloudWatch log group for Lambda function
resource "aws_cloudwatch_log_group" "backup_lambda_logs" {
  name              = "/aws/lambda/backup-orchestrator-${local.name_suffix}"
  retention_in_days = var.cloudwatch_log_retention_days

  tags = merge(local.common_tags, {
    Name = "Backup Lambda Logs"
  })
}

# Create Lambda deployment package
data "archive_file" "backup_lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/backup_function.zip"
  
  source {
    content  = file("${path.module}/lambda_function.py")
    filename = "lambda_function.py"
  }
}

# Lambda function for backup orchestration
resource "aws_lambda_function" "backup_orchestrator" {
  depends_on = [
    aws_iam_role_policy_attachment.backup_lambda_basic_execution,
    aws_cloudwatch_log_group.backup_lambda_logs,
  ]

  filename         = data.archive_file.backup_lambda_zip.output_path
  function_name    = "backup-orchestrator-${local.name_suffix}"
  role            = aws_iam_role.backup_lambda_role.arn
  handler         = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.backup_lambda_zip.output_base64sha256
  runtime         = "python3.9"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size

  environment {
    variables = {
      BACKUP_BUCKET   = aws_s3_bucket.backup_bucket.id
      SNS_TOPIC_ARN   = aws_sns_topic.backup_notifications.arn
    }
  }

  tags = merge(local.common_tags, {
    Name = "Backup Orchestrator Function"
  })
}

# EventBridge rule for daily backups
resource "aws_cloudwatch_event_rule" "daily_backup" {
  name                = "daily-backup-${local.name_suffix}"
  description         = "Daily backup at 2 AM UTC"
  schedule_expression = var.backup_schedule_daily

  tags = merge(local.common_tags, {
    Name = "Daily Backup Schedule"
  })
}

# EventBridge rule for weekly backups
resource "aws_cloudwatch_event_rule" "weekly_backup" {
  name                = "weekly-backup-${local.name_suffix}"
  description         = "Weekly full backup on Sunday at 1 AM UTC"
  schedule_expression = var.backup_schedule_weekly

  tags = merge(local.common_tags, {
    Name = "Weekly Backup Schedule"
  })
}

# EventBridge target for daily backup
resource "aws_cloudwatch_event_target" "daily_backup_target" {
  rule      = aws_cloudwatch_event_rule.daily_backup.name
  target_id = "DailyBackupTarget"
  arn       = aws_lambda_function.backup_orchestrator.arn

  input = jsonencode({
    backup_type   = "incremental"
    source_prefix = "daily/"
  })
}

# EventBridge target for weekly backup
resource "aws_cloudwatch_event_target" "weekly_backup_target" {
  rule      = aws_cloudwatch_event_rule.weekly_backup.name
  target_id = "WeeklyBackupTarget"
  arn       = aws_lambda_function.backup_orchestrator.arn

  input = jsonencode({
    backup_type   = "full"
    source_prefix = "weekly/"
  })
}

# Lambda permission for daily backup EventBridge rule
resource "aws_lambda_permission" "allow_daily_backup_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridgeDaily"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.backup_orchestrator.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.daily_backup.arn
}

# Lambda permission for weekly backup EventBridge rule
resource "aws_lambda_permission" "allow_weekly_backup_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridgeWeekly"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.backup_orchestrator.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.weekly_backup.arn
}

# CloudWatch alarm for backup failures
resource "aws_cloudwatch_metric_alarm" "backup_failure_alarm" {
  alarm_name          = "backup-failure-alarm-${local.name_suffix}"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "BackupSuccess"
  namespace           = "BackupStrategy"
  period              = "300"
  statistic           = "Sum"
  threshold           = var.backup_alarm_threshold_failure
  alarm_description   = "This metric monitors backup failures"
  alarm_actions       = [aws_sns_topic.backup_notifications.arn]

  tags = merge(local.common_tags, {
    Name = "Backup Failure Alarm"
  })
}

# CloudWatch alarm for backup duration
resource "aws_cloudwatch_metric_alarm" "backup_duration_alarm" {
  alarm_name          = "backup-duration-alarm-${local.name_suffix}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "BackupDuration"
  namespace           = "BackupStrategy"
  period              = "300"
  statistic           = "Average"
  threshold           = var.backup_alarm_threshold_duration
  alarm_description   = "This metric monitors backup duration"
  alarm_actions       = [aws_sns_topic.backup_notifications.arn]

  tags = merge(local.common_tags, {
    Name = "Backup Duration Alarm"
  })
}

# CloudWatch dashboard for backup monitoring
resource "aws_cloudwatch_dashboard" "backup_dashboard" {
  dashboard_name = "backup-strategy-dashboard-${local.name_suffix}"

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
            ["BackupStrategy", "BackupSuccess"],
            [".", "BackupDuration"]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
          title  = "Backup Metrics"
        }
      }
    ]
  })
}