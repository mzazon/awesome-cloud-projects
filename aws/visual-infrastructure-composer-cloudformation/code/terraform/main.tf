# =============================================================================
# Visual Infrastructure Design with Application Composer and CloudFormation
# =============================================================================
# This Terraform configuration creates the same infrastructure that would be
# designed visually using AWS Infrastructure Composer and deployed via CloudFormation.
# The primary resource is an S3 bucket configured for static website hosting.

# =============================================================================
# Data Sources
# =============================================================================

# Get current AWS caller identity to reference account ID
data "aws_caller_identity" "current" {}

# Get current AWS region
data "aws_region" "current" {}

# Generate a random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# =============================================================================
# Local Values
# =============================================================================

locals {
  # Common tags to apply to all resources
  common_tags = {
    Project     = "visual-infrastructure-composer"
    Environment = var.environment
    ManagedBy   = "terraform"
    Recipe      = "visual-infrastructure-composer-cloudformation"
  }

  # S3 bucket name with random suffix to ensure uniqueness
  bucket_name = "${var.bucket_prefix}-${random_string.suffix.result}"

  # Website URL for the S3 static website
  website_url = "http://${aws_s3_bucket.website.bucket}.s3-website-${data.aws_region.current.name}.amazonaws.com"
}

# =============================================================================
# S3 Bucket for Static Website Hosting
# =============================================================================

# Create S3 bucket for static website hosting
# This is the main resource that would be created through Infrastructure Composer
resource "aws_s3_bucket" "website" {
  bucket = local.bucket_name

  tags = merge(local.common_tags, {
    Name        = local.bucket_name
    Purpose     = "Static website hosting"
    Description = "S3 bucket configured for static website hosting via visual design"
  })
}

# Configure the S3 bucket for static website hosting
# This configuration enables the bucket to serve web content
resource "aws_s3_bucket_website_configuration" "website" {
  bucket = aws_s3_bucket.website.id

  # Set the index document (default page)
  index_document {
    suffix = var.index_document
  }

  # Set the error document (404 page)
  error_document {
    key = var.error_document
  }

  depends_on = [aws_s3_bucket.website]
}

# Configure S3 bucket versioning (optional but recommended)
resource "aws_s3_bucket_versioning" "website" {
  bucket = aws_s3_bucket.website.id
  versioning_configuration {
    status = var.enable_versioning ? "Enabled" : "Suspended"
  }
}

# Configure server-side encryption for the S3 bucket
resource "aws_s3_bucket_server_side_encryption_configuration" "website" {
  bucket = aws_s3_bucket.website.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# Block public ACLs - we'll use bucket policy for public access
resource "aws_s3_bucket_public_access_block" "website" {
  bucket = aws_s3_bucket.website.id

  # Block public ACLs but allow bucket policy for public read access
  block_public_acls       = true
  block_public_policy     = false
  ignore_public_acls      = true
  restrict_public_buckets = false
}

# =============================================================================
# S3 Bucket Policy for Public Read Access
# =============================================================================

# Create bucket policy to allow public read access to website content
# This policy would be visually connected to the S3 bucket in Infrastructure Composer
resource "aws_s3_bucket_policy" "website" {
  bucket = aws_s3_bucket.website.id

  # Define the policy document for public read access
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.website.arn}/*"
        Condition = {
          StringEquals = {
            "s3:ExistingObjectTag/Environment" = var.environment
          }
        }
      }
    ]
  })

  depends_on = [
    aws_s3_bucket_public_access_block.website,
    aws_s3_bucket.website
  ]
}

# =============================================================================
# Sample Website Content (Optional)
# =============================================================================

# Upload sample index.html file to demonstrate website functionality
resource "aws_s3_object" "index" {
  count = var.upload_sample_content ? 1 : 0

  bucket       = aws_s3_bucket.website.id
  key          = var.index_document
  content_type = "text/html"

  # Sample HTML content that demonstrates the visual infrastructure design
  content = templatefile("${path.module}/templates/index.html.tpl", {
    website_url = local.website_url
    bucket_name = local.bucket_name
    region      = data.aws_region.current.name
  })

  # Tag the object to match bucket policy condition
  tags = merge(local.common_tags, {
    Name        = "Index Document"
    Environment = var.environment
  })

  depends_on = [
    aws_s3_bucket_website_configuration.website,
    aws_s3_bucket_policy.website
  ]
}

# Upload sample error.html file for 404 handling
resource "aws_s3_object" "error" {
  count = var.upload_sample_content ? 1 : 0

  bucket       = aws_s3_bucket.website.id
  key          = var.error_document
  content_type = "text/html"

  # Sample HTML content for error page
  content = templatefile("${path.module}/templates/error.html.tpl", {
    website_url = local.website_url
    bucket_name = local.bucket_name
  })

  # Tag the object to match bucket policy condition
  tags = merge(local.common_tags, {
    Name        = "Error Document"
    Environment = var.environment
  })

  depends_on = [
    aws_s3_bucket_website_configuration.website,
    aws_s3_bucket_policy.website
  ]
}

# =============================================================================
# CloudWatch Monitoring (Optional)
# =============================================================================

# Create CloudWatch alarm for monitoring bucket size (optional enhancement)
resource "aws_cloudwatch_metric_alarm" "bucket_size" {
  count = var.enable_monitoring ? 1 : 0

  alarm_name          = "${local.bucket_name}-size-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "BucketSizeBytes"
  namespace           = "AWS/S3"
  period              = "86400" # Daily
  statistic           = "Average"
  threshold           = var.bucket_size_threshold
  alarm_description   = "This metric monitors S3 bucket size for ${local.bucket_name}"
  alarm_actions       = var.sns_topic_arn != "" ? [var.sns_topic_arn] : []

  dimensions = {
    BucketName  = aws_s3_bucket.website.bucket
    StorageType = "StandardStorage"
  }

  tags = local.common_tags
}

# Create CloudWatch alarm for monitoring number of objects (optional enhancement)
resource "aws_cloudwatch_metric_alarm" "object_count" {
  count = var.enable_monitoring ? 1 : 0

  alarm_name          = "${local.bucket_name}-object-count-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "NumberOfObjects"
  namespace           = "AWS/S3"
  period              = "86400" # Daily
  statistic           = "Average"
  threshold           = var.object_count_threshold
  alarm_description   = "This metric monitors number of objects in ${local.bucket_name}"
  alarm_actions       = var.sns_topic_arn != "" ? [var.sns_topic_arn] : []

  dimensions = {
    BucketName  = aws_s3_bucket.website.bucket
    StorageType = "AllStorageTypes"
  }

  tags = local.common_tags
}