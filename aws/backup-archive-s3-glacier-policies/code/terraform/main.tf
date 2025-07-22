# Get current AWS account ID and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Merge default and additional tags
  common_tags = merge(var.default_tags, var.additional_tags, {
    Environment = var.environment
    Project     = var.project_name
  })
  
  # Generate unique bucket name
  bucket_name = "${var.project_name}-${var.environment}-${random_id.suffix.hex}"
  
  # Account ID for Glacier data retrieval policy
  account_id = data.aws_caller_identity.current.account_id
}

# ============================================================================
# S3 BUCKET CONFIGURATION
# ============================================================================

# Main S3 bucket for backup and archiving
resource "aws_s3_bucket" "backup_archive" {
  bucket        = local.bucket_name
  force_destroy = var.force_destroy

  tags = merge(local.common_tags, {
    Name        = local.bucket_name
    Description = "S3 bucket for backup and archive data with lifecycle policies"
    DataClass   = "Backup"
  })
}

# Enable versioning for backup integrity
resource "aws_s3_bucket_versioning" "backup_archive" {
  bucket = aws_s3_bucket.backup_archive.id
  
  versioning_configuration {
    status     = var.enable_versioning ? "Enabled" : "Disabled"
    mfa_delete = var.enable_mfa_delete ? "Enabled" : "Disabled"
  }
}

# Configure server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "backup_archive" {
  bucket = aws_s3_bucket.backup_archive.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# Block public access (security best practice)
resource "aws_s3_bucket_public_access_block" "backup_archive" {
  bucket = aws_s3_bucket.backup_archive.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ============================================================================
# S3 LIFECYCLE CONFIGURATION
# ============================================================================

# Comprehensive lifecycle policy for backup and archive data
resource "aws_s3_bucket_lifecycle_configuration" "backup_archive" {
  depends_on = [aws_s3_bucket_versioning.backup_archive]
  bucket     = aws_s3_bucket.backup_archive.id

  # Rule 1: Backup data with comprehensive 7-year retention strategy
  rule {
    id     = "backup-archive-strategy"
    status = "Enabled"

    filter {
      prefix = "backups/"
    }

    # Current version transitions
    transition {
      days          = var.backup_transition_to_ia_days
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = var.backup_transition_to_glacier_ir_days
      storage_class = "GLACIER_IR"
    }

    transition {
      days          = var.backup_transition_to_glacier_days
      storage_class = "GLACIER"
    }

    transition {
      days          = var.backup_transition_to_deep_archive_days
      storage_class = "DEEP_ARCHIVE"
    }

    # Non-current version transitions
    noncurrent_version_transition {
      noncurrent_days = 7
      storage_class   = "STANDARD_IA"
    }

    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "GLACIER"
    }

    # Non-current version expiration (8 years total retention)
    noncurrent_version_expiration {
      noncurrent_days = 2920
    }

    tags = {
      Rule        = "backup-archive-strategy"
      DataType    = "Backup"
      Retention   = "7-years"
    }
  }

  # Rule 2: Log data with shorter lifecycle and automatic deletion
  rule {
    id     = "logs-retention-policy"
    status = "Enabled"

    filter {
      prefix = "logs/"
    }

    # Current version transitions
    transition {
      days          = var.logs_transition_to_ia_days
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 30
      storage_class = "GLACIER_IR"
    }

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    # Automatic deletion after retention period
    expiration {
      days = var.logs_expiration_days
    }

    tags = {
      Rule        = "logs-retention-policy"
      DataType    = "Logs"
      Retention   = "7-years-with-deletion"
    }
  }

  # Rule 3: Document archives with tag-based filtering
  rule {
    id     = "documents-long-term-archive"
    status = "Enabled"

    filter {
      and {
        prefix = "documents/"
        
        tags = {
          DataClass = "Archive"
        }
      }
    }

    # Current version transitions
    transition {
      days          = var.documents_transition_to_glacier_ir_days
      storage_class = "GLACIER_IR"
    }

    transition {
      days          = var.documents_transition_to_glacier_days
      storage_class = "GLACIER"
    }

    transition {
      days          = var.documents_transition_to_deep_archive_days
      storage_class = "DEEP_ARCHIVE"
    }

    tags = {
      Rule        = "documents-long-term-archive"
      DataType    = "Documents"
      Retention   = "permanent"
    }
  }
}

# ============================================================================
# IAM ROLE FOR GLACIER OPERATIONS
# ============================================================================

# Trust policy for Glacier service
data "aws_iam_policy_document" "glacier_trust_policy" {
  statement {
    effect = "Allow"
    
    principals {
      type        = "Service"
      identifiers = ["glacier.amazonaws.com"]
    }
    
    actions = ["sts:AssumeRole"]
  }
}

