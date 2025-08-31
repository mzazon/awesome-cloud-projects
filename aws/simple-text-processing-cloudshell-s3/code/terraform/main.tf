# Main Terraform configuration for Simple Text Processing with CloudShell and S3
# This configuration creates the infrastructure needed for text processing workflows

# Generate random suffix for unique resource naming
resource "random_id" "bucket_suffix" {
  byte_length = 3
  
  keepers = {
    bucket_prefix = var.bucket_name_prefix
    environment   = var.environment
  }
}

# Data source to get current AWS caller identity
data "aws_caller_identity" "current" {}

# Data source to get current AWS region
data "aws_region" "current" {}

# Create S3 bucket for text processing data
resource "aws_s3_bucket" "text_processing" {
  bucket = "${var.bucket_name_prefix}-${random_id.bucket_suffix.hex}"

  # Prevent accidental deletion in production
  lifecycle {
    prevent_destroy = false # Set to true for production environments
  }

  tags = merge(var.additional_tags, {
    Name        = "${var.bucket_name_prefix}-${random_id.bucket_suffix.hex}"
    Purpose     = "Text processing data storage"
    DataClass   = "BusinessData"
  })
}

# Configure S3 bucket versioning
resource "aws_s3_bucket_versioning" "text_processing" {
  bucket = aws_s3_bucket.text_processing.id
  
  versioning_configuration {
    status = var.enable_versioning ? "Enabled" : "Suspended"
  }
}

# Configure S3 bucket server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "text_processing" {
  count  = var.enable_encryption ? 1 : 0
  bucket = aws_s3_bucket.text_processing.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# Configure S3 bucket public access block for security
resource "aws_s3_bucket_public_access_block" "text_processing" {
  bucket = aws_s3_bucket.text_processing.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Configure S3 bucket lifecycle management
resource "aws_s3_bucket_lifecycle_configuration" "text_processing" {
  depends_on = [aws_s3_bucket_versioning.text_processing]
  bucket     = aws_s3_bucket.text_processing.id

  rule {
    id     = "text_processing_lifecycle"
    status = "Enabled"

    # Transition current versions to IA after specified days
    transition {
      days          = var.lifecycle_transition_days
      storage_class = "STANDARD_IA"
    }

    # Transition current versions to Glacier after 90 days
    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    # Delete objects after expiration (if configured)
    dynamic "expiration" {
      for_each = var.lifecycle_expiration_days > 0 ? [1] : []
      content {
        days = var.lifecycle_expiration_days
      }
    }

    # Handle non-current versions if versioning is enabled
    dynamic "noncurrent_version_transition" {
      for_each = var.enable_versioning ? [1] : []
      content {
        noncurrent_days = 30
        storage_class   = "STANDARD_IA"
      }
    }

    dynamic "noncurrent_version_expiration" {
      for_each = var.enable_versioning ? [1] : []
      content {
        noncurrent_days = 90
      }
    }

    # Clean up incomplete multipart uploads
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# Create folder structure in S3 bucket using placeholder objects
resource "aws_s3_object" "folder_structure" {
  for_each = toset(var.folder_structure)
  
  bucket = aws_s3_bucket.text_processing.id
  key    = each.value
  source = "/dev/null"
  
  tags = {
    Purpose = "Folder structure placeholder"
    Type    = "Directory"
  }
}

# Create sample sales data file
resource "aws_s3_object" "sample_data" {
  count  = var.create_sample_data ? 1 : 0
  bucket = aws_s3_bucket.text_processing.id
  key    = "input/sample_sales_data.csv"
  
  content = <<-EOT
Date,Region,Product,Sales,Quantity
2024-01-15,North,Laptop,1200,2
2024-01-16,South,Mouse,25,5
2024-01-17,East,Keyboard,75,3
2024-01-18,West,Monitor,300,1
2024-01-19,North,Laptop,600,1
2024-01-20,South,Tablet,400,2
2024-01-21,East,Mouse,50,10
2024-01-22,West,Keyboard,150,6
2024-01-23,North,Monitor,900,3
2024-01-24,South,Laptop,2400,4
2024-01-25,East,Tablet,800,4
2024-01-26,West,Mouse,75,15
EOT

  content_type = "text/csv"
  
  tags = {
    Purpose   = "Sample data for text processing demo"
    DataType  = "CSV"
    Generated = "Terraform"
  }
}

# Create IAM policy for CloudShell access to S3 bucket
resource "aws_iam_policy" "cloudshell_s3_access" {
  name        = "TextProcessingCloudShellS3Access-${random_id.bucket_suffix.hex}"
  description = "Policy allowing CloudShell access to text processing S3 bucket"
  
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
          "s3:GetObjectVersion",
          "s3:PutObjectAcl",
          "s3:GetObjectAcl"
        ]
        Resource = [
          aws_s3_bucket.text_processing.arn,
          "${aws_s3_bucket.text_processing.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListAllMyBuckets"
        ]
        Resource = "*"
      }
    ]
  })

  tags = merge(var.additional_tags, {
    Purpose = "CloudShell S3 access for text processing"
    Service = "IAM"
  })
}

