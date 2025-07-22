# Data sources for AWS account information
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  # Common tags for all resources
  common_tags = merge(var.tags, {
    Project     = "vod-platform"
    Environment = var.environment
    ManagedBy   = "terraform"
  })
  
  # Generate unique container name if not provided
  container_name = var.mediastore_container_name != "" ? var.mediastore_container_name : "vod-platform-${random_id.suffix.hex}"
  
  # Account ID for policy generation
  account_id = data.aws_caller_identity.current.account_id
}

# S3 bucket for staging content uploads
resource "aws_s3_bucket" "staging" {
  bucket = "vod-staging-${random_id.suffix.hex}"

  tags = merge(local.common_tags, {
    Name = "VOD Staging Bucket"
    Type = "staging"
  })
}

# Configure S3 bucket versioning
resource "aws_s3_bucket_versioning" "staging" {
  bucket = aws_s3_bucket.staging.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Configure S3 bucket server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "staging" {
  bucket = aws_s3_bucket.staging.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Block public access to staging bucket
resource "aws_s3_bucket_public_access_block" "staging" {
  bucket = aws_s3_bucket.staging.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# AWS Elemental MediaStore container for video origin storage
resource "aws_mediastore_container" "vod_origin" {
  name = local.container_name

  tags = merge(local.common_tags, {
    Name = "VOD Origin Container"
    Type = "mediastore"
  })
}

# MediaStore container policy for secure access control
resource "aws_mediastore_container_policy" "vod_policy" {
  container_name = aws_mediastore_container.vod_origin.name
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "MediaStoreFullAccess"
        Effect = "Allow"
        Principal = "*"
        Action = [
          "mediastore:GetObject",
          "mediastore:DescribeObject"
        ]
        Resource = "*"
        Condition = {
          Bool = {
            "aws:SecureTransport" = "true"
          }
        }
      },
      {
        Sid    = "MediaStoreUploadAccess"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${local.account_id}:root"
        }
        Action = [
          "mediastore:PutObject",
          "mediastore:DeleteObject"
        ]
        Resource = "*"
      }
    ]
  })
}

# CORS policy for web application access
resource "aws_mediastore_cors_policy" "vod_cors" {
  container_name = aws_mediastore_container.vod_origin.name
  
  cors_policy = jsonencode([
    {
      AllowedOrigins = ["*"]
      AllowedMethods = ["GET", "HEAD"]
      AllowedHeaders = ["*"]
      MaxAgeSeconds  = var.mediastore_cors_max_age
      ExposeHeaders  = ["Date", "Server"]
    }
  ])
}

# CloudWatch metrics policy for MediaStore monitoring
resource "aws_mediastore_metric_policy" "vod_metrics" {
  count          = var.enable_mediastore_metrics ? 1 : 0
  container_name = aws_mediastore_container.vod_origin.name
  
  metric_policy = jsonencode({
    ContainerLevelMetrics = "ENABLED"
    MetricPolicyRules = [
      {
        ObjectGroup     = "/*"
        ObjectGroupName = "AllObjects"
      }
    ]
  })
}

# Lifecycle policy for automatic content management
resource "aws_mediastore_lifecycle_policy" "vod_lifecycle" {
  container_name = aws_mediastore_container.vod_origin.name
  
  lifecycle_policy = jsonencode({
    Rules = [
      {
        ObjectGroup     = "/videos/temp/*"
        ObjectGroupName = "TempVideos"
        Lifecycle = {
          TransitionToIA    = "AFTER_${var.lifecycle_transition_days}_DAYS"
          ExpirationInDays  = var.lifecycle_expiration_days
        }
      },
      {
        ObjectGroup     = "/videos/archive/*"
        ObjectGroupName = "ArchiveVideos"
        Lifecycle = {
          TransitionToIA   = "AFTER_7_DAYS"
          ExpirationInDays = 365
        }
      }
    ]
  })
}

