# Generate random suffix for globally unique bucket name
resource "random_id" "bucket_suffix" {
  byte_length = 3
}

# Data source to get current AWS account ID
data "aws_caller_identity" "current" {}

# Data source to get current AWS region
data "aws_region" "current" {}

# Create S3 bucket for long-term archiving
resource "aws_s3_bucket" "archive_bucket" {
  bucket = "${var.bucket_name_prefix}-${random_id.bucket_suffix.hex}"

  tags = merge(
    {
      Name        = "${var.bucket_name_prefix}-${random_id.bucket_suffix.hex}"
      Purpose     = "Long-term data archiving with Glacier Deep Archive"
      CostCenter  = "Data Management"
    },
    var.additional_tags
  )
}

# Configure bucket versioning for additional data protection
resource "aws_s3_bucket_versioning" "archive_bucket_versioning" {
  bucket = aws_s3_bucket.archive_bucket.id
  
  versioning_configuration {
    status     = var.enable_versioning ? "Enabled" : "Disabled"
    mfa_delete = var.enable_mfa_delete ? "Enabled" : "Disabled"
  }
}

# Configure server-side encryption for the bucket
resource "aws_s3_bucket_server_side_encryption_configuration" "archive_bucket_encryption" {
  count  = var.enable_server_side_encryption ? 1 : 0
  bucket = aws_s3_bucket.archive_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.sse_algorithm
      kms_master_key_id = var.sse_algorithm == "aws:kms" && var.kms_key_id != "" ? var.kms_key_id : null
    }
    bucket_key_enabled = var.sse_algorithm == "aws:kms" ? true : null
  }
}

# Configure public access block settings for enhanced security
resource "aws_s3_bucket_public_access_block" "archive_bucket_pab" {
  count  = var.enable_public_access_block ? 1 : 0
  bucket = aws_s3_bucket.archive_bucket.id

  block_public_acls       = var.block_public_acls
  block_public_policy     = var.block_public_policy
  ignore_public_acls      = var.ignore_public_acls
  restrict_public_buckets = var.restrict_public_buckets
}

# Configure lifecycle rules for automatic transition to Glacier Deep Archive
resource "aws_s3_bucket_lifecycle_configuration" "archive_lifecycle" {
  depends_on = [aws_s3_bucket_versioning.archive_bucket_versioning]
  bucket     = aws_s3_bucket.archive_bucket.id

  # Rule for archives folder - faster transition to Deep Archive
  rule {
    id     = "Archives-to-Deep-Archive"
    status = "Enabled"

    filter {
      prefix = "archives/"
    }

    transition {
      days          = var.archives_transition_days
      storage_class = "DEEP_ARCHIVE"
    }

    # Clean up incomplete multipart uploads if enabled
    dynamic "abort_incomplete_multipart_upload" {
      for_each = var.enable_incomplete_multipart_cleanup ? [1] : []
      content {
        days_after_initiation = var.incomplete_multipart_cleanup_days
      }
    }
  }

  # Rule for all other files - standard transition timeline
  rule {
    id     = "General-to-Deep-Archive"
    status = "Enabled"

    filter {
      prefix = ""
    }

    transition {
      days          = var.general_transition_days
      storage_class = "DEEP_ARCHIVE"
    }

    # Clean up incomplete multipart uploads if enabled
    dynamic "abort_incomplete_multipart_upload" {
      for_each = var.enable_incomplete_multipart_cleanup ? [1] : []
      content {
        days_after_initiation = var.incomplete_multipart_cleanup_days
      }
    }
  }

  # Rule for versioned objects - transition non-current versions
  dynamic "rule" {
    for_each = var.enable_versioning ? [1] : []
    content {
      id     = "Noncurrent-Versions-to-Deep-Archive"
      status = "Enabled"

      filter {
        prefix = ""
      }

      noncurrent_version_transition {
        noncurrent_days = var.general_transition_days + 30
        storage_class   = "DEEP_ARCHIVE"
      }

      # Optionally delete old non-current versions after extended period
      noncurrent_version_expiration {
        noncurrent_days = var.general_transition_days + 2555  # 7 years
      }
    }
  }
}