# Create IAM role for CloudShell (optional - for specific use cases)
resource "aws_iam_role" "cloudshell_text_processing" {
  count = length(var.allowed_principals) > 0 ? 1 : 0
  name  = "CloudShellTextProcessingRole-${random_id.bucket_suffix.hex}"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          AWS = var.allowed_principals
        }
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = data.aws_region.current.name
          }
        }
      }
    ]
  })

  tags = merge(var.additional_tags, {
    Purpose = "CloudShell role for text processing operations"
    Service = "IAM"
  })
}

# Attach policy to CloudShell role
resource "aws_iam_role_policy_attachment" "cloudshell_s3_policy" {
  count      = length(var.allowed_principals) > 0 ? 1 : 0
  role       = aws_iam_role.cloudshell_text_processing[0].name
  policy_arn = aws_iam_policy.cloudshell_s3_access.arn
}

# SNS topic for S3 event notifications (optional)
resource "aws_sns_topic" "s3_notifications" {
  count = var.notification_email != "" ? 1 : 0
  name  = "text-processing-s3-notifications-${random_id.bucket_suffix.hex}"

  tags = merge(var.additional_tags, {
    Purpose = "S3 event notifications for text processing"
    Service = "SNS"
  })
}

# SNS topic subscription for email notifications
resource "aws_sns_topic_subscription" "email_notification" {
  count     = var.notification_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.s3_notifications[0].arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# SNS topic policy to allow S3 to publish messages
resource "aws_sns_topic_policy" "s3_notification_policy" {
  count = var.notification_email != "" ? 1 : 0
  arn   = aws_sns_topic.s3_notifications[0].arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.s3_notifications[0].arn
        Condition = {
          StringEquals = {
            "aws:SourceArn" = aws_s3_bucket.text_processing.arn
          }
        }
      }
    ]
  })
}

# S3 bucket notification configuration
resource "aws_s3_bucket_notification" "text_processing_notifications" {
  count  = var.notification_email != "" ? 1 : 0
  bucket = aws_s3_bucket.text_processing.id

  topic {
    topic_arn = aws_sns_topic.s3_notifications[0].arn
    events    = ["s3:ObjectCreated:*", "s3:ObjectRemoved:*"]
    
    filter_prefix = "input/"
  }

  topic {
    topic_arn = aws_sns_topic.s3_notifications[0].arn
    events    = ["s3:ObjectCreated:*"]
    
    filter_prefix = "output/"
  }

  depends_on = [aws_sns_topic_policy.s3_notification_policy]
}

# CloudTrail for S3 API logging (optional)
resource "aws_cloudtrail" "s3_api_logging" {
  count          = var.enable_cloudtrail_logging ? 1 : 0
  name           = "text-processing-s3-trail-${random_id.bucket_suffix.hex}"
  s3_bucket_name = aws_s3_bucket.cloudtrail_logs[0].bucket

  event_selector {
    read_write_type                 = "All"
    include_management_events       = false
    exclude_management_event_sources = []

    data_resource {
      type   = "AWS::S3::Object"
      values = ["${aws_s3_bucket.text_processing.arn}/*"]
    }

    data_resource {
      type   = "AWS::S3::Bucket"
      values = [aws_s3_bucket.text_processing.arn]
    }
  }

  tags = merge(var.additional_tags, {
    Purpose = "S3 API logging for text processing bucket"
    Service = "CloudTrail"
  })
}

# CloudTrail logs bucket (only created if CloudTrail is enabled)
resource "aws_s3_bucket" "cloudtrail_logs" {
  count  = var.enable_cloudtrail_logging ? 1 : 0
  bucket = "${var.bucket_name_prefix}-cloudtrail-${random_id.bucket_suffix.hex}"

  tags = merge(var.additional_tags, {
    Purpose = "CloudTrail logs storage"
    Service = "S3"
  })
}

# CloudTrail logs bucket policy
resource "aws_s3_bucket_policy" "cloudtrail_logs_policy" {
  count  = var.enable_cloudtrail_logging ? 1 : 0
  bucket = aws_s3_bucket.cloudtrail_logs[0].id

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
        Resource = aws_s3_bucket.cloudtrail_logs[0].arn
      },
      {
        Sid    = "AWSCloudTrailWrite"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.cloudtrail_logs[0].arn}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      }
    ]
  })
}

# CloudWatch log group for enhanced monitoring (optional)
resource "aws_cloudwatch_log_group" "text_processing_logs" {
  name              = "/aws/textprocessing/${random_id.bucket_suffix.hex}"
  retention_in_days = 30

  tags = merge(var.additional_tags, {
    Purpose = "Text processing application logs"
    Service = "CloudWatch"
  })
}