# =============================================================================
# S3 Cross-Region Replication with Encryption and Access Controls
# =============================================================================
# This configuration creates S3 buckets in two regions with cross-region
# replication, KMS encryption, and comprehensive access controls.

# Data sources for account information
data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

# Random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

# =============================================================================
# KMS Keys for Encryption
# =============================================================================

# KMS key for source bucket encryption
resource "aws_kms_key" "source" {
  description             = "S3 Cross-Region Replication Source Key - ${var.project_name}"
  deletion_window_in_days = var.kms_deletion_window
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
        Sid    = "Allow S3 Service"
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "kms:ReEncrypt*",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })

  tags = merge(var.tags, {
    Name = "${var.project_name}-source-kms-key"
    Type = "source-encryption"
  })
}

# KMS alias for source key
resource "aws_kms_alias" "source" {
  name          = "alias/${var.project_name}-source-${random_string.suffix.result}"
  target_key_id = aws_kms_key.source.key_id
}

# KMS key for destination bucket encryption
resource "aws_kms_key" "destination" {
  provider = aws.destination

  description             = "S3 Cross-Region Replication Destination Key - ${var.project_name}"
  deletion_window_in_days = var.kms_deletion_window
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
        Sid    = "Allow S3 Service"
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "kms:ReEncrypt*",
          "kms:DescribeKey"
        ]
        Resource = "*"
      },
      {
        Sid    = "Allow Replication Role"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.replication.arn
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
          StringEquals = {
            "kms:ViaService" = "s3.${var.destination_region}.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = merge(var.tags, {
    Name = "${var.project_name}-destination-kms-key"
    Type = "destination-encryption"
  })
}

# KMS alias for destination key
resource "aws_kms_alias" "destination" {
  provider = aws.destination

  name          = "alias/${var.project_name}-destination-${random_string.suffix.result}"
  target_key_id = aws_kms_key.destination.key_id
}

# =============================================================================
# S3 Buckets Configuration
# =============================================================================

# Source S3 bucket
resource "aws_s3_bucket" "source" {
  bucket        = "${var.source_bucket_name}-${random_string.suffix.result}"
  force_destroy = var.force_destroy_buckets

  tags = merge(var.tags, {
    Name   = "${var.project_name}-source-bucket"
    Type   = "source"
    Region = var.source_region
  })
}

# Source bucket versioning
resource "aws_s3_bucket_versioning" "source" {
  bucket = aws_s3_bucket.source.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Source bucket server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "source" {
  bucket = aws_s3_bucket.source.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.source.arn
      sse_algorithm     = "aws:kms"
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

# Source bucket policy
resource "aws_s3_bucket_policy" "source" {
  bucket = aws_s3_bucket.source.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyUnencryptedObjectUploads"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.source.arn}/*"
        Condition = {
          StringNotEquals = {
            "s3:x-amz-server-side-encryption" = "aws:kms"
          }
        }
      },
      {
        Sid       = "DenyInsecureConnections"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.source.arn,
          "${aws_s3_bucket.source.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.source]
}

# Destination S3 bucket
resource "aws_s3_bucket" "destination" {
  provider = aws.destination

  bucket        = "${var.destination_bucket_name}-${random_string.suffix.result}"
  force_destroy = var.force_destroy_buckets

  tags = merge(var.tags, {
    Name   = "${var.project_name}-destination-bucket"
    Type   = "destination"
    Region = var.destination_region
  })
}

# Destination bucket versioning
resource "aws_s3_bucket_versioning" "destination" {
  provider = aws.destination

  bucket = aws_s3_bucket.destination.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Destination bucket server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "destination" {
  provider = aws.destination

  bucket = aws_s3_bucket.destination.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.destination.arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

# Destination bucket public access block
resource "aws_s3_bucket_public_access_block" "destination" {
  provider = aws.destination

  bucket = aws_s3_bucket.destination.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Destination bucket policy
resource "aws_s3_bucket_policy" "destination" {
  provider = aws.destination

  bucket = aws_s3_bucket.destination.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureConnections"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.destination.arn,
          "${aws_s3_bucket.destination.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      },
      {
        Sid    = "AllowReplicationRole"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.replication.arn
        }
        Action = [
          "s3:ReplicateObject",
          "s3:ReplicateDelete",
          "s3:ReplicateTags"
        ]
        Resource = "${aws_s3_bucket.destination.arn}/*"
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.destination]
}

# =============================================================================
# IAM Role for Cross-Region Replication
# =============================================================================

# IAM policy documents for replication role
data "aws_iam_policy_document" "replication_assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

data "aws_iam_policy_document" "replication" {
  # Allow replication configuration access on source bucket
  statement {
    effect = "Allow"
    actions = [
      "s3:GetReplicationConfiguration",
      "s3:ListBucket",
      "s3:GetBucketVersioning"
    ]
    resources = [aws_s3_bucket.source.arn]
  }

  # Allow reading objects from source bucket
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObjectVersionForReplication",
      "s3:GetObjectVersionAcl",
      "s3:GetObjectVersionTagging"
    ]
    resources = ["${aws_s3_bucket.source.arn}/*"]
  }

  # Allow writing objects to destination bucket
  statement {
    effect = "Allow"
    actions = [
      "s3:ReplicateObject",
      "s3:ReplicateDelete",
      "s3:ReplicateTags"
    ]
    resources = ["${aws_s3_bucket.destination.arn}/*"]
  }

  # KMS permissions for source key (decrypt)
  statement {
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:DescribeKey"
    ]
    resources = [aws_kms_key.source.arn]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["s3.${var.source_region}.amazonaws.com"]
    }
  }

  # KMS permissions for destination key (encrypt)
  statement {
    effect = "Allow"
    actions = [
      "kms:GenerateDataKey",
      "kms:Encrypt",
      "kms:DescribeKey"
    ]
    resources = [aws_kms_key.destination.arn]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["s3.${var.destination_region}.amazonaws.com"]
    }
  }
}