# Create SNS topic for archive notifications
resource "aws_sns_topic" "archive_notifications" {
  count = var.enable_notifications ? 1 : 0
  name  = "s3-archive-notifications-${random_id.bucket_suffix.hex}"

  tags = merge(
    {
      Name    = "S3 Archive Notifications"
      Purpose = "Notifications for S3 lifecycle transitions"
    },
    var.additional_tags
  )
}

# Create SNS topic policy to allow S3 to publish messages
resource "aws_sns_topic_policy" "archive_notifications_policy" {
  count = var.enable_notifications ? 1 : 0
  arn   = aws_sns_topic.archive_notifications[0].arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowS3Publish"
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
        Action   = "sns:Publish"
        Resource = aws_sns_topic.archive_notifications[0].arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
          ArnEquals = {
            "aws:SourceArn" = aws_s3_bucket.archive_bucket.arn
          }
        }
      }
    ]
  })
}

# Subscribe email to SNS topic if email address is provided
resource "aws_sns_topic_subscription" "email_notification" {
  count     = var.enable_notifications && var.notification_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.archive_notifications[0].arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# Configure S3 bucket notifications for lifecycle transitions
resource "aws_s3_bucket_notification" "archive_notifications" {
  count      = var.enable_notifications ? 1 : 0
  bucket     = aws_s3_bucket.archive_bucket.id
  depends_on = [aws_sns_topic_policy.archive_notifications_policy]

  topic {
    topic_arn = aws_sns_topic.archive_notifications[0].arn
    events    = ["s3:LifecycleTransition"]

    filter_prefix = ""
    filter_suffix = var.notification_filter_suffix
  }
}

# Create destination bucket for inventory reports (using same bucket for simplicity)
# In production, you might want to use a separate bucket
resource "aws_s3_bucket_inventory" "archive_inventory" {
  count  = var.enable_inventory ? 1 : 0
  bucket = aws_s3_bucket.archive_bucket.id
  name   = "Weekly-Archive-Inventory"

  included_object_versions = var.inventory_included_object_versions

  schedule {
    frequency = var.inventory_frequency
  }

  destination {
    bucket {
      format     = "CSV"
      bucket_arn = aws_s3_bucket.archive_bucket.arn
      prefix     = "inventory-reports/"
      
      # Enable encryption for inventory reports
      encryption {
        sse_s3 {}
      }
    }
  }

  optional_fields = [
    "Size",
    "LastModifiedDate", 
    "StorageClass",
    "ETag",
    "IsMultipartUploaded",
    "ReplicationStatus",
    "EncryptionStatus"
  ]
}

# Create IAM role for S3 inventory (required for inventory configuration)
resource "aws_iam_role" "s3_inventory_role" {
  count = var.enable_inventory ? 1 : 0
  name  = "s3-inventory-role-${random_id.bucket_suffix.hex}"

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

  tags = merge(
    {
      Name    = "S3 Inventory Role"
      Purpose = "Allow S3 to write inventory reports"
    },
    var.additional_tags
  )
}

# Create IAM policy for S3 inventory role
resource "aws_iam_role_policy" "s3_inventory_policy" {
  count = var.enable_inventory ? 1 : 0
  name  = "s3-inventory-policy-${random_id.bucket_suffix.hex}"
  role  = aws_iam_role.s3_inventory_role[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:PutObjectAcl",
          "s3:GetBucketLocation"
        ]
        Resource = [
          aws_s3_bucket.archive_bucket.arn,
          "${aws_s3_bucket.archive_bucket.arn}/*"
        ]
      }
    ]
  })
}

# Create sample directories in S3 to demonstrate the archiving structure
resource "aws_s3_object" "archives_folder" {
  bucket       = aws_s3_bucket.archive_bucket.id
  key          = "archives/.gitkeep"
  content      = "This folder contains documents that transition to Deep Archive after ${var.archives_transition_days} days"
  content_type = "text/plain"

  tags = merge(
    {
      Purpose = "Folder marker for fast archiving path"
    },
    var.additional_tags
  )
}

resource "aws_s3_object" "general_folder" {
  bucket       = aws_s3_bucket.archive_bucket.id
  key          = "general/.gitkeep" 
  content      = "This folder contains documents that transition to Deep Archive after ${var.general_transition_days} days"
  content_type = "text/plain"

  tags = merge(
    {
      Purpose = "Folder marker for standard archiving path"
    },
    var.additional_tags
  )
}