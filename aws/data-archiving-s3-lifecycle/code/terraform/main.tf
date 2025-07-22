# Data sources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# S3 Bucket for data archiving demonstration
resource "aws_s3_bucket" "data_archiving_bucket" {
  bucket        = "${var.bucket_name_prefix}-${random_string.suffix.result}"
  force_destroy = true

  tags = {
    Name        = "Data Archiving Demo Bucket"
    Purpose     = "Demonstrate S3 lifecycle policies for data archiving"
    DataTypes   = "documents,logs,backups,media"
  }
}

# S3 Bucket Versioning
resource "aws_s3_bucket_versioning" "bucket_versioning" {
  count  = var.enable_versioning ? 1 : 0
  bucket = aws_s3_bucket.data_archiving_bucket.id
  
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 Bucket Server-Side Encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "bucket_encryption" {
  count  = var.enable_server_side_encryption ? 1 : 0
  bucket = aws_s3_bucket.data_archiving_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# S3 Bucket Public Access Block
resource "aws_s3_bucket_public_access_block" "bucket_pab" {
  bucket = aws_s3_bucket.data_archiving_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 Lifecycle Configuration
resource "aws_s3_bucket_lifecycle_configuration" "bucket_lifecycle" {
  bucket = aws_s3_bucket.data_archiving_bucket.id

  # Document archiving lifecycle rule
  rule {
    id     = "DocumentArchiving"
    status = "Enabled"

    filter {
      prefix = "documents/"
    }

    transition {
      days          = var.document_ia_transition_days
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = var.document_glacier_transition_days
      storage_class = "GLACIER"
    }

    transition {
      days          = var.document_deep_archive_transition_days
      storage_class = "DEEP_ARCHIVE"
    }

    # Handle versioned objects
    noncurrent_version_transition {
      noncurrent_days = var.document_ia_transition_days
      storage_class   = "STANDARD_IA"
    }

    noncurrent_version_transition {
      noncurrent_days = var.document_glacier_transition_days
      storage_class   = "GLACIER"
    }

    noncurrent_version_expiration {
      noncurrent_days = var.document_deep_archive_transition_days + 365
    }
  }

  # Log archiving lifecycle rule
  rule {
    id     = "LogArchiving"
    status = "Enabled"

    filter {
      prefix = "logs/"
    }

    transition {
      days          = var.log_ia_transition_days
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = var.log_glacier_transition_days
      storage_class = "GLACIER"
    }

    transition {
      days          = var.log_glacier_transition_days + 60
      storage_class = "DEEP_ARCHIVE"
    }

    expiration {
      days = var.log_expiration_days
    }

    # Handle versioned log objects
    noncurrent_version_transition {
      noncurrent_days = var.log_ia_transition_days
      storage_class   = "STANDARD_IA"
    }

    noncurrent_version_expiration {
      noncurrent_days = var.log_expiration_days
    }
  }

  # Backup archiving lifecycle rule
  rule {
    id     = "BackupArchiving"
    status = "Enabled"

    filter {
      prefix = "backups/"
    }

    transition {
      days          = var.backup_ia_transition_days
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = var.backup_glacier_transition_days
      storage_class = "GLACIER"
    }

    # Handle versioned backup objects
    noncurrent_version_transition {
      noncurrent_days = var.backup_ia_transition_days
      storage_class   = "STANDARD_IA"
    }

    noncurrent_version_transition {
      noncurrent_days = var.backup_glacier_transition_days
      storage_class   = "GLACIER"
    }
  }

  # Media intelligent tiering lifecycle rule
  rule {
    id     = "MediaIntelligentTiering"
    status = "Enabled"

    filter {
      prefix = "media/"
    }

    transition {
      days          = 0
      storage_class = "INTELLIGENT_TIERING"
    }

    # Handle versioned media objects
    noncurrent_version_transition {
      noncurrent_days = 0
      storage_class   = "INTELLIGENT_TIERING"
    }
  }

  depends_on = [aws_s3_bucket_versioning.bucket_versioning]
}

# S3 Intelligent Tiering Configuration for media files
resource "aws_s3_bucket_intelligent_tiering_configuration" "media_intelligent_tiering" {
  count  = var.enable_intelligent_tiering ? 1 : 0
  bucket = aws_s3_bucket.data_archiving_bucket.id
  name   = "MediaIntelligentTieringConfig"

  filter {
    prefix = "media/"
  }

  tiering {
    access_tier = "ARCHIVE_ACCESS"
    days        = var.intelligent_tiering_archive_days
  }

  tiering {
    access_tier = "DEEP_ARCHIVE_ACCESS"
    days        = var.intelligent_tiering_deep_archive_days
  }

  status = "Enabled"
}

# S3 Analytics Configuration for documents
resource "aws_s3_bucket_analytics_configuration" "document_analytics" {
  count  = var.enable_s3_analytics ? 1 : 0
  bucket = aws_s3_bucket.data_archiving_bucket.id
  name   = "DocumentAnalytics"

  filter {
    prefix = "documents/"
  }

  storage_class_analysis {
    data_export {
      destination {
        s3_bucket_destination {
          bucket_arn = aws_s3_bucket.data_archiving_bucket.arn
          prefix     = "analytics-reports/documents/"
          format     = "CSV"
        }
      }
      output_schema_version = "V_1"
    }
  }
}

# S3 Inventory Configuration
resource "aws_s3_bucket_inventory" "storage_inventory" {
  count  = var.enable_s3_inventory ? 1 : 0
  bucket = aws_s3_bucket.data_archiving_bucket.id
  name   = "StorageInventoryConfig"

  included_object_versions = "Current"

  schedule {
    frequency = var.inventory_frequency
  }

  destination {
    bucket {
      format     = "CSV"
      bucket_arn = aws_s3_bucket.data_archiving_bucket.arn
      prefix     = "inventory-reports/"
    }
  }

  optional_fields = [
    "Size",
    "LastModifiedDate", 
    "StorageClass",
    "IntelligentTieringAccessTier"
  ]

  enabled = true
}

# IAM Role for S3 Lifecycle Management
resource "aws_iam_role" "lifecycle_role" {
  count = var.create_lifecycle_role ? 1 : 0
  name  = var.lifecycle_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name    = "S3 Lifecycle Management Role"
    Purpose = "Enable automated S3 lifecycle management operations"
  }
}

# IAM Policy for S3 Lifecycle Management
resource "aws_iam_policy" "lifecycle_policy" {
  count       = var.create_lifecycle_role ? 1 : 0
  name        = "DataArchivingPolicy"
  description = "Policy for S3 lifecycle management operations"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetBucketLocation",
          "s3:GetBucketLifecycleConfiguration",
          "s3:PutBucketLifecycleConfiguration",
          "s3:GetBucketVersioning",
          "s3:GetBucketIntelligentTieringConfiguration",
          "s3:PutBucketIntelligentTieringConfiguration"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.data_archiving_bucket.arn,
          "${aws_s3_bucket.data_archiving_bucket.arn}/*"
        ]
      }
    ]
  })
}