# IAM role for replication
resource "aws_iam_role" "replication" {
  name               = "${var.project_name}-replication-role-${random_string.suffix.result}"
  assume_role_policy = data.aws_iam_policy_document.replication_assume_role.json

  tags = merge(var.tags, {
    Name = "${var.project_name}-replication-role"
    Type = "replication"
  })
}

# IAM policy for replication
resource "aws_iam_policy" "replication" {
  name   = "${var.project_name}-replication-policy-${random_string.suffix.result}"
  policy = data.aws_iam_policy_document.replication.json

  tags = merge(var.tags, {
    Name = "${var.project_name}-replication-policy"
    Type = "replication"
  })
}

# Attach policy to role
resource "aws_iam_role_policy_attachment" "replication" {
  role       = aws_iam_role.replication.name
  policy_arn = aws_iam_policy.replication.arn
}

# =============================================================================
# S3 Cross-Region Replication Configuration
# =============================================================================

# S3 bucket replication configuration
resource "aws_s3_bucket_replication_configuration" "replication" {
  role   = aws_iam_role.replication.arn
  bucket = aws_s3_bucket.source.id

  rule {
    id     = "cross-region-replication"
    status = "Enabled"

    # Delete marker replication
    delete_marker_replication {
      status = "Enabled"
    }

    # Filter to replicate all objects
    filter {
      prefix = ""
    }

    # Destination configuration
    destination {
      bucket        = aws_s3_bucket.destination.arn
      storage_class = var.replication_storage_class

      # Encryption configuration for destination
      encryption_configuration {
        replica_kms_key_id = aws_kms_key.destination.arn
      }
    }

    # Source selection criteria (replicate KMS encrypted objects)
    source_selection_criteria {
      sse_kms_encrypted_objects {
        status = "Enabled"
      }
    }
  }

  depends_on = [aws_s3_bucket_versioning.source]
}

# =============================================================================
# CloudWatch Monitoring
# =============================================================================

# CloudWatch metric alarm for replication latency
resource "aws_cloudwatch_metric_alarm" "replication_latency" {
  count = var.enable_monitoring ? 1 : 0

  alarm_name          = "${var.project_name}-replication-latency-${random_string.suffix.result}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "ReplicationLatency"
  namespace           = "AWS/S3"
  period              = var.alarm_period
  statistic           = "Maximum"
  threshold           = var.replication_latency_threshold
  alarm_description   = "S3 replication latency is too high for ${var.project_name}"
  treat_missing_data  = "notBreaching"

  dimensions = {
    SourceBucket      = aws_s3_bucket.source.bucket
    DestinationBucket = aws_s3_bucket.destination.bucket
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-replication-latency-alarm"
    Type = "monitoring"
  })
}

# CloudWatch metric alarm for source bucket size (optional monitoring)
resource "aws_cloudwatch_metric_alarm" "source_bucket_size" {
  count = var.enable_monitoring && var.enable_size_monitoring ? 1 : 0

  alarm_name          = "${var.project_name}-source-bucket-size-${random_string.suffix.result}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "BucketSizeBytes"
  namespace           = "AWS/S3"
  period              = 86400 # Daily
  statistic           = "Average"
  threshold           = var.bucket_size_threshold
  alarm_description   = "Source S3 bucket size exceeds threshold for ${var.project_name}"
  treat_missing_data  = "notBreaching"

  dimensions = {
    BucketName  = aws_s3_bucket.source.bucket
    StorageType = "StandardStorage"
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-source-bucket-size-alarm"
    Type = "monitoring"
  })
}

# S3 bucket metrics configuration for replication monitoring
resource "aws_s3_bucket_metrics_configuration" "source_metrics" {
  count = var.enable_monitoring ? 1 : 0

  bucket = aws_s3_bucket.source.id
  name   = "ReplicationMetrics"

  filter {
    prefix = ""
  }
}