# IAM role for Glacier operations
resource "aws_iam_role" "glacier_operations" {
  name               = "${var.project_name}-${var.environment}-glacier-operations-role"
  assume_role_policy = data.aws_iam_policy_document.glacier_trust_policy.json

  tags = merge(local.common_tags, {
    Name        = "${var.project_name}-${var.environment}-glacier-operations-role"
    Description = "IAM role for Glacier operations and lifecycle management"
    Service     = "Glacier"
  })
}

# Attach S3 access policy to the role
resource "aws_iam_role_policy_attachment" "glacier_s3_access" {
  role       = aws_iam_role.glacier_operations.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

# Custom policy for specific Glacier operations
resource "aws_iam_policy" "glacier_operations" {
  name        = "${var.project_name}-${var.environment}-glacier-operations-policy"
  description = "Custom policy for Glacier data retrieval operations"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "glacier:GetDataRetrievalPolicy",
          "glacier:SetDataRetrievalPolicy",
          "glacier:InitiateJob",
          "glacier:DescribeJob",
          "glacier:GetJobOutput",
          "glacier:ListJobs"
        ]
        Resource = "*"
      }
    ]
  })

  tags = local.common_tags
}

# Attach custom Glacier policy
resource "aws_iam_role_policy_attachment" "glacier_operations_custom" {
  role       = aws_iam_role.glacier_operations.name
  policy_arn = aws_iam_policy.glacier_operations.arn
}

# ============================================================================
# GLACIER DATA RETRIEVAL POLICY
# ============================================================================

# Glacier data retrieval policy for cost control
resource "aws_glacier_data_retrieval_policy" "cost_control" {
  account_id = local.account_id

  rules {
    strategy            = "BytesPerHour"
    bytes_per_hour      = var.glacier_retrieval_bytes_per_hour
  }

  depends_on = [aws_iam_role.glacier_operations]
}

# ============================================================================
# CLOUDWATCH MONITORING AND ALARMS
# ============================================================================

# CloudWatch log group for lifecycle transitions
resource "aws_cloudwatch_log_group" "lifecycle_transitions" {
  count             = var.enable_cost_monitoring ? 1 : 0
  name              = "/aws/s3/lifecycle-transitions"
  retention_in_days = 30

  tags = merge(local.common_tags, {
    Name        = "/aws/s3/lifecycle-transitions"
    Description = "Log group for S3 lifecycle transition events"
    Service     = "CloudWatch"
  })
}

# SNS topic for cost alerts (if email provided)
resource "aws_sns_topic" "cost_alerts" {
  count = var.enable_cost_monitoring && var.notification_email != "" ? 1 : 0
  name  = "${var.project_name}-${var.environment}-cost-alerts"

  tags = merge(local.common_tags, {
    Name        = "${var.project_name}-${var.environment}-cost-alerts"
    Description = "SNS topic for backup archive cost notifications"
    Service     = "SNS"
  })
}

# SNS topic subscription for email notifications
resource "aws_sns_topic_subscription" "cost_alerts_email" {
  count     = var.enable_cost_monitoring && var.notification_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.cost_alerts[0].arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# CloudWatch alarm for S3 storage costs
resource "aws_cloudwatch_metric_alarm" "storage_cost_alarm" {
  count               = var.enable_cost_monitoring ? 1 : 0
  alarm_name          = "${var.project_name}-${var.environment}-s3-cost-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "EstimatedCharges"
  namespace           = "AWS/Billing"
  period              = "86400"
  statistic           = "Maximum"
  threshold           = var.cost_threshold_usd
  alarm_description   = "This metric monitors S3 storage costs"
  alarm_actions       = var.notification_email != "" ? [aws_sns_topic.cost_alerts[0].arn] : []

  dimensions = {
    Currency    = "USD"
    ServiceName = "AmazonS3"
  }

  tags = merge(local.common_tags, {
    Name        = "${var.project_name}-${var.environment}-s3-cost-alarm"
    Description = "CloudWatch alarm for S3 storage cost monitoring"
    Service     = "CloudWatch"
  })
}

# ============================================================================
# S3 BUCKET NOTIFICATION (Optional for monitoring)
# ============================================================================

# S3 bucket notification configuration for lifecycle events
resource "aws_s3_bucket_notification" "backup_archive_notifications" {
  count  = var.enable_cost_monitoring ? 1 : 0
  bucket = aws_s3_bucket.backup_archive.id

  # Note: Additional configuration would be needed for actual event notifications
  # This is a placeholder for future CloudWatch Events integration

  depends_on = [aws_s3_bucket.backup_archive]
}