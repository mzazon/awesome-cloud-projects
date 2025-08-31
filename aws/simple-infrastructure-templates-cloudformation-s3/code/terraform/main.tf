# Main Terraform Configuration for Simple Infrastructure Templates with CloudFormation and S3
# This configuration creates a secure S3 bucket following AWS security best practices
# equivalent to the CloudFormation template described in the recipe

# Data source to get current AWS account information
data "aws_caller_identity" "current" {}

# Data source to get current AWS region
data "aws_region" "current" {}

# Random string for unique bucket naming
resource "random_string" "bucket_suffix" {
  length  = 6
  special = false
  upper   = false
  numeric = true
  lower   = true
}

# Local values for computed configurations
locals {
  # Generate unique bucket name with prefix and random suffix
  bucket_name = "${var.bucket_name_prefix}-${random_string.bucket_suffix.result}"
  
  # Access log bucket name - either use provided name or create one
  access_log_bucket_name = var.enable_access_logging ? (
    var.access_log_bucket_name != null ? var.access_log_bucket_name : "${local.bucket_name}-access-logs"
  ) : null
  
  # Merge default and custom tags
  common_tags = merge(
    var.additional_tags,
    {
      BucketName = local.bucket_name
      CreatedBy  = "Terraform"
    }
  )
}

# S3 Access Logs Bucket (conditional creation)
# This bucket stores access logs for the main bucket if access logging is enabled
resource "aws_s3_bucket" "access_logs" {
  count = var.enable_access_logging && var.access_log_bucket_name == null ? 1 : 0
  
  bucket = local.access_log_bucket_name
  
  tags = merge(
    local.common_tags,
    {
      Name    = "${local.access_log_bucket_name}"
      Purpose = "Access-Logs-Storage"
    }
  )
}

# Access logs bucket public access block (conditional)
resource "aws_s3_bucket_public_access_block" "access_logs" {
  count = var.enable_access_logging && var.access_log_bucket_name == null ? 1 : 0
  
  bucket = aws_s3_bucket.access_logs[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Access logs bucket server-side encryption (conditional)
resource "aws_s3_bucket_server_side_encryption_configuration" "access_logs" {
  count = var.enable_access_logging && var.access_log_bucket_name == null ? 1 : 0
  
  bucket = aws_s3_bucket.access_logs[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# Main S3 Bucket
# This is the primary infrastructure bucket created by this template
resource "aws_s3_bucket" "main" {
  bucket = local.bucket_name
  
  # Enable object lock if specified (must be set at bucket creation)
  object_lock_enabled = var.object_lock_enabled
  
  tags = merge(
    local.common_tags,
    var.bucket_specific_tags,
    {
      Name = local.bucket_name
    }
  )
}

# S3 Bucket Versioning Configuration
# Enables versioning to protect against accidental deletion or modification
resource "aws_s3_bucket_versioning" "main" {
  bucket = aws_s3_bucket.main.id
  
  versioning_configuration {
    status     = var.enable_versioning ? "Enabled" : "Suspended"
    mfa_delete = var.mfa_delete ? "Enabled" : "Disabled"
  }
}

# S3 Bucket Server-Side Encryption Configuration
# Implements AES256 encryption by default with bucket key optimization
resource "aws_s3_bucket_server_side_encryption_configuration" "main" {
  count = var.enable_encryption ? 1 : 0
  
  bucket = aws_s3_bucket.main.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.encryption_algorithm
      kms_master_key_id = var.encryption_algorithm == "aws:kms" ? var.kms_key_id : null
    }
    
    # Enable bucket key for cost optimization (reduces KMS API calls)
    bucket_key_enabled = var.enable_bucket_key
  }
}

# S3 Bucket Public Access Block Configuration
# Blocks all public access to prevent accidental data exposure
resource "aws_s3_bucket_public_access_block" "main" {
  bucket = aws_s3_bucket.main.id

  block_public_acls       = var.block_public_access.block_public_acls
  block_public_policy     = var.block_public_access.block_public_policy
  ignore_public_acls      = var.block_public_access.ignore_public_acls
  restrict_public_buckets = var.block_public_access.restrict_public_buckets
}

# S3 Bucket Lifecycle Configuration (conditional)
# Automatically transitions objects to cheaper storage classes based on age
resource "aws_s3_bucket_lifecycle_configuration" "main" {
  count = var.enable_lifecycle_policy ? 1 : 0
  
  bucket = aws_s3_bucket.main.id

  rule {
    id     = "lifecycle_policy"
    status = "Enabled"

    # Transition to Standard-IA after specified days
    transition {
      days          = var.lifecycle_transition_ia_days
      storage_class = "STANDARD_IA"
    }

    # Transition to Glacier after specified days
    transition {
      days          = var.lifecycle_transition_glacier_days
      storage_class = "GLACIER"
    }

    # Expire objects after specified days (if enabled)
    dynamic "expiration" {
      for_each = var.lifecycle_expiration_days > 0 ? [1] : []
      content {
        days = var.lifecycle_expiration_days
      }
    }

    # Clean up incomplete multipart uploads after 7 days
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# S3 Bucket Logging Configuration (conditional)
# Enables access logging to track bucket usage and requests
resource "aws_s3_bucket_logging" "main" {
  count = var.enable_access_logging ? 1 : 0
  
  bucket = aws_s3_bucket.main.id

  target_bucket = local.access_log_bucket_name
  target_prefix = var.access_log_prefix
}

# S3 Bucket Request Payment Configuration
# Controls who pays for requests and data transfer
resource "aws_s3_bucket_request_payment_configuration" "main" {
  bucket = aws_s3_bucket.main.id
  payer  = var.request_payer
}

# S3 Bucket Object Lock Configuration (conditional)
# Provides WORM (Write Once Read Many) functionality for compliance
resource "aws_s3_bucket_object_lock_configuration" "main" {
  count = var.object_lock_enabled && var.object_lock_configuration.rule != null ? 1 : 0
  
  bucket = aws_s3_bucket.main.id

  object_lock_enabled = var.object_lock_configuration.object_lock_enabled ? "Enabled" : "Disabled"

  rule {
    default_retention {
      mode  = var.object_lock_configuration.rule.default_retention.mode
      days  = var.object_lock_configuration.rule.default_retention.days
      years = var.object_lock_configuration.rule.default_retention.years
    }
  }
}

# S3 Bucket Notification Configuration (placeholder for future extensions)
# This can be extended to integrate with SNS, SQS, or Lambda functions
# Currently commented out but provided as a template for future enhancements
#
# resource "aws_s3_bucket_notification" "main" {
#   bucket = aws_s3_bucket.main.id
#
#   lambda_function {
#     lambda_function_arn = aws_lambda_function.processor.arn
#     events              = ["s3:ObjectCreated:*"]
#     filter_prefix       = "uploads/"
#     filter_suffix       = ".jpg"
#   }
#
#   depends_on = [aws_lambda_permission.allow_bucket]
# }