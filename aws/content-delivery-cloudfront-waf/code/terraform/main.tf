# Secure Content Delivery with CloudFront and AWS WAF Infrastructure

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 4
}

# Data source to get current AWS caller identity
data "aws_caller_identity" "current" {}

# Data source to get current AWS region
data "aws_region" "current" {}

# S3 bucket for content storage with security best practices
resource "aws_s3_bucket" "content" {
  bucket = "${var.bucket_name_prefix}-${random_id.suffix.hex}"

  tags = merge(var.tags, {
    Name        = "${var.project_name}-content-bucket"
    Purpose     = "Static content storage for CloudFront distribution"
    Environment = var.environment
  })
}

# S3 bucket public access block - ensure bucket is private
resource "aws_s3_bucket_public_access_block" "content" {
  bucket = aws_s3_bucket.content.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket server-side encryption configuration
resource "aws_s3_bucket_server_side_encryption_configuration" "content" {
  bucket = aws_s3_bucket.content.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# S3 bucket versioning configuration
resource "aws_s3_bucket_versioning" "content" {
  bucket = aws_s3_bucket.content.id

  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket lifecycle configuration
resource "aws_s3_bucket_lifecycle_configuration" "content" {
  bucket = aws_s3_bucket.content.id

  rule {
    id     = "delete_old_versions"
    status = "Enabled"

    noncurrent_version_expiration {
      noncurrent_days = 30
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# Optional: Create sample content for testing
resource "aws_s3_object" "sample_content" {
  count = var.create_sample_content ? 1 : 0

  bucket       = aws_s3_bucket.content.id
  key          = "index.html"
  content_type = "text/html"
  content = <<-HTML
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Secure Content Test</title>
        <style>
            body { font-family: Arial, sans-serif; margin: 40px; background-color: #f5f5f5; }
            .container { max-width: 800px; margin: 0 auto; background: white; padding: 40px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
            h1 { color: #2c3e50; border-bottom: 3px solid #3498db; padding-bottom: 10px; }
            .status { padding: 15px; margin: 20px 0; border-radius: 5px; }
            .success { background-color: #d4edda; border: 1px solid #c3e6cb; color: #155724; }
            .info { background-color: #d1ecf1; border: 1px solid #bee5eb; color: #0c5460; }
        </style>
    </head>
    <body>
        <div class="container">
            <h1>🛡️ Secure Content Delivery Test</h1>
            <div class="status success">
                <strong>✅ Success!</strong> This content is protected by AWS WAF and delivered through CloudFront.
            </div>
            <div class="status info">
                <strong>ℹ️ Security Features:</strong>
                <ul>
                    <li>AWS WAF protection against common web threats</li>
                    <li>Rate-based rules for DDoS protection</li>
                    <li>Geographic restrictions (if enabled)</li>
                    <li>HTTPS enforcement</li>
                    <li>Origin Access Control for S3 protection</li>
                </ul>
            </div>
            <p><strong>Distribution Domain:</strong> ${aws_cloudfront_distribution.main.domain_name}</p>
            <p><strong>Environment:</strong> ${var.environment}</p>
            <p><strong>Deployment Time:</strong> ${timestamp()}</p>
        </div>
    </body>
    </html>
  HTML

  tags = merge(var.tags, {
    Name        = "sample-content"
    Purpose     = "Testing content for CloudFront distribution"
    Environment = var.environment
  })
}

# CloudWatch Log Group for WAF logs (optional)
resource "aws_cloudwatch_log_group" "waf_logs" {
  count = var.enable_waf_logging ? 1 : 0

  name              = "/aws/wafv2/${var.project_name}-${var.environment}"
  retention_in_days = var.cloudwatch_log_retention_days

  tags = merge(var.tags, {
    Name        = "${var.project_name}-waf-logs"
    Purpose     = "WAF access logs"
    Environment = var.environment
  })
}

# AWS WAF Web ACL for CloudFront protection
resource "aws_wafv2_web_acl" "main" {
  provider = aws.us_east_1 # WAF for CloudFront must be in us-east-1

  name        = "${var.project_name}-web-acl-${var.environment}"
  description = "WAF Web ACL for CloudFront distribution security"
  scope       = "CLOUDFRONT"

  default_action {
    allow {}
  }

  # Rate-based rule for DDoS protection
  rule {
    name     = "RateLimitRule"
    priority = 0

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = var.waf_rate_limit
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                 = "RateLimitRule"
      sampled_requests_enabled    = true
    }
  }

  # AWS Managed Rules
  dynamic "rule" {
    for_each = var.waf_managed_rules

    content {
      name     = rule.value.name
      priority = rule.value.priority

      dynamic "action" {
        for_each = rule.value.action == "allow" ? [1] : []
        content {
          allow {}
        }
      }

      dynamic "action" {
        for_each = rule.value.action == "block" ? [1] : []
        content {
          block {}
        }
      }

      dynamic "action" {
        for_each = rule.value.action == "count" ? [1] : []
        content {
          count {}
        }
      }

      override_action {
        none {}
      }

      statement {
        managed_rule_group_statement {
          name        = rule.value.name
          vendor_name = "AWS"
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                 = rule.value.name
        sampled_requests_enabled    = true
      }
    }
  }

  # Optional WAF logging configuration
  dynamic "logging_configuration" {
    for_each = var.enable_waf_logging ? [1] : []

    content {
      log_destination_configs = [aws_cloudwatch_log_group.waf_logs[0].arn]

      redacted_fields {
        single_header {
          name = "authorization"
        }
      }

      redacted_fields {
        single_header {
          name = "cookie"
        }
      }
    }
  }

  tags = merge(var.tags, {
    Name        = "${var.project_name}-web-acl"
    Purpose     = "WAF protection for CloudFront distribution"
    Environment = var.environment
  })
}

# CloudFront Origin Access Control for S3
resource "aws_cloudfront_origin_access_control" "main" {
  name                              = "${var.project_name}-oac-${var.environment}"
  description                       = "Origin Access Control for S3 bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# CloudFront Distribution with WAF protection
resource "aws_cloudfront_distribution" "main" {
  comment             = "Secure CloudFront distribution with WAF protection"
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  price_class         = var.cloudfront_price_class
  web_acl_id          = aws_wafv2_web_acl.main.arn

  # S3 Origin configuration
  origin {
    domain_name              = aws_s3_bucket.content.bucket_regional_domain_name
    origin_id                = "S3-${aws_s3_bucket.content.id}"
    origin_access_control_id = aws_cloudfront_origin_access_control.main.id
  }

  # Default cache behavior
  default_cache_behavior {
    target_origin_id         = "S3-${aws_s3_bucket.content.id}"
    viewer_protocol_policy   = "redirect-to-https"
    cache_policy_id          = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad" # Managed-CachingOptimized
    origin_request_policy_id = "88a5eaf4-2fd4-4709-b370-b4c650ea3fcf" # Managed-CORS-S3Origin
    compress                 = true
    allowed_methods          = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods           = ["GET", "HEAD"]
  }

  # Additional cache behaviors
  dynamic "ordered_cache_behavior" {
    for_each = var.cache_behaviors

    content {
      path_pattern             = ordered_cache_behavior.value.path_pattern
      target_origin_id         = ordered_cache_behavior.value.target_origin_id
      viewer_protocol_policy   = ordered_cache_behavior.value.viewer_protocol_policy
      cache_policy_id          = ordered_cache_behavior.value.cache_policy_id
      compress                 = ordered_cache_behavior.value.compress
      allowed_methods          = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
      cached_methods           = ["GET", "HEAD"]
    }
  }

  # Geographic restrictions
  restrictions {
    geo_restriction {
      restriction_type = var.enable_geo_restrictions && length(var.blocked_countries) > 0 ? "blacklist" : "none"
      locations        = var.enable_geo_restrictions ? var.blocked_countries : []
    }
  }

  # SSL/TLS configuration
  viewer_certificate {
    cloudfront_default_certificate = true
    minimum_protocol_version       = "TLSv1.2_2021"
    ssl_support_method             = "vip" # Use sni-only for custom certificates
  }

  # Custom error responses
  dynamic "custom_error_response" {
    for_each = var.custom_error_responses

    content {
      error_code            = custom_error_response.value.error_code
      response_code         = custom_error_response.value.response_code
      response_page_path    = custom_error_response.value.response_page_path
      error_caching_min_ttl = custom_error_response.value.error_caching_min_ttl
    }
  }

  # Optional access logging
  dynamic "logging_config" {
    for_each = var.enable_cloudfront_logging ? [1] : []

    content {
      bucket          = aws_s3_bucket.cloudfront_logs[0].bucket_domain_name
      include_cookies = false
      prefix          = "cloudfront-logs/"
    }
  }

  tags = merge(var.tags, {
    Name        = "${var.project_name}-distribution"
    Purpose     = "Secure content delivery with WAF protection"
    Environment = var.environment
  })

  # Ensure WAF is created before CloudFront distribution
  depends_on = [aws_wafv2_web_acl.main]
}

# Optional: S3 bucket for CloudFront access logs
resource "aws_s3_bucket" "cloudfront_logs" {
  count = var.enable_cloudfront_logging ? 1 : 0

  bucket = "${var.bucket_name_prefix}-logs-${random_id.suffix.hex}"

  tags = merge(var.tags, {
    Name        = "${var.project_name}-cloudfront-logs"
    Purpose     = "CloudFront access logs storage"
    Environment = var.environment
  })
}

resource "aws_s3_bucket_public_access_block" "cloudfront_logs" {
  count = var.enable_cloudfront_logging ? 1 : 0

  bucket = aws_s3_bucket.cloudfront_logs[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket policy for CloudFront Origin Access Control
resource "aws_s3_bucket_policy" "content" {
  bucket = aws_s3_bucket.content.id

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
        Resource = "${aws_s3_bucket.content.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.main.arn
          }
        }
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.content]
}

# CloudWatch dashboard for monitoring (optional)
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.project_name}-security-dashboard-${var.environment}"

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
            ["AWS/CloudFront", "Requests", "DistributionId", aws_cloudfront_distribution.main.id],
            [".", "BytesDownloaded", ".", "."],
            [".", "4xxErrorRate", ".", "."],
            [".", "5xxErrorRate", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = "us-east-1"
          title   = "CloudFront Metrics"
          period  = 300
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["AWS/WAFV2", "AllowedRequests", "WebACL", aws_wafv2_web_acl.main.name, "Region", "CloudFront", "Rule", "ALL"],
            [".", "BlockedRequests", ".", ".", ".", ".", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = "us-east-1"
          title   = "WAF Metrics"
          period  = 300
        }
      }
    ]
  })

  tags = merge(var.tags, {
    Name        = "${var.project_name}-dashboard"
    Purpose     = "Monitoring dashboard for secure content delivery"
    Environment = var.environment
  })
}