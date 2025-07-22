# Main Terraform configuration for Amazon Rekognition image analysis solution

# Data sources for current AWS account and region information
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource naming
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# Local values for consistent naming and configuration
locals {
  bucket_name = "${var.project_name}-images-${var.environment}-${random_id.bucket_suffix.hex}"
  
  common_tags = merge(var.tags, {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  })
}

# KMS key for S3 bucket encryption
resource "aws_kms_key" "s3_encryption" {
  count = var.enable_s3_encryption ? 1 : 0
  
  description             = "KMS key for ${var.project_name} S3 bucket encryption"
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
        Sid    = "Allow S3 service"
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
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
    Name = "${var.project_name}-s3-encryption-key"
  })
}

# KMS key alias for easier reference
resource "aws_kms_alias" "s3_encryption" {
  count         = var.enable_s3_encryption ? 1 : 0
  name          = "alias/${var.project_name}-s3-encryption"
  target_key_id = aws_kms_key.s3_encryption[0].key_id
}

# S3 bucket for storing images to be analyzed
resource "aws_s3_bucket" "images" {
  bucket        = local.bucket_name
  force_destroy = true

  tags = merge(local.common_tags, {
    Name        = local.bucket_name
    Purpose     = "Image storage for Rekognition analysis"
    ContentType = "Images"
  })
}

# S3 bucket versioning configuration
resource "aws_s3_bucket_versioning" "images" {
  bucket = aws_s3_bucket.images.id
  
  versioning_configuration {
    status = var.s3_versioning_enabled ? "Enabled" : "Suspended"
  }
}

# S3 bucket server-side encryption configuration
resource "aws_s3_bucket_server_side_encryption_configuration" "images" {
  count  = var.enable_s3_encryption ? 1 : 0
  bucket = aws_s3_bucket.images.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.s3_encryption[0].arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

# S3 bucket public access block for security
resource "aws_s3_bucket_public_access_block" "images" {
  count  = var.enable_s3_public_access_block ? 1 : 0
  bucket = aws_s3_bucket.images.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket lifecycle configuration
resource "aws_s3_bucket_lifecycle_configuration" "images" {
  count  = var.s3_lifecycle_enabled ? 1 : 0
  bucket = aws_s3_bucket.images.id

  depends_on = [aws_s3_bucket_versioning.images]

  rule {
    id     = "image_lifecycle"
    status = "Enabled"

    # Transition current version to IA after specified days
    transition {
      days          = var.s3_lifecycle_transition_days
      storage_class = "STANDARD_IA"
    }

    # Transition current version to Glacier after 90 days
    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    # Handle non-current versions
    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "STANDARD_IA"
    }

    noncurrent_version_transition {
      noncurrent_days = 60
      storage_class   = "GLACIER"
    }

    # Delete non-current versions after 365 days
    noncurrent_version_expiration {
      noncurrent_days = 365
    }

    # Optional: Delete current version after specified days (if > 0)
    dynamic "expiration" {
      for_each = var.s3_lifecycle_expiration_days > 0 ? [1] : []
      content {
        days = var.s3_lifecycle_expiration_days
      }
    }

    # Clean up incomplete multipart uploads
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# S3 bucket notification for future Lambda integration (optional)
resource "aws_s3_bucket_notification" "images" {
  bucket = aws_s3_bucket.images.id

  # Placeholder for future Lambda function integration
  # This can be uncommented and configured when Lambda functions are added
  # lambda_function {
  #   lambda_function_arn = aws_lambda_function.image_processor.arn
  #   events              = ["s3:ObjectCreated:*"]
  #   filter_prefix       = "images/"
  #   filter_suffix       = ".jpg"
  # }
}

# IAM role for applications to access Rekognition and S3
resource "aws_iam_role" "rekognition_analysis_role" {
  name = "${var.project_name}-rekognition-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = [
            "lambda.amazonaws.com",
            "ec2.amazonaws.com"
          ]
        }
      },
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Condition = {
          StringEquals = {
            "sts:ExternalId" = "${var.project_name}-external-id"
          }
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-rekognition-role"
  })
}