# Attach policy to role
resource "aws_iam_role_policy_attachment" "lifecycle_role_policy" {
  count      = var.create_lifecycle_role ? 1 : 0
  role       = aws_iam_role.lifecycle_role[0].name
  policy_arn = aws_iam_policy.lifecycle_policy[0].arn
}

# CloudWatch Alarm for Storage Costs
resource "aws_cloudwatch_metric_alarm" "storage_cost_alarm" {
  count = var.enable_cloudwatch_monitoring ? 1 : 0

  alarm_name          = "S3-Storage-Cost-${aws_s3_bucket.data_archiving_bucket.id}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "EstimatedCharges"
  namespace           = "AWS/Billing"
  period              = "86400"
  statistic           = "Maximum"
  threshold           = var.storage_cost_threshold
  alarm_description   = "Monitor S3 storage costs for bucket ${aws_s3_bucket.data_archiving_bucket.id}"
  alarm_actions       = var.sns_topic_arn != "" ? [var.sns_topic_arn] : []

  dimensions = {
    Currency    = "USD"
    ServiceName = "AmazonS3"
  }

  treat_missing_data = "notBreaching"

  tags = {
    Name    = "S3 Storage Cost Alarm"
    Bucket  = aws_s3_bucket.data_archiving_bucket.id
    Purpose = "Monitor unexpected storage cost increases"
  }
}

# CloudWatch Alarm for Object Count
resource "aws_cloudwatch_metric_alarm" "object_count_alarm" {
  count = var.enable_cloudwatch_monitoring ? 1 : 0

  alarm_name          = "S3-Object-Count-${aws_s3_bucket.data_archiving_bucket.id}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "NumberOfObjects"
  namespace           = "AWS/S3"
  period              = "86400"
  statistic           = "Average"
  threshold           = var.object_count_threshold
  alarm_description   = "Monitor S3 object count for bucket ${aws_s3_bucket.data_archiving_bucket.id}"

  dimensions = {
    BucketName  = aws_s3_bucket.data_archiving_bucket.id
    StorageType = "AllStorageTypes"
  }

  treat_missing_data = "notBreaching"

  tags = {
    Name    = "S3 Object Count Alarm"
    Bucket  = aws_s3_bucket.data_archiving_bucket.id
    Purpose = "Monitor unexpected object count increases"
  }
}

# Sample data objects to demonstrate lifecycle policies
resource "aws_s3_object" "sample_document" {
  bucket = aws_s3_bucket.data_archiving_bucket.id
  key    = "documents/business-doc-${formatdate("YYYYMMDD", timestamp())}.txt"
  content = "Important business document - ${timestamp()}"
  
  tags = {
    DataType = "Document"
    Purpose  = "Sample data for lifecycle demonstration"
  }
}

resource "aws_s3_object" "sample_log" {
  bucket = aws_s3_bucket.data_archiving_bucket.id
  key    = "logs/app-log-${formatdate("YYYYMMDD", timestamp())}.log"
  content = "Application log entry - ${timestamp()}"
  
  tags = {
    DataType = "Log"
    Purpose  = "Sample data for lifecycle demonstration"
  }
}

resource "aws_s3_object" "sample_backup" {
  bucket = aws_s3_bucket.data_archiving_bucket.id
  key    = "backups/db-backup-${formatdate("YYYYMMDD", timestamp())}.sql"
  content = "Database backup metadata - ${timestamp()}"
  
  tags = {
    DataType = "Backup"
    Purpose  = "Sample data for lifecycle demonstration"
  }
}

resource "aws_s3_object" "sample_media" {
  bucket = aws_s3_bucket.data_archiving_bucket.id
  key    = "media/video-${formatdate("YYYYMMDD", timestamp())}.mp4"
  content = "Media file placeholder - ${timestamp()}"
  
  tags = {
    DataType = "Media"
    Purpose  = "Sample data for lifecycle demonstration"
  }
}