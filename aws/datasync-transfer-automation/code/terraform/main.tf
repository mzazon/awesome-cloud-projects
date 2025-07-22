# Data sources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  # Resource naming
  suffix = random_id.suffix.hex
  source_bucket_name = var.source_bucket_name != "" ? var.source_bucket_name : "${var.project_name}-source-${local.suffix}"
  destination_bucket_name = var.destination_bucket_name != "" ? var.destination_bucket_name : "${var.project_name}-dest-${local.suffix}"
  
  # Common tags
  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Recipe      = "datasync-data-transfer-automation"
    },
    var.additional_tags
  )
}

# ============================================================================
# S3 Buckets
# ============================================================================

# Source S3 Bucket
resource "aws_s3_bucket" "source" {
  bucket = local.source_bucket_name
  tags   = local.common_tags
}

# Source bucket versioning
resource "aws_s3_bucket_versioning" "source" {
  bucket = aws_s3_bucket.source.id
  versioning_configuration {
    status = var.enable_bucket_versioning ? "Enabled" : "Disabled"
  }
}

# Source bucket encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "source" {
  count  = var.enable_bucket_encryption ? 1 : 0
  bucket = aws_s3_bucket.source.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
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

# Destination S3 Bucket
resource "aws_s3_bucket" "destination" {
  bucket = local.destination_bucket_name
  tags   = local.common_tags
}

# Destination bucket versioning
resource "aws_s3_bucket_versioning" "destination" {
  bucket = aws_s3_bucket.destination.id
  versioning_configuration {
    status = var.enable_bucket_versioning ? "Enabled" : "Disabled"
  }
}

# Destination bucket encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "destination" {
  count  = var.enable_bucket_encryption ? 1 : 0
  bucket = aws_s3_bucket.destination.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# Destination bucket public access block
resource "aws_s3_bucket_public_access_block" "destination" {
  bucket = aws_s3_bucket.destination.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ============================================================================
# Sample Data (Optional)
# ============================================================================

# Sample objects for testing
resource "aws_s3_object" "sample_file_root" {
  count   = var.create_sample_data ? 1 : 0
  bucket  = aws_s3_bucket.source.id
  key     = "sample-file.txt"
  content = "Sample data for DataSync transfer - root level"
  tags    = local.common_tags
}

resource "aws_s3_object" "sample_file_folder1" {
  count   = var.create_sample_data ? 1 : 0
  bucket  = aws_s3_bucket.source.id
  key     = "folder1/sample-file.txt"
  content = "Sample data for DataSync transfer - folder1"
  tags    = local.common_tags
}

resource "aws_s3_object" "sample_file_folder2" {
  count   = var.create_sample_data ? 1 : 0
  bucket  = aws_s3_bucket.source.id
  key     = "folder2/sample-file.txt"
  content = "Sample data for DataSync transfer - folder2"
  tags    = local.common_tags
}

# ============================================================================
# IAM Roles and Policies
# ============================================================================

# DataSync service role
resource "aws_iam_role" "datasync_service_role" {
  name = "${var.project_name}-datasync-service-role-${local.suffix}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "datasync.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = local.common_tags
}

# DataSync S3 access policy
resource "aws_iam_role_policy" "datasync_s3_policy" {
  name = "DataSyncS3Policy"
  role = aws_iam_role.datasync_service_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetBucketLocation",
          "s3:ListBucket",
          "s3:ListBucketMultipartUploads"
        ]
        Resource = [
          aws_s3_bucket.source.arn,
          aws_s3_bucket.destination.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectTagging",
          "s3:GetObjectVersion",
          "s3:GetObjectVersionTagging",
          "s3:PutObject",
          "s3:PutObjectTagging",
          "s3:DeleteObject",
          "s3:AbortMultipartUpload",
          "s3:ListMultipartUploadParts"
        ]
        Resource = [
          "${aws_s3_bucket.source.arn}/*",
          "${aws_s3_bucket.destination.arn}/*"
        ]
      }
    ]
  })
}

# EventBridge role for DataSync execution
resource "aws_iam_role" "eventbridge_datasync_role" {
  count = var.enable_scheduled_execution ? 1 : 0
  name  = "${var.project_name}-eventbridge-datasync-role-${local.suffix}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = local.common_tags
}

# EventBridge DataSync execution policy
resource "aws_iam_role_policy" "eventbridge_datasync_policy" {
  count = var.enable_scheduled_execution ? 1 : 0
  name  = "DataSyncExecutionPolicy"
  role  = aws_iam_role.eventbridge_datasync_role[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "datasync:StartTaskExecution"
        ]
        Resource = aws_datasync_task.s3_to_s3.arn
      }
    ]
  })
}