# IAM role for MediaStore access
resource "aws_iam_role" "mediastore_access" {
  name = "MediaStoreAccessRole-${random_id.suffix.hex}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "mediastore.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "MediaStore Access Role"
    Type = "iam-role"
  })
}

# IAM policy for MediaStore operations
resource "aws_iam_role_policy" "mediastore_access_policy" {
  name = "MediaStoreAccessPolicy"
  role = aws_iam_role.mediastore_access.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "mediastore:GetObject",
          "mediastore:PutObject",
          "mediastore:DeleteObject",
          "mediastore:DescribeObject",
          "mediastore:ListItems"
        ]
        Resource = "*"
      }
    ]
  })
}

# CloudFront Origin Access Control for secure S3 access
resource "aws_cloudfront_origin_access_control" "vod_oac" {
  name                              = "vod-mediastore-oac-${random_id.suffix.hex}"
  description                       = "Origin Access Control for VOD MediaStore"
  origin_access_control_origin_type = "mediastore"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# CloudFront distribution for global content delivery
resource "aws_cloudfront_distribution" "vod_distribution" {
  comment             = var.cloudfront_comment
  default_root_object = ""
  enabled             = true
  is_ipv6_enabled     = true
  price_class         = var.cloudfront_price_class

  # MediaStore origin configuration
  origin {
    domain_name              = replace(aws_mediastore_container.vod_origin.endpoint, "https://", "")
    origin_id                = "MediaStoreOrigin"
    origin_access_control_id = aws_cloudfront_origin_access_control.vod_oac.id

    custom_origin_config {
      http_port                = 443
      https_port               = 443
      origin_protocol_policy   = "https-only"
      origin_ssl_protocols     = ["TLSv1.2"]
      origin_keepalive_timeout = 5
      origin_read_timeout      = 30
    }
  }

  # Default cache behavior for video content
  default_cache_behavior {
    target_origin_id       = "MediaStoreOrigin"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    forwarded_values {
      query_string = true
      cookies {
        forward = "none"
      }
      headers = [
        "Origin",
        "Access-Control-Request-Headers",
        "Access-Control-Request-Method"
      ]
    }

    min_ttl     = 0
    default_ttl = var.cloudfront_default_ttl
    max_ttl     = var.cloudfront_max_ttl
  }

  # Custom cache behavior for video content paths
  ordered_cache_behavior {
    path_pattern           = "/videos/*"
    target_origin_id       = "MediaStoreOrigin"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    min_ttl     = 0
    default_ttl = 86400  # 24 hours for video content
    max_ttl     = 31536000  # 1 year maximum
  }

  # Geographic restrictions (none by default)
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  # SSL/TLS certificate configuration
  viewer_certificate {
    cloudfront_default_certificate = true
    minimum_protocol_version       = "TLSv1.2_2021"
  }

  # Optional access logging configuration
  dynamic "logging_config" {
    for_each = var.enable_cloudfront_logging && var.cloudfront_log_bucket != "" ? [1] : []
    content {
      bucket          = var.cloudfront_log_bucket
      include_cookies = false
      prefix          = "cloudfront-logs/"
    }
  }

  tags = merge(local.common_tags, {
    Name = "VOD CloudFront Distribution"
    Type = "cloudfront"
  })
}

# CloudWatch alarm for high request rate monitoring
resource "aws_cloudwatch_metric_alarm" "high_request_rate" {
  count = var.enable_mediastore_metrics ? 1 : 0
  
  alarm_name          = "MediaStore-HighRequestRate-${random_id.suffix.hex}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "RequestCount"
  namespace           = "AWS/MediaStore"
  period              = "300"
  statistic           = "Sum"
  threshold           = "1000"
  alarm_description   = "This metric monitors high request rate on MediaStore container"
  alarm_actions       = []

  dimensions = {
    ContainerName = aws_mediastore_container.vod_origin.name
  }

  tags = merge(local.common_tags, {
    Name = "MediaStore High Request Rate Alarm"
    Type = "cloudwatch-alarm"
  })
}