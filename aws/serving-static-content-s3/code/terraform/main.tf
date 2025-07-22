# Main Terraform Configuration for Static Website Hosting
# This file contains all the AWS resources needed for hosting a static website
# using S3 for storage and CloudFront for global content delivery

# Get current AWS account and region information
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random string for unique resource naming
resource "random_string" "bucket_suffix" {
  length  = 8
  special = false
  upper   = false
}

# Local values for resource naming and configuration
locals {
  bucket_name      = "${var.project_name}-${var.environment}-${random_string.bucket_suffix.result}"
  logs_bucket_name = "${local.bucket_name}-logs"
  
  # Common tags applied to all resources
  common_tags = merge(var.tags, {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  })

  # CloudFront origin ID
  s3_origin_id = "S3-${local.bucket_name}"

  # Determine if we should create certificate and Route53 records
  create_certificate = var.domain_name != ""
  create_dns_record  = var.create_route53_record && var.domain_name != ""
}

# Data source to find Route 53 hosted zone (if domain is provided)
data "aws_route53_zone" "main" {
  count = local.create_dns_record ? 1 : 0
  name  = var.domain_name
}

#
# S3 Buckets Configuration
#

# Main S3 bucket for website content
resource "aws_s3_bucket" "website" {
  bucket = local.bucket_name

  tags = merge(local.common_tags, {
    Name = "Website Content Bucket"
    Type = "website-content"
  })
}

# S3 bucket for CloudFront access logs
resource "aws_s3_bucket" "logs" {
  count  = var.enable_logging ? 1 : 0
  bucket = local.logs_bucket_name

  tags = merge(local.common_tags, {
    Name = "CloudFront Access Logs"
    Type = "access-logs"
  })
}

# Website configuration for main S3 bucket
resource "aws_s3_bucket_website_configuration" "website" {
  bucket = aws_s3_bucket.website.id

  index_document {
    suffix = var.default_root_object
  }

  error_document {
    key = var.error_document
  }
}