# ============================================================================
# CloudWatch Resources
# ============================================================================

# CloudWatch log group for DataSync
resource "aws_cloudwatch_log_group" "datasync" {
  name              = "/aws/datasync/${var.datasync_task_name}-${local.suffix}"
  retention_in_days = var.cloudwatch_log_retention_days
  tags              = local.common_tags
}

# CloudWatch dashboard for DataSync monitoring
resource "aws_cloudwatch_dashboard" "datasync_monitoring" {
  count          = var.enable_cloudwatch_dashboard ? 1 : 0
  dashboard_name = "DataSync-Monitoring-${local.suffix}"

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
            ["AWS/DataSync", "BytesTransferred", "TaskArn", aws_datasync_task.s3_to_s3.arn],
            ["AWS/DataSync", "FilesTransferred", "TaskArn", aws_datasync_task.s3_to_s3.arn]
          ]
          period = 300
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "DataSync Transfer Metrics"
          view   = "timeSeries"
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
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["AWS/DataSync", "FilesVerified", "TaskArn", aws_datasync_task.s3_to_s3.arn],
            ["AWS/DataSync", "FilesPrepared", "TaskArn", aws_datasync_task.s3_to_s3.arn]
          ]
          period = 300
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "DataSync File Processing Metrics"
          view   = "timeSeries"
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

# ============================================================================
# DataSync Resources
# ============================================================================

# DataSync source location (S3)
resource "aws_datasync_location_s3" "source" {
  s3_bucket_arn = aws_s3_bucket.source.arn
  subdirectory  = "/"

  s3_config {
    bucket_access_role_arn = aws_iam_role.datasync_service_role.arn
  }

  tags = local.common_tags
}

# DataSync destination location (S3)
resource "aws_datasync_location_s3" "destination" {
  s3_bucket_arn = aws_s3_bucket.destination.arn
  subdirectory  = "/"

  s3_config {
    bucket_access_role_arn = aws_iam_role.datasync_service_role.arn
  }

  tags = local.common_tags
}

# DataSync task
resource "aws_datasync_task" "s3_to_s3" {
  destination_location_arn = aws_datasync_location_s3.destination.arn
  name                     = "${var.datasync_task_name}-${local.suffix}"
  source_location_arn      = aws_datasync_location_s3.source.arn

  # Task options for optimal performance and reliability
  options {
    bytes_per_second                = var.datasync_bandwidth_throttle
    log_level                      = var.datasync_log_level
    overwrite_mode                 = var.datasync_overwrite_mode
    posix_permissions              = "NONE"
    preserve_deleted_files         = "PRESERVE"
    preserve_devices               = "NONE"
    task_queueing                  = "ENABLED"
    transfer_mode                  = var.datasync_transfer_mode
    uid                           = "NONE"
    gid                           = "NONE"
    verify_mode                   = var.datasync_verify_mode
  }

  # CloudWatch logging configuration
  cloudwatch_log_group_arn = aws_cloudwatch_log_group.datasync.arn

  tags = local.common_tags

  depends_on = [
    aws_iam_role_policy.datasync_s3_policy
  ]
}

# Task reporting configuration
resource "aws_datasync_task_report" "main" {
  count   = var.enable_task_reporting ? 1 : 0
  task_arn = aws_datasync_task.s3_to_s3.arn

  s3_destination {
    bucket_arn   = aws_s3_bucket.destination.arn
    subdirectory = "datasync-reports"
    
    s3_config {
      bucket_access_role_arn = aws_iam_role.datasync_service_role.arn
    }
  }

  report_level = var.task_report_level
}

# ============================================================================
# EventBridge Scheduled Execution
# ============================================================================

# EventBridge rule for scheduled execution
resource "aws_cloudwatch_event_rule" "datasync_schedule" {
  count               = var.enable_scheduled_execution ? 1 : 0
  name                = "DataSyncScheduledExecution-${local.suffix}"
  description         = "Scheduled execution of DataSync task"
  schedule_expression = var.schedule_expression
  tags                = local.common_tags
}

# EventBridge target for DataSync task
resource "aws_cloudwatch_event_target" "datasync_task" {
  count     = var.enable_scheduled_execution ? 1 : 0
  rule      = aws_cloudwatch_event_rule.datasync_schedule[0].name
  target_id = "DataSyncTaskTarget"
  arn       = aws_datasync_task.s3_to_s3.arn
  role_arn  = aws_iam_role.eventbridge_datasync_role[0].arn
}