# IAM policy for Rekognition operations
resource "aws_iam_policy" "rekognition_policy" {
  name        = "${var.project_name}-rekognition-policy-${var.environment}"
  description = "Policy for Rekognition image analysis operations"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RekognitionAnalysis"
        Effect = "Allow"
        Action = [
          "rekognition:DetectLabels",
          "rekognition:DetectText",
          "rekognition:DetectModerationLabels",
          "rekognition:DetectFaces",
          "rekognition:DetectProtectiveEquipment",
          "rekognition:DetectCustomLabels"
        ]
        Resource = "*"
      },
      {
        Sid    = "S3ReadAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.images.arn,
          "${aws_s3_bucket.images.arn}/*"
        ]
      },
      {
        Sid    = "S3WriteAccess"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:PutObjectAcl",
          "s3:DeleteObject"
        ]
        Resource = [
          "${aws_s3_bucket.images.arn}/results/*",
          "${aws_s3_bucket.images.arn}/processed/*"
        ]
      }
    ]
  })

  tags = local.common_tags
}

# IAM policy for KMS access (if encryption is enabled)
resource "aws_iam_policy" "kms_policy" {
  count = var.enable_s3_encryption ? 1 : 0
  
  name        = "${var.project_name}-kms-policy-${var.environment}"
  description = "Policy for KMS key access for S3 encryption"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "KMSAccess"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "kms:DescribeKey"
        ]
        Resource = aws_kms_key.s3_encryption[0].arn
      }
    ]
  })

  tags = local.common_tags
}

# Attach Rekognition policy to the role
resource "aws_iam_role_policy_attachment" "rekognition_policy_attachment" {
  role       = aws_iam_role.rekognition_analysis_role.name
  policy_arn = aws_iam_policy.rekognition_policy.arn
}

# Attach KMS policy to the role (if encryption is enabled)
resource "aws_iam_role_policy_attachment" "kms_policy_attachment" {
  count      = var.enable_s3_encryption ? 1 : 0
  role       = aws_iam_role.rekognition_analysis_role.name
  policy_arn = aws_iam_policy.kms_policy[0].arn
}

# Attach basic Lambda execution role (for future Lambda functions)
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.rekognition_analysis_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# CloudTrail for API logging (optional)
resource "aws_cloudtrail" "rekognition_trail" {
  count = var.enable_cloudtrail_logging ? 1 : 0
  
  name           = "${var.project_name}-trail-${var.environment}"
  s3_bucket_name = aws_s3_bucket.cloudtrail_logs[0].bucket

  event_selector {
    read_write_type           = "All"
    include_management_events = true

    data_resource {
      type   = "AWS::S3::Object"
      values = ["${aws_s3_bucket.images.arn}/*"]
    }

    data_resource {
      type   = "AWS::Rekognition::*"
      values = ["*"]
    }
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-cloudtrail"
  })
}

# S3 bucket for CloudTrail logs (if CloudTrail is enabled)
resource "aws_s3_bucket" "cloudtrail_logs" {
  count = var.enable_cloudtrail_logging ? 1 : 0
  
  bucket        = "${var.project_name}-cloudtrail-${var.environment}-${random_id.bucket_suffix.hex}"
  force_destroy = true

  tags = merge(local.common_tags, {
    Name    = "${var.project_name}-cloudtrail-logs"
    Purpose = "CloudTrail logs storage"
  })
}

# CloudTrail bucket policy
resource "aws_s3_bucket_policy" "cloudtrail_bucket_policy" {
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

# Sample S3 object prefixes for organization
resource "aws_s3_object" "images_prefix" {
  bucket       = aws_s3_bucket.images.bucket
  key          = "images/"
  content_type = "application/x-directory"
  
  tags = merge(local.common_tags, {
    Purpose = "Images directory prefix"
  })
}

resource "aws_s3_object" "results_prefix" {
  bucket       = aws_s3_bucket.images.bucket
  key          = "results/"
  content_type = "application/x-directory"
  
  tags = merge(local.common_tags, {
    Purpose = "Analysis results directory prefix"
  })
}

resource "aws_s3_object" "processed_prefix" {
  bucket       = aws_s3_bucket.images.bucket
  key          = "processed/"
  content_type = "application/x-directory"
  
  tags = merge(local.common_tags, {
    Purpose = "Processed images directory prefix"
  })
}