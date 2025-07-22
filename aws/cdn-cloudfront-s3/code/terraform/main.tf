# Main Terraform configuration for CloudFront and S3 CDN

# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Data source for current AWS caller identity
data "aws_caller_identity" "current" {}

# Data source for current AWS region
data "aws_region" "current" {}

# S3 bucket for content storage
resource "aws_s3_bucket" "content_bucket" {
  bucket = "${var.project_name}-${random_string.suffix.result}"
  
  tags = merge(var.tags, {
    Name = "${var.project_name}-content-bucket"
    Type = "content"
  })
}

# S3 bucket for CloudFront access logs
resource "aws_s3_bucket" "logs_bucket" {
  count = var.enable_cloudfront_logging ? 1 : 0
  
  bucket = "${var.project_name}-logs-${random_string.suffix.result}"
  
  tags = merge(var.tags, {
    Name = "${var.project_name}-logs-bucket"
    Type = "logs"
  })
}

# S3 bucket versioning for content bucket
resource "aws_s3_bucket_versioning" "content_bucket_versioning" {
  bucket = aws_s3_bucket.content_bucket.id
  
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket versioning for logs bucket
resource "aws_s3_bucket_versioning" "logs_bucket_versioning" {
  count = var.enable_cloudfront_logging ? 1 : 0
  
  bucket = aws_s3_bucket.logs_bucket[0].id
  
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket server-side encryption for content bucket
resource "aws_s3_bucket_server_side_encryption_configuration" "content_bucket_encryption" {
  bucket = aws_s3_bucket.content_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# S3 bucket server-side encryption for logs bucket
resource "aws_s3_bucket_server_side_encryption_configuration" "logs_bucket_encryption" {
  count = var.enable_cloudfront_logging ? 1 : 0
  
  bucket = aws_s3_bucket.logs_bucket[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# S3 bucket public access block for content bucket
resource "aws_s3_bucket_public_access_block" "content_bucket_pab" {
  bucket = aws_s3_bucket.content_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket public access block for logs bucket
resource "aws_s3_bucket_public_access_block" "logs_bucket_pab" {
  count = var.enable_cloudfront_logging ? 1 : 0
  
  bucket = aws_s3_bucket.logs_bucket[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# CloudFront Origin Access Control
resource "aws_cloudfront_origin_access_control" "oac" {
  name                              = "${var.project_name}-oac-${random_string.suffix.result}"
  description                       = "OAC for ${var.project_name} CDN content bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# CloudFront distribution
resource "aws_cloudfront_distribution" "cdn_distribution" {
  enabled             = true
  is_ipv6_enabled     = var.enable_ipv6
  comment             = "CDN distribution for ${var.project_name}"
  default_root_object = "index.html"
  price_class         = var.cloudfront_price_class
  
  # Origin configuration
  origin {
    domain_name              = aws_s3_bucket.content_bucket.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.oac.id
    origin_id                = "S3-${aws_s3_bucket.content_bucket.id}"
    
    # Custom origin configuration for S3
    s3_origin_config {
      origin_access_identity = ""
    }
  }
  
  # Default cache behavior for all content
  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-${aws_s3_bucket.content_bucket.id}"
    compress         = var.enable_compression
    
    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
    
    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = var.cloudfront_min_ttl
    default_ttl            = var.cloudfront_default_ttl
    max_ttl                = var.cloudfront_max_ttl
    
    # Response headers policy for security
    response_headers_policy_id = aws_cloudfront_response_headers_policy.security_headers.id
  }
  
  # Cache behavior for CSS files (longer TTL)
  ordered_cache_behavior {
    path_pattern     = "*.css"
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-${aws_s3_bucket.content_bucket.id}"
    compress         = var.enable_compression
    
    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
    
    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 2592000  # 30 days
    max_ttl                = 31536000 # 1 year
  }
  
  # Cache behavior for JavaScript files (longer TTL)
  ordered_cache_behavior {
    path_pattern     = "*.js"
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-${aws_s3_bucket.content_bucket.id}"
    compress         = var.enable_compression
    
    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
    
    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 2592000  # 30 days
    max_ttl                = 31536000 # 1 year
  }
  
  # Cache behavior for images (longer TTL)
  ordered_cache_behavior {
    path_pattern     = "/images/*"
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-${aws_s3_bucket.content_bucket.id}"
    compress         = var.enable_compression
    
    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
    
    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 2592000  # 30 days
    max_ttl                = 31536000 # 1 year
  }
  
  # Cache behavior for API endpoints (shorter TTL)
  ordered_cache_behavior {
    path_pattern     = "/api/*"
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-${aws_s3_bucket.content_bucket.id}"
    compress         = var.enable_compression
    
    forwarded_values {
      query_string = true
      cookies {
        forward = "none"
      }
      headers = ["Authorization", "CloudFront-Forwarded-Proto"]
    }
    
    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600    # 1 hour
    max_ttl                = 86400   # 24 hours
  }
  
  # Geo restrictions (none by default)
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
  
  # SSL/TLS configuration
  viewer_certificate {
    cloudfront_default_certificate = true
    minimum_protocol_version       = "TLSv1.2_2021"
    ssl_support_method             = "sni-only"
  }
  
  # Custom error responses
  custom_error_response {
    error_code         = 404
    response_code      = var.custom_error_response_code
    response_page_path = var.custom_error_response_path
    error_caching_min_ttl = 300
  }
  
  custom_error_response {
    error_code         = 403
    response_code      = var.custom_error_response_code
    response_page_path = var.custom_error_response_path
    error_caching_min_ttl = 300
  }
  
  # Logging configuration
  dynamic "logging_config" {
    for_each = var.enable_cloudfront_logging ? [1] : []
    content {
      include_cookies = false
      bucket          = aws_s3_bucket.logs_bucket[0].bucket_domain_name
      prefix          = "cloudfront-logs/"
    }
  }
  
  tags = merge(var.tags, {
    Name = "${var.project_name}-cloudfront-distribution"
  })
}

# Response headers policy for security
resource "aws_cloudfront_response_headers_policy" "security_headers" {
  name = "${var.project_name}-security-headers-${random_string.suffix.result}"
  
  security_headers_config {
    content_type_options {
      override = true
    }
    frame_options {
      frame_option = "DENY"
      override     = true
    }
    referrer_policy {
      referrer_policy = "strict-origin-when-cross-origin"
      override        = true
    }
    strict_transport_security {
      access_control_max_age_sec = 31536000
      include_subdomains         = true
      preload                    = true
      override                   = true
    }
    content_security_policy {
      content_security_policy = "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; font-src 'self' data:; connect-src 'self'; frame-ancestors 'none';"
      override                = true
    }
  }
}

# S3 bucket policy to allow CloudFront access
resource "aws_s3_bucket_policy" "content_bucket_policy" {
  bucket = aws_s3_bucket.content_bucket.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudFrontServicePrincipal"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.content_bucket.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.cdn_distribution.arn
          }
        }
      }
    ]
  })
}

# Sample content for testing
resource "aws_s3_object" "index_html" {
  bucket       = aws_s3_bucket.content_bucket.id
  key          = "index.html"
  content_type = "text/html"
  
  content = templatefile("${path.module}/templates/index.html", {
    title       = "CloudFront CDN Test"
    timestamp   = timestamp()
    project     = var.project_name
    environment = var.environment
  })
  
  etag = md5(templatefile("${path.module}/templates/index.html", {
    title       = "CloudFront CDN Test"
    timestamp   = timestamp()
    project     = var.project_name
    environment = var.environment
  }))
  
  tags = merge(var.tags, {
    Name = "index-html"
    Type = "content"
  })
}

# Sample CSS file for testing cache behaviors
resource "aws_s3_object" "styles_css" {
  bucket       = aws_s3_bucket.content_bucket.id
  key          = "styles.css"
  content_type = "text/css"
  
  content = file("${path.module}/templates/styles.css")
  etag    = filemd5("${path.module}/templates/styles.css")
  
  tags = merge(var.tags, {
    Name = "styles-css"
    Type = "content"
  })
}

# Sample API response for testing API cache behavior
resource "aws_s3_object" "api_response" {
  bucket       = aws_s3_bucket.content_bucket.id
  key          = "api/response.json"
  content_type = "application/json"
  
  content = jsonencode({
    status = "success"
    data = {
      message   = "API endpoint cached for shorter duration"
      timestamp = timestamp()
      cacheable = true
    }
  })
  
  etag = md5(jsonencode({
    status = "success"
    data = {
      message   = "API endpoint cached for shorter duration"
      timestamp = timestamp()
      cacheable = true
    }
  }))
  
  tags = merge(var.tags, {
    Name = "api-response"
    Type = "content"
  })
}

# Sample image placeholder for testing image cache behavior
resource "aws_s3_object" "image_placeholder" {
  bucket       = aws_s3_bucket.content_bucket.id
  key          = "images/placeholder.txt"
  content_type = "text/plain"
  
  content = file("${path.module}/sample-content/placeholder.txt")
  etag    = filemd5("${path.module}/sample-content/placeholder.txt")
  
  tags = merge(var.tags, {
    Name = "image-placeholder"
    Type = "content"
  })
}

# CloudWatch alarms for monitoring (optional)
resource "aws_cloudwatch_metric_alarm" "high_error_rate" {
  count = var.enable_cloudwatch_monitoring ? 1 : 0
  
  alarm_name          = "CloudFront-HighErrorRate-${aws_cloudfront_distribution.cdn_distribution.id}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "4xxErrorRate"
  namespace           = "AWS/CloudFront"
  period              = "300"
  statistic           = "Average"
  threshold           = var.error_rate_threshold
  alarm_description   = "This metric monitors CloudFront 4xx error rate"
  alarm_actions       = []
  
  dimensions = {
    DistributionId = aws_cloudfront_distribution.cdn_distribution.id
  }
  
  tags = merge(var.tags, {
    Name = "cloudfront-high-error-rate"
  })
}

resource "aws_cloudwatch_metric_alarm" "high_origin_latency" {
  count = var.enable_cloudwatch_monitoring ? 1 : 0
  
  alarm_name          = "CloudFront-HighOriginLatency-${aws_cloudfront_distribution.cdn_distribution.id}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "OriginLatency"
  namespace           = "AWS/CloudFront"
  period              = "300"
  statistic           = "Average"
  threshold           = var.origin_latency_threshold
  alarm_description   = "This metric monitors CloudFront origin latency"
  alarm_actions       = []
  
  dimensions = {
    DistributionId = aws_cloudfront_distribution.cdn_distribution.id
  }
  
  tags = merge(var.tags, {
    Name = "cloudfront-high-origin-latency"
  })
}

# CloudWatch dashboard for monitoring
resource "aws_cloudwatch_dashboard" "cdn_dashboard" {
  count = var.enable_cloudwatch_monitoring ? 1 : 0
  
  dashboard_name = "CloudFront-CDN-Performance-${random_string.suffix.result}"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["AWS/CloudFront", "Requests", "DistributionId", aws_cloudfront_distribution.cdn_distribution.id],
            [".", "BytesDownloaded", ".", "."],
            [".", "4xxErrorRate", ".", "."],
            [".", "5xxErrorRate", ".", "."]
          ]
          period = 300
          stat   = "Sum"
          region = "us-east-1"
          title  = "CloudFront Performance Metrics"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["AWS/CloudFront", "CacheHitRate", "DistributionId", aws_cloudfront_distribution.cdn_distribution.id],
            [".", "OriginLatency", ".", "."]
          ]
          period = 300
          stat   = "Average"
          region = "us-east-1"
          title  = "Cache Performance"
        }
      }
    ]
  })
}