# Amazon QLDB ACID-Compliant Distributed Database Infrastructure
# This configuration creates a complete QLDB-based financial ledger system
# with real-time streaming, S3 exports, and cryptographic verification

# Data source for current AWS caller identity
data "aws_caller_identity" "current" {}

# Data source for current AWS region
data "aws_region" "current" {}

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  # Common resource naming convention
  name_prefix = "${var.application_name}-${var.environment}"
  
  # Common tags applied to all resources
  common_tags = merge(var.tags, {
    Environment     = var.environment
    Application     = var.application_name
    ManagedBy      = "terraform"
    Purpose        = "acid-compliant-ledger"
    ComplianceType = "financial-services"
  })
}

# ============================================================================
# IAM Role and Policies for QLDB Operations
# ============================================================================

# IAM role that allows QLDB to access S3 and Kinesis services
resource "aws_iam_role" "qldb_stream_role" {
  name               = "${local.name_prefix}-qldb-stream-role-${random_id.suffix.hex}"
  description        = "IAM role for QLDB journal streaming and S3 exports"
  assume_role_policy = data.aws_iam_policy_document.qldb_trust_policy.json

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-qldb-stream-role"
  })
}

# Trust policy allowing QLDB service to assume the role
data "aws_iam_policy_document" "qldb_trust_policy" {
  statement {
    effect = "Allow"
    
    principals {
      type        = "Service"
      identifiers = ["qldb.amazonaws.com"]
    }
    
    actions = ["sts:AssumeRole"]
    
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

# IAM policy for S3 and Kinesis access
data "aws_iam_policy_document" "qldb_permissions_policy" {
  # S3 permissions for journal exports
  statement {
    sid    = "S3ExportPermissions"
    effect = "Allow"
    
    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:ListBucket",
      "s3:GetBucketLocation"
    ]
    
    resources = [
      aws_s3_bucket.journal_exports.arn,
      "${aws_s3_bucket.journal_exports.arn}/*"
    ]
  }
  
  # Kinesis permissions for journal streaming
  statement {
    sid    = "KinesisStreamPermissions"
    effect = "Allow"
    
    actions = [
      "kinesis:PutRecord",
      "kinesis:PutRecords",
      "kinesis:DescribeStream",
      "kinesis:DescribeStreamSummary"
    ]
    
    resources = [aws_kinesis_stream.journal_stream.arn]
  }
}

# Attach the permissions policy to the IAM role
resource "aws_iam_role_policy" "qldb_stream_policy" {
  name   = "${local.name_prefix}-qldb-stream-policy"
  role   = aws_iam_role.qldb_stream_role.id
  policy = data.aws_iam_policy_document.qldb_permissions_policy.json
}

# ============================================================================
# S3 Bucket for Journal Exports
# ============================================================================

# S3 bucket for storing QLDB journal exports
resource "aws_s3_bucket" "journal_exports" {
  bucket        = "${local.name_prefix}-journal-exports-${random_id.suffix.hex}"
  force_destroy = var.environment != "prod" # Prevent accidental deletion in production

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-journal-exports"
    DataType    = "financial-journals"
    Retention   = "regulatory-compliance"
  })
}

# Configure S3 bucket versioning for audit trail protection
resource "aws_s3_bucket_versioning" "journal_exports" {
  bucket = aws_s3_bucket.journal_exports.id
  
  versioning_configuration {
    status = var.s3_versioning_enabled ? "Enabled" : "Suspended"
  }
}

# Configure S3 bucket server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "journal_exports" {
  bucket = aws_s3_bucket.journal_exports.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    
    bucket_key_enabled = true
  }
}

# Block all public access to the S3 bucket
resource "aws_s3_bucket_public_access_block" "journal_exports" {
  bucket = aws_s3_bucket.journal_exports.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket policy to restrict access to QLDB role only
resource "aws_s3_bucket_policy" "journal_exports" {
  bucket = aws_s3_bucket.journal_exports.id
  policy = data.aws_iam_policy_document.s3_bucket_policy.json
}

data "aws_iam_policy_document" "s3_bucket_policy" {
  statement {
    sid    = "RestrictToQLDBRole"
    effect = "Allow"
    
    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.qldb_stream_role.arn]
    }
    
    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:ListBucket"
    ]
    
    resources = [
      aws_s3_bucket.journal_exports.arn,
      "${aws_s3_bucket.journal_exports.arn}/*"
    ]
  }
  
  statement {
    sid    = "DenyInsecureConnections"
    effect = "Deny"
    
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    
    actions = ["s3:*"]
    
    resources = [
      aws_s3_bucket.journal_exports.arn,
      "${aws_s3_bucket.journal_exports.arn}/*"
    ]
    
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

# Configure S3 lifecycle management for cost optimization
resource "aws_s3_bucket_lifecycle_configuration" "journal_exports" {
  bucket = aws_s3_bucket.journal_exports.id

  rule {
    id     = "journal_lifecycle"
    status = "Enabled"

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    transition {
      days          = 365
      storage_class = "DEEP_ARCHIVE"
    }

    # Retain data for regulatory compliance (7 years)
    expiration {
      days = 2555
    }
  }
}

# ============================================================================
# Amazon Kinesis Data Stream for Real-time Journal Streaming
# ============================================================================

# Kinesis stream for real-time QLDB journal data
resource "aws_kinesis_stream" "journal_stream" {
  name        = "${local.name_prefix}-journal-stream-${random_id.suffix.hex}"
  shard_count = var.kinesis_shard_count

  # Retention period for data replay capabilities
  retention_period = var.kinesis_retention_hours

  # Enable server-side encryption
  encryption_type = "KMS"
  kms_key_id      = "alias/aws/kinesis"

  # Shard level metrics for monitoring
  shard_level_metrics = [
    "IncomingRecords",
    "OutgoingRecords",
  ]

  tags = merge(local.common_tags, {
    Name     = "${local.name_prefix}-journal-stream"
    DataType = "financial-journal-stream"
    Purpose  = "real-time-processing"
  })
}

# ============================================================================
# Amazon QLDB Ledger
# ============================================================================

# QLDB ledger for ACID-compliant transaction storage
resource "aws_qldb_ledger" "financial_ledger" {
  name                = "${local.name_prefix}-ledger-${random_id.suffix.hex}"
  permissions_mode    = "STANDARD"
  deletion_protection = var.deletion_protection

  tags = merge(local.common_tags, {
    Name             = "${local.name_prefix}-financial-ledger"
    DataClassification = "highly-confidential"
    ComplianceScope    = "financial-regulations"
    ACIDCompliance     = "enabled"
  })
}

# ============================================================================
# QLDB Journal Streaming Configuration
# ============================================================================

# Configure journal streaming from QLDB to Kinesis
resource "aws_qldb_stream" "journal_stream" {
  ledger_name      = aws_qldb_ledger.financial_ledger.name
  role_arn         = aws_iam_role.qldb_stream_role.arn
  stream_name      = "${local.name_prefix}-journal-stream"
  inclusive_start_time = var.stream_start_time

  kinesis_configuration {
    aggregation_enabled = true
    stream_arn         = aws_kinesis_stream.journal_stream.arn
  }

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-qldb-stream"
    Purpose = "real-time-audit-trail"
  })

  depends_on = [
    aws_iam_role_policy.qldb_stream_policy,
    aws_kinesis_stream.journal_stream
  ]
}

# ============================================================================
# CloudWatch Log Group for QLDB Operations (Optional)
# ============================================================================

# CloudWatch log group for QLDB operation logs
resource "aws_cloudwatch_log_group" "qldb_operations" {
  name              = "/aws/qldb/${aws_qldb_ledger.financial_ledger.name}"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-qldb-logs"
    Purpose = "operational-monitoring"
  })
}

# ============================================================================
# CloudWatch Alarms for Monitoring
# ============================================================================

# CloudWatch alarm for QLDB read I/O usage
resource "aws_cloudwatch_metric_alarm" "qldb_read_io" {
  alarm_name          = "${local.name_prefix}-qldb-read-io-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "ReadIOs"
  namespace           = "AWS/QLDB"
  period              = "300"
  statistic           = "Sum"
  threshold           = var.read_io_alarm_threshold
  alarm_description   = "This metric monitors QLDB read I/O usage"
  alarm_actions       = var.alarm_notification_arn != "" ? [var.alarm_notification_arn] : []

  dimensions = {
    LedgerName = aws_qldb_ledger.financial_ledger.name
  }

  tags = local.common_tags
}

# CloudWatch alarm for QLDB write I/O usage
resource "aws_cloudwatch_metric_alarm" "qldb_write_io" {
  alarm_name          = "${local.name_prefix}-qldb-write-io-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "WriteIOs"
  namespace           = "AWS/QLDB"
  period              = "300"
  statistic           = "Sum"
  threshold           = var.write_io_alarm_threshold
  alarm_description   = "This metric monitors QLDB write I/O usage"
  alarm_actions       = var.alarm_notification_arn != "" ? [var.alarm_notification_arn] : []

  dimensions = {
    LedgerName = aws_qldb_ledger.financial_ledger.name
  }

  tags = local.common_tags
}

# CloudWatch alarm for Kinesis stream incoming records
resource "aws_cloudwatch_metric_alarm" "kinesis_incoming_records" {
  alarm_name          = "${local.name_prefix}-kinesis-incoming-records-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "3"
  metric_name         = "IncomingRecords"
  namespace           = "AWS/Kinesis"
  period              = "300"
  statistic           = "Sum"
  threshold           = "1"
  alarm_description   = "This metric monitors Kinesis stream health"
  treat_missing_data  = "breaching"
  alarm_actions       = var.alarm_notification_arn != "" ? [var.alarm_notification_arn] : []

  dimensions = {
    StreamName = aws_kinesis_stream.journal_stream.name
  }

  tags = local.common_tags
}