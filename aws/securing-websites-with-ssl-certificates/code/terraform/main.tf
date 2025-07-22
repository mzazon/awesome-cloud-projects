# Main Terraform Configuration for Secure Static Website
# This configuration creates a complete static website hosting solution with SSL/TLS certificates

# Generate random suffix for unique resource names
resource "random_id" "bucket_suffix" {
  byte_length = 3
}

# Data source to get current AWS caller identity
data "aws_caller_identity" "current" {}

# Data source to lookup Route 53 hosted zone (if not provided)
data "aws_route53_zone" "main" {
  count = var.hosted_zone_id == "" ? 1 : 0
  name  = var.domain_name
}

locals {
  # Determine hosted zone ID from variable or data source
  hosted_zone_id = var.hosted_zone_id != "" ? var.hosted_zone_id : data.aws_route53_zone.main[0].zone_id
  
  # Construct full domain names
  subdomain_fqdn = "${var.subdomain_name}.${var.domain_name}"
  bucket_name    = "${var.bucket_name_prefix}-${random_id.bucket_suffix.hex}"
  
  # Common tags for all resources
  common_tags = merge(var.tags, {
    Domain = var.domain_name
  })
}

# S3 Bucket for static website hosting
resource "aws_s3_bucket" "website" {
  bucket = local.bucket_name

  tags = merge(local.common_tags, {
    Name = "Static Website Bucket"
    Type = "S3Storage"
  })
}

# Configure S3 bucket versioning
resource "aws_s3_bucket_versioning" "website" {
  bucket = aws_s3_bucket.website.id
  versioning_configuration {
    status = var.enable_versioning ? "Enabled" : "Suspended"
  }
}

# Configure S3 bucket for static website hosting
resource "aws_s3_bucket_website_configuration" "website" {
  bucket = aws_s3_bucket.website.id

  index_document {
    suffix = var.default_root_object
  }

  error_document {
    key = var.error_document
  }
}

# Block all public access to S3 bucket (security best practice)
resource "aws_s3_bucket_public_access_block" "website" {
  bucket = aws_s3_bucket.website.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Create sample website content
resource "aws_s3_object" "index_html" {
  bucket       = aws_s3_bucket.website.id
  key          = var.default_root_object
  content_type = "text/html"
  content      = templatefile("${path.module}/website_content/index.html.tpl", {
    domain_name = var.domain_name
    timestamp   = timestamp()
  })

  tags = merge(local.common_tags, {
    Name = "Website Index Page"
    Type = "WebContent"
  })
}

resource "aws_s3_object" "error_html" {
  bucket       = aws_s3_bucket.website.id
  key          = var.error_document
  content_type = "text/html"
  content      = file("${path.module}/website_content/error.html")

  tags = merge(local.common_tags, {
    Name = "Website Error Page"
    Type = "WebContent"
  })
}

# Create SSL certificate using AWS Certificate Manager (must be in us-east-1)
resource "aws_acm_certificate" "website" {
  provider = aws.us_east_1

  domain_name               = var.domain_name
  subject_alternative_names = [local.subdomain_fqdn]
  validation_method         = var.certificate_validation_method

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(local.common_tags, {
    Name = "Website SSL Certificate"
    Type = "SSL Certificate"
  })
}

# Create DNS validation records for the certificate
resource "aws_route53_record" "certificate_validation" {
  provider = aws.us_east_1
  for_each = {
    for dvo in aws_acm_certificate.website.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = local.hosted_zone_id
}

# Wait for certificate validation to complete
resource "aws_acm_certificate_validation" "website" {
  provider        = aws.us_east_1
  certificate_arn = aws_acm_certificate.website.arn
  validation_record_fqdns = [
    for record in aws_route53_record.certificate_validation : record.fqdn
  ]

  timeouts {
    create = "10m"
  }
}

# Create CloudFront Origin Access Control (OAC)
resource "aws_cloudfront_origin_access_control" "website" {
  name                              = "OAC-${local.bucket_name}"
  description                       = "Origin Access Control for ${local.bucket_name}"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# Create CloudFront distribution
resource "aws_cloudfront_distribution" "website" {
  depends_on = [aws_acm_certificate_validation.website]

  # Origin configuration for S3 bucket
  origin {
    domain_name              = aws_s3_bucket.website.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.website.id
    origin_id                = "S3-${local.bucket_name}"
  }

  enabled             = true
  is_ipv6_enabled     = var.enable_ipv6
  default_root_object = var.default_root_object
  aliases             = [var.domain_name, local.subdomain_fqdn]
  price_class         = var.price_class

  # Default cache behavior
  default_cache_behavior {
    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "S3-${local.bucket_name}"
    compress               = var.enable_compression
    viewer_protocol_policy = "redirect-to-https"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    min_ttl     = 0
    default_ttl = var.cloudfront_cache_ttl
    max_ttl     = 31536000 # 1 year
  }

  # Custom error responses
  custom_error_response {
    error_code         = 404
    response_code      = 404
    response_page_path = "/${var.error_document}"
  }

  custom_error_response {
    error_code         = 403
    response_code      = 404
    response_page_path = "/${var.error_document}"
  }

  # SSL certificate configuration
  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate.website.arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = var.minimum_protocol_version
  }

  # Geographic restrictions (none by default)
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  tags = merge(local.common_tags, {
    Name = "Website CloudFront Distribution"
    Type = "CDN"
  })
}

# Update S3 bucket policy to allow CloudFront access
resource "aws_s3_bucket_policy" "website" {
  bucket = aws_s3_bucket.website.id
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
        Resource = "${aws_s3_bucket.website.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.website.arn
          }
        }
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.website]
}

# Create DNS A records for the domain and subdomain
resource "aws_route53_record" "website_root" {
  zone_id = local.hosted_zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.website.domain_name
    zone_id                = aws_cloudfront_distribution.website.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "website_subdomain" {
  zone_id = local.hosted_zone_id
  name    = local.subdomain_fqdn
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.website.domain_name
    zone_id                = aws_cloudfront_distribution.website.hosted_zone_id
    evaluate_target_health = false
  }
}

# Optional: Create AAAA records for IPv6 if enabled
resource "aws_route53_record" "website_root_ipv6" {
  count   = var.enable_ipv6 ? 1 : 0
  zone_id = local.hosted_zone_id
  name    = var.domain_name
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.website.domain_name
    zone_id                = aws_cloudfront_distribution.website.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "website_subdomain_ipv6" {
  count   = var.enable_ipv6 ? 1 : 0
  zone_id = local.hosted_zone_id
  name    = local.subdomain_fqdn
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.website.domain_name
    zone_id                = aws_cloudfront_distribution.website.hosted_zone_id
    evaluate_target_health = false
  }
}