# Block all public access to website bucket (security best practice)
resource "aws_s3_bucket_public_access_block" "website" {
  bucket = aws_s3_bucket.website.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Block all public access to logs bucket
resource "aws_s3_bucket_public_access_block" "logs" {
  count  = var.enable_logging ? 1 : 0
  bucket = aws_s3_bucket.logs[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Enable versioning on website bucket for content management
resource "aws_s3_bucket_versioning" "website" {
  bucket = aws_s3_bucket.website.id
  
  versioning_configuration {
    status = "Enabled"
  }
}

# Server-side encryption for website bucket
resource "aws_s3_bucket_server_side_encryption_configuration" "website" {
  bucket = aws_s3_bucket.website.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Server-side encryption for logs bucket
resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  count  = var.enable_logging ? 1 : 0
  bucket = aws_s3_bucket.logs[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# CORS configuration for website bucket
resource "aws_s3_bucket_cors_configuration" "website" {
  bucket = aws_s3_bucket.website.id

  cors_rule {
    allowed_headers = var.cors_configuration.allowed_headers
    allowed_methods = var.cors_configuration.allowed_methods
    allowed_origins = var.cors_configuration.allowed_origins
    expose_headers  = var.cors_configuration.expose_headers
    max_age_seconds = var.cors_configuration.max_age_seconds
  }
}

#
# CloudFront Configuration
#

# Origin Access Control for secure S3 access
resource "aws_cloudfront_origin_access_control" "website" {
  name                              = "${var.project_name}-${var.environment}-oac"
  description                       = "Origin Access Control for ${local.bucket_name}"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# SSL Certificate for custom domain (if provided)
resource "aws_acm_certificate" "website" {
  count             = local.create_certificate ? 1 : 0
  domain_name       = var.domain_name
  validation_method = "DNS"

  # Certificate must be in us-east-1 for CloudFront
  provider = aws.us_east_1

  tags = merge(local.common_tags, {
    Name = "Website SSL Certificate"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# Route53 record for certificate validation
resource "aws_route53_record" "certificate_validation" {
  for_each = local.create_dns_record ? {
    for dvo in aws_acm_certificate.website[0].domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  } : {}

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.main[0].zone_id
}

# Certificate validation
resource "aws_acm_certificate_validation" "website" {
  count           = local.create_dns_record ? 1 : 0
  certificate_arn = aws_acm_certificate.website[0].arn
  validation_record_fqdns = [
    for record in aws_route53_record.certificate_validation : record.fqdn
  ]

  provider = aws.us_east_1

  timeouts {
    create = "5m"
  }
}

# CloudFront Distribution
resource "aws_cloudfront_distribution" "website" {
  comment             = "CloudFront distribution for ${var.project_name}-${var.environment}"
  default_root_object = var.default_root_object
  enabled             = true
  is_ipv6_enabled     = var.enable_ipv6
  price_class         = var.cloudfront_price_class

  # Custom domain aliases (if provided)
  aliases = var.domain_name != "" ? [var.domain_name] : []

  # S3 origin configuration
  origin {
    domain_name              = aws_s3_bucket.website.bucket_regional_domain_name
    origin_id                = local.s3_origin_id
    origin_access_control_id = aws_cloudfront_origin_access_control.website.id
  }

  # Default cache behavior
  default_cache_behavior {
    target_origin_id       = local.s3_origin_id
    viewer_protocol_policy = var.viewer_protocol_policy
    compress               = var.enable_compression

    allowed_methods = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods  = ["GET", "HEAD"]

    # Use AWS Managed Cache Policy for optimized static content
    cache_policy_id = "658327ea-f89d-4fab-a63d-7e88639e58f6" # Managed-CachingOptimized

    # Use AWS Managed Origin Request Policy
    origin_request_policy_id = "88a5eaf4-2fd4-4709-b370-b4c650ea3fcf" # Managed-CORS-S3Origin

    # Use AWS Managed Response Headers Policy for security headers
    response_headers_policy_id = "67f7725c-6f97-4210-82d7-5512b31e9d03" # Managed-SecurityHeadersPolicy
  }

  # Custom error responses
  custom_error_response {
    error_code         = 404
    response_code      = 404
    response_page_path = "/${var.error_document}"
    error_caching_min_ttl = 300
  }

  custom_error_response {
    error_code         = 403
    response_code      = 404
    response_page_path = "/${var.error_document}"
    error_caching_min_ttl = 300
  }

  # SSL/TLS configuration
  viewer_certificate {
    # Use ACM certificate if domain is provided, otherwise use CloudFront default
    dynamic "acm_certificate_arn" {
      for_each = local.create_certificate ? [1] : []
      content {
        acm_certificate_arn      = local.create_dns_record ? aws_acm_certificate_validation.website[0].certificate_arn : aws_acm_certificate.website[0].arn
        ssl_support_method       = "sni-only"
        minimum_protocol_version = var.minimum_protocol_version
      }
    }

    dynamic "cloudfront_default_certificate" {
      for_each = local.create_certificate ? [] : [1]
      content {
        cloudfront_default_certificate = true
      }
    }
  }

  # Access logging configuration
  dynamic "logging_config" {
    for_each = var.enable_logging ? [1] : []
    content {
      bucket          = aws_s3_bucket.logs[0].bucket_domain_name
      include_cookies = false
      prefix          = "cloudfront-logs/"
    }
  }

  # Geographic restrictions (none by default)
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  tags = merge(local.common_tags, {
    Name = "Website CloudFront Distribution"
  })

  depends_on = [
    aws_s3_bucket.website,
    aws_cloudfront_origin_access_control.website
  ]
}

# S3 bucket policy to allow CloudFront access
resource "aws_s3_bucket_policy" "website" {
  bucket = aws_s3_bucket.website.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudFrontServicePrincipalReadOnly"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.website.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.website.arn
          }
        }
      }
    ]
  })

  depends_on = [
    aws_s3_bucket_public_access_block.website,
    aws_cloudfront_distribution.website
  ]
}

# Route53 alias record for custom domain
resource "aws_route53_record" "website" {
  count   = local.create_dns_record ? 1 : 0
  zone_id = data.aws_route53_zone.main[0].zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.website.domain_name
    zone_id                = aws_cloudfront_distribution.website.hosted_zone_id
    evaluate_target_health = false
  }
}

# Create AAAA record for IPv6 support (if enabled)
resource "aws_route53_record" "website_ipv6" {
  count   = local.create_dns_record && var.enable_ipv6 ? 1 : 0
  zone_id = data.aws_route53_zone.main[0].zone_id
  name    = var.domain_name
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.website.domain_name
    zone_id                = aws_cloudfront_distribution.website.hosted_zone_id
    evaluate_target_health = false
  }
}

#
# Sample Website Content (Optional)
#

# Upload sample index.html file
resource "aws_s3_object" "index" {
  bucket       = aws_s3_bucket.website.id
  key          = "index.html"
  content_type = "text/html"
  
  content = <<-EOT
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Welcome to ${var.project_name}</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            line-height: 1.6;
            margin: 0;
            padding: 0;
            background-color: #f4f4f4;
            display: flex;
            justify-content: center;
            align-items: center;
            height: 100vh;
        }
        .container {
            max-width: 800px;
            margin: 0 auto;
            padding: 30px;
            background-color: white;
            border-radius: 8px;
            box-shadow: 0 2px 10px rgba(0, 0, 0, 0.1);
            text-align: center;
        }
        h1 {
            color: #ff9900;
            margin-bottom: 20px;
        }
        .info {
            background-color: #f8f9fa;
            padding: 20px;
            border-radius: 5px;
            margin: 20px 0;
        }
        .deployment-info {
            font-size: 14px;
            color: #666;
            margin-top: 30px;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🚀 Welcome to Your Static Website!</h1>
        <p>This static website is successfully hosted on Amazon S3 and delivered via CloudFront.</p>
        
        <div class="info">
            <h3>✅ Infrastructure Deployed</h3>
            <p><strong>Project:</strong> ${var.project_name}</p>
            <p><strong>Environment:</strong> ${var.environment}</p>
            <p><strong>Region:</strong> ${var.aws_region}</p>
            ${var.domain_name != "" ? "<p><strong>Custom Domain:</strong> ${var.domain_name}</p>" : ""}
        </div>
        
        <div class="deployment-info">
            <p>🏗️ Deployed with Terraform</p>
            <p>📦 Content stored in Amazon S3</p>
            <p>🌐 Delivered via Amazon CloudFront</p>
            <p>🔒 Secured with HTTPS</p>
        </div>
        
        <p><em>You can now upload your own content to replace this default page!</em></p>
    </div>
</body>
</html>
EOT

  tags = merge(local.common_tags, {
    Name = "Website Index Page"
    Type = "web-content"
  })
}

# Upload sample error.html file
resource "aws_s3_object" "error" {
  bucket       = aws_s3_bucket.website.id
  key          = "error.html"
  content_type = "text/html"
  
  content = <<-EOT
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Page Not Found - ${var.project_name}</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            line-height: 1.6;
            margin: 0;
            padding: 0;
            background-color: #f4f4f4;
            display: flex;
            justify-content: center;
            align-items: center;
            height: 100vh;
        }
        .container {
            max-width: 600px;
            margin: 0 auto;
            padding: 30px;
            background-color: white;
            border-radius: 8px;
            box-shadow: 0 2px 10px rgba(0, 0, 0, 0.1);
            text-align: center;
        }
        h1 {
            color: #e74c3c;
            margin-bottom: 20px;
        }
        .error-code {
            font-size: 72px;
            font-weight: bold;
            color: #ff9900;
            margin: 20px 0;
        }
        a {
            color: #ff9900;
            text-decoration: none;
        }
        a:hover {
            text-decoration: underline;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="error-code">404</div>
        <h1>Page Not Found</h1>
        <p>Sorry, the page you're looking for doesn't exist.</p>
        <p>It might have been moved, deleted, or you entered the wrong URL.</p>
        <p><a href="/">← Return to Homepage</a></p>
    </div>
</body>
</html>
EOT

  tags = merge(local.common_tags, {
    Name = "Website Error Page"
    Type = "web-content"
  })
}