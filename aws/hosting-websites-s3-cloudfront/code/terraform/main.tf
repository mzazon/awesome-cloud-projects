# Static Website Hosting with S3, CloudFront, and Route 53
# This configuration creates a globally distributed static website with SSL/TLS encryption

# Local values for computed configurations
locals {
  www_domain_name = "${var.subdomain}.${var.domain_name}"
  
  # Common tags for all resources
  common_tags = merge(var.tags, {
    Name = "static-website-${var.domain_name}"
  })
}

# Random suffix for S3 bucket names (S3 buckets must be globally unique)
resource "random_string" "bucket_suffix" {
  length  = 8
  special = false
  upper   = false
}

# Data source for existing Route 53 hosted zone (if not creating new one)
data "aws_route53_zone" "main" {
  count = var.create_route53_zone ? 0 : 1
  
  zone_id = var.route53_zone_id
}

# Create Route 53 hosted zone for the domain (optional)
resource "aws_route53_zone" "main" {
  count = var.create_route53_zone ? 1 : 0
  
  name = var.domain_name
  
  tags = merge(local.common_tags, {
    Description = "Hosted zone for ${var.domain_name}"
  })
}

# S3 bucket for www subdomain (main website hosting)
resource "aws_s3_bucket" "www_bucket" {
  bucket = "${local.www_domain_name}-${random_string.bucket_suffix.result}"
  
  tags = merge(local.common_tags, {
    Purpose = "Main website hosting bucket"
  })
}

# S3 bucket for root domain (redirect to www)
resource "aws_s3_bucket" "root_bucket" {
  bucket = "${var.domain_name}-${random_string.bucket_suffix.result}"
  
  tags = merge(local.common_tags, {
    Purpose = "Root domain redirect bucket"
  })
}

# Configure www bucket for static website hosting
resource "aws_s3_bucket_website_configuration" "www_bucket" {
  bucket = aws_s3_bucket.www_bucket.id
  
  index_document {
    suffix = var.index_document
  }
  
  error_document {
    key = var.error_document
  }
}

# Configure root bucket to redirect to www subdomain
resource "aws_s3_bucket_website_configuration" "root_bucket" {
  bucket = aws_s3_bucket.root_bucket.id
  
  redirect_all_requests_to {
    host_name = local.www_domain_name
    protocol  = "https"
  }
}

# Block public access settings for www bucket (will be overridden by bucket policy)
resource "aws_s3_bucket_public_access_block" "www_bucket" {
  bucket = aws_s3_bucket.www_bucket.id
  
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# Block public access settings for root bucket (for redirects)
resource "aws_s3_bucket_public_access_block" "root_bucket" {
  bucket = aws_s3_bucket.root_bucket.id
  
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# S3 bucket policy for www bucket (allow public read access)
resource "aws_s3_bucket_policy" "www_bucket_policy" {
  bucket = aws_s3_bucket.www_bucket.id
  
  depends_on = [aws_s3_bucket_public_access_block.www_bucket]
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.www_bucket.arn}/*"
      }
    ]
  })
}

# SSL/TLS certificate for CloudFront (must be in us-east-1)
resource "aws_acm_certificate" "cert" {
  provider = aws.us_east_1
  
  domain_name       = var.domain_name
  subject_alternative_names = [local.www_domain_name]
  validation_method = "DNS"
  
  lifecycle {
    create_before_destroy = true
  }
  
  tags = merge(local.common_tags, {
    Purpose = "SSL certificate for CloudFront"
  })
}

# Route 53 records for certificate validation
resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.cert.domain_validation_options : dvo.domain_name => {
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
  zone_id         = var.create_route53_zone ? aws_route53_zone.main[0].zone_id : data.aws_route53_zone.main[0].zone_id
}

# Certificate validation waiter
resource "aws_acm_certificate_validation" "cert" {
  provider = aws.us_east_1
  
  certificate_arn         = aws_acm_certificate.cert.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
  
  timeouts {
    create = "5m"
  }
}

# CloudFront Origin Access Control for S3 bucket
resource "aws_cloudfront_origin_access_control" "www_bucket_oac" {
  name                              = "OAC-${aws_s3_bucket.www_bucket.id}"
  description                       = "Origin Access Control for ${local.www_domain_name}"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# CloudFront distribution for www subdomain
resource "aws_cloudfront_distribution" "www_distribution" {
  depends_on = [aws_acm_certificate_validation.cert]
  
  origin {
    domain_name              = aws_s3_bucket.www_bucket.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.www_bucket_oac.id
    origin_id                = "S3-${aws_s3_bucket.www_bucket.id}"
  }
  
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = var.index_document
  
  aliases = [local.www_domain_name]
  
  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-${aws_s3_bucket.www_bucket.id}"
    
    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
    
    viewer_protocol_policy = "redirect-to-https"
    compress               = var.enable_compression
    min_ttl                = 0
    default_ttl            = var.default_ttl
    max_ttl                = var.max_ttl
  }
  
  # Custom error responses for single-page applications
  custom_error_response {
    error_code         = 404
    response_code      = 200
    response_page_path = "/${var.index_document}"
  }
  
  custom_error_response {
    error_code         = 403
    response_code      = 200
    response_page_path = "/${var.index_document}"
  }
  
  price_class = var.cloudfront_price_class
  
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
  
  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate.cert.arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = var.minimum_protocol_version
  }
  
  tags = merge(local.common_tags, {
    Purpose = "CloudFront distribution for ${local.www_domain_name}"
  })
}

# Update S3 bucket policy to allow CloudFront access
resource "aws_s3_bucket_policy" "www_bucket_policy_updated" {
  bucket = aws_s3_bucket.www_bucket.id
  
  depends_on = [
    aws_s3_bucket_public_access_block.www_bucket,
    aws_cloudfront_distribution.www_distribution
  ]
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowCloudFrontServicePrincipal"
        Effect    = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.www_bucket.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.www_distribution.arn
          }
        }
      }
    ]
  })
}

# CloudFront distribution for root domain redirect
resource "aws_cloudfront_distribution" "root_distribution" {
  depends_on = [aws_acm_certificate_validation.cert]
  
  origin {
    domain_name = aws_s3_bucket_website_configuration.root_bucket.website_endpoint
    origin_id   = "S3-Website-${aws_s3_bucket.root_bucket.id}"
    
    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }
  
  enabled         = true
  is_ipv6_enabled = true
  
  aliases = [var.domain_name]
  
  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-Website-${aws_s3_bucket.root_bucket.id}"
    
    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
    
    viewer_protocol_policy = "redirect-to-https"
    compress               = true
    min_ttl                = 0
    default_ttl            = 86400
    max_ttl                = 31536000
  }
  
  price_class = var.cloudfront_price_class
  
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
  
  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate.cert.arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = var.minimum_protocol_version
  }
  
  tags = merge(local.common_tags, {
    Purpose = "CloudFront distribution for root domain redirect"
  })
}

# Route 53 A record for www subdomain (alias to CloudFront)
resource "aws_route53_record" "www" {
  zone_id = var.create_route53_zone ? aws_route53_zone.main[0].zone_id : data.aws_route53_zone.main[0].zone_id
  name    = local.www_domain_name
  type    = "A"
  
  alias {
    name                   = aws_cloudfront_distribution.www_distribution.domain_name
    zone_id                = aws_cloudfront_distribution.www_distribution.hosted_zone_id
    evaluate_target_health = false
  }
}

# Route 53 A record for root domain (alias to CloudFront)
resource "aws_route53_record" "root" {
  zone_id = var.create_route53_zone ? aws_route53_zone.main[0].zone_id : data.aws_route53_zone.main[0].zone_id
  name    = var.domain_name
  type    = "A"
  
  alias {
    name                   = aws_cloudfront_distribution.root_distribution.domain_name
    zone_id                = aws_cloudfront_distribution.root_distribution.hosted_zone_id
    evaluate_target_health = false
  }
}

# Route 53 AAAA record for www subdomain (IPv6 support)
resource "aws_route53_record" "www_ipv6" {
  zone_id = var.create_route53_zone ? aws_route53_zone.main[0].zone_id : data.aws_route53_zone.main[0].zone_id
  name    = local.www_domain_name
  type    = "AAAA"
  
  alias {
    name                   = aws_cloudfront_distribution.www_distribution.domain_name
    zone_id                = aws_cloudfront_distribution.www_distribution.hosted_zone_id
    evaluate_target_health = false
  }
}

# Route 53 AAAA record for root domain (IPv6 support)
resource "aws_route53_record" "root_ipv6" {
  zone_id = var.create_route53_zone ? aws_route53_zone.main[0].zone_id : data.aws_route53_zone.main[0].zone_id
  name    = var.domain_name
  type    = "AAAA"
  
  alias {
    name                   = aws_cloudfront_distribution.root_distribution.domain_name
    zone_id                = aws_cloudfront_distribution.root_distribution.hosted_zone_id
    evaluate_target_health = false
  }
}

# Sample website content files
resource "aws_s3_object" "index_html" {
  bucket       = aws_s3_bucket.www_bucket.id
  key          = var.index_document
  content_type = "text/html"
  
  content = templatefile("${path.module}/templates/index.html", {
    domain_name = var.domain_name
  })
  
  tags = merge(local.common_tags, {
    Purpose = "Website index document"
  })
}

resource "aws_s3_object" "error_html" {
  bucket       = aws_s3_bucket.www_bucket.id
  key          = var.error_document
  content_type = "text/html"
  
  content = templatefile("${path.module}/templates/error.html", {
    domain_name = var.domain_name
  })
  
  tags = merge(local.common_tags, {
    Purpose = "Website error document"
  })
}

# Create templates directory and files
resource "local_file" "index_template" {
  filename = "${path.module}/templates/index.html"
  content  = <<-EOF
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Welcome to ${domain_name}</title>
        <style>
            body { font-family: Arial, sans-serif; margin: 40px; 
                   text-align: center; background-color: #f0f8ff; }
            h1 { color: #2c3e50; }
            p { color: #7f8c8d; font-size: 18px; }
            .container { max-width: 800px; margin: 0 auto; }
            .footer { margin-top: 40px; font-size: 14px; color: #95a5a6; }
        </style>
    </head>
    <body>
        <div class="container">
            <h1>Welcome to ${domain_name}</h1>
            <p>Your static website is now live with global CDN delivery!</p>
            <p>Powered by AWS S3, CloudFront, and Route 53</p>
            <div class="footer">
                <p>Deployed with Terraform Infrastructure as Code</p>
            </div>
        </div>
    </body>
    </html>
  EOF
}

resource "local_file" "error_template" {
  filename = "${path.module}/templates/error.html"
  content  = <<-EOF
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Page Not Found - ${domain_name}</title>
        <style>
            body { font-family: Arial, sans-serif; margin: 40px; 
                   text-align: center; background-color: #fff5f5; }
            h1 { color: #e74c3c; }
            p { color: #7f8c8d; font-size: 18px; }
            .container { max-width: 800px; margin: 0 auto; }
            a { color: #3498db; text-decoration: none; }
            a:hover { text-decoration: underline; }
        </style>
    </head>
    <body>
        <div class="container">
            <h1>404 - Page Not Found</h1>
            <p>The page you're looking for doesn't exist.</p>
            <a href="/">Return to Home</a>
        </div>
    </body>
    </html>
  EOF
}