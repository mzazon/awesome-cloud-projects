# CloudFront CDN with Origin Access Control Infrastructure
# This Terraform configuration creates a secure, global content delivery network
# using Amazon CloudFront with Origin Access Control (OAC) for S3 origins

# Data sources for current AWS account and region information
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  # Common naming convention using project name and random suffix
  name_suffix = "${var.project_name}-${random_id.suffix.hex}"
  
  # S3 bucket names with globally unique identifiers
  content_bucket_name = "${var.bucket_name_prefix}-${random_id.suffix.hex}"
  logs_bucket_name    = "${var.bucket_name_prefix}-logs-${random_id.suffix.hex}"
  
  # Common tags merged with user-provided tags
  common_tags = merge(
    {
      Environment = var.environment
      Project     = var.project_name
      ManagedBy   = "Terraform"
      Recipe      = "content-delivery-networks-cloudfront-origin-access-controls"
    },
    var.tags
  )
}

# ============================================================================
# S3 BUCKETS FOR CONTENT AND LOGGING
# ============================================================================

# Primary S3 bucket for storing content that will be served through CloudFront
resource "aws_s3_bucket" "content" {
  bucket = local.content_bucket_name

  tags = merge(local.common_tags, {
    Name        = "${local.name_suffix}-content"
    Description = "Primary content bucket for CloudFront CDN"
  })
}

# S3 bucket for storing CloudFront access logs
resource "aws_s3_bucket" "logs" {
  count = var.enable_logging ? 1 : 0

  bucket = local.logs_bucket_name

  tags = merge(local.common_tags, {
    Name        = "${local.name_suffix}-logs"
    Description = "CloudFront access logs storage"
  })
}

# Block all public access to the content bucket - security best practice
resource "aws_s3_bucket_public_access_block" "content" {
  bucket = aws_s3_bucket.content.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Block all public access to the logs bucket
resource "aws_s3_bucket_public_access_block" "logs" {
  count = var.enable_logging ? 1 : 0

  bucket = aws_s3_bucket.logs[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Enable versioning on content bucket for better content management
resource "aws_s3_bucket_versioning" "content" {
  bucket = aws_s3_bucket.content.id
  
  versioning_configuration {
    status = "Enabled"
  }
}

# Server-side encryption for content bucket using AES256
resource "aws_s3_bucket_server_side_encryption_configuration" "content" {
  bucket = aws_s3_bucket.content.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# Server-side encryption for logs bucket
resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  count = var.enable_logging ? 1 : 0

  bucket = aws_s3_bucket.logs[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# ============================================================================
# ORIGIN ACCESS CONTROL (OAC)
# ============================================================================

# Create Origin Access Control for secure S3 access
# OAC is the modern replacement for Origin Access Identity (OAI)
resource "aws_cloudfront_origin_access_control" "main" {
  name                              = "${local.name_suffix}-oac"
  description                       = "Origin Access Control for ${local.content_bucket_name}"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# ============================================================================
# AWS WAF WEB ACL FOR SECURITY
# ============================================================================

# Create WAF Web ACL for CloudFront protection
resource "aws_wafv2_web_acl" "main" {
  count = var.enable_waf ? 1 : 0

  name  = "${local.name_suffix}-waf"
  scope = "CLOUDFRONT"

  default_action {
    allow {}
  }

  # AWS Managed Rules - Common Rule Set for basic protection
  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "CommonRuleSetMetric"
      sampled_requests_enabled   = true
    }
  }

  # Rate limiting rule to prevent abuse
  rule {
    name     = "RateLimitRule"
    priority = 2

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
      metric_name                = "RateLimitMetric"
      sampled_requests_enabled   = true
    }
  }

  # AWS Managed Rules - Known Bad Inputs
  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 3

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "KnownBadInputsMetric"
      sampled_requests_enabled   = true
    }
  }

  tags = merge(local.common_tags, {
    Name        = "${local.name_suffix}-waf"
    Description = "WAF Web ACL for CloudFront protection"
  })

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "CDNWebACL"
    sampled_requests_enabled   = true
  }
}

# ============================================================================
# CLOUDFRONT DISTRIBUTION
# ============================================================================

# CloudFront distribution with multiple cache behaviors and security features
resource "aws_cloudfront_distribution" "main" {
  comment             = "CDN Distribution for ${var.project_name}"
  default_root_object = "index.html"
  enabled             = true
  http_version        = "http2and3"
  is_ipv6_enabled     = true
  price_class         = var.price_class
  web_acl_id          = var.enable_waf ? aws_wafv2_web_acl.main[0].arn : null

  # S3 origin configuration with Origin Access Control
  origin {
    domain_name              = aws_s3_bucket.content.bucket_regional_domain_name
    origin_id                = local.content_bucket_name
    origin_access_control_id = aws_cloudfront_origin_access_control.main.id

    connection_attempts = 3
    connection_timeout  = 10
  }

  # Default cache behavior for all content
  default_cache_behavior {
    target_origin_id       = local.content_bucket_name
    viewer_protocol_policy = "redirect-to-https"
    compress               = true

    # Use AWS managed cache policy for optimal caching
    cache_policy_id = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad" # Managed-CachingOptimized

    # Use AWS managed origin request policy
    origin_request_policy_id = "88a5eaf4-2fd4-4709-b370-b4c650ea3fcf" # Managed-CORS-S3Origin

    # Use AWS managed response headers policy for security
    response_headers_policy_id = "5cc3b908-e619-4b99-88e5-2cf7f45965bd" # Managed-SecurityHeadersPolicy

    allowed_methods = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods  = ["GET", "HEAD"]

    trusted_signers    = []
    trusted_key_groups = []
  }

  # Optimized cache behavior for images with long TTL
  ordered_cache_behavior {
    path_pattern           = "/images/*"
    target_origin_id       = local.content_bucket_name
    viewer_protocol_policy = "redirect-to-https"
    compress               = true

    cache_policy_id = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad" # Managed-CachingOptimized

    allowed_methods = ["GET", "HEAD"]
    cached_methods  = ["GET", "HEAD"]

    trusted_signers    = []
    trusted_key_groups = []
  }

  # Optimized cache behavior for CSS files
  ordered_cache_behavior {
    path_pattern           = "/css/*"
    target_origin_id       = local.content_bucket_name
    viewer_protocol_policy = "redirect-to-https"
    compress               = true

    cache_policy_id = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad" # Managed-CachingOptimized

    allowed_methods = ["GET", "HEAD"]
    cached_methods  = ["GET", "HEAD"]

    trusted_signers    = []
    trusted_key_groups = []
  }

  # Optimized cache behavior for JavaScript files
  ordered_cache_behavior {
    path_pattern           = "/js/*"
    target_origin_id       = local.content_bucket_name
    viewer_protocol_policy = "redirect-to-https"
    compress               = true

    cache_policy_id = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad" # Managed-CachingOptimized

    allowed_methods = ["GET", "HEAD"]
    cached_methods  = ["GET", "HEAD"]

    trusted_signers    = []
    trusted_key_groups = []
  }

  # Custom error responses for single-page applications
  custom_error_response {
    error_code         = 404
    response_code      = 200
    response_page_path = "/index.html"
    error_caching_min_ttl = 300
  }

  custom_error_response {
    error_code         = 403
    response_code      = 200
    response_page_path = "/index.html"
    error_caching_min_ttl = 300
  }

  # Geo restrictions configuration
  restrictions {
    geo_restriction {
      restriction_type = var.geo_restriction_type
      locations        = var.geo_restriction_locations
    }
  }

  # SSL/TLS configuration
  viewer_certificate {
    # Use custom certificate if provided, otherwise use CloudFront default
    acm_certificate_arn            = var.custom_domain != "" ? var.certificate_arn : null
    cloudfront_default_certificate = var.custom_domain == "" ? true : null
    minimum_protocol_version       = var.minimum_protocol_version
    ssl_support_method             = var.custom_domain != "" ? "sni-only" : null
  }

  # Custom domain configuration if provided
  dynamic "aliases" {
    for_each = var.custom_domain != "" ? [var.custom_domain] : []
    content {
      aliases = [var.custom_domain]
    }
  }

  # CloudFront access logging configuration
  dynamic "logging_config" {
    for_each = var.enable_logging ? [1] : []
    content {
      bucket          = aws_s3_bucket.logs[0].bucket_domain_name
      include_cookies = false
      prefix          = "cloudfront-logs/"
    }
  }

  tags = merge(local.common_tags, {
    Name        = "${local.name_suffix}-distribution"
    Description = "CloudFront distribution for global content delivery"
  })

  # Ensure OAC and WAF are created before distribution
  depends_on = [
    aws_cloudfront_origin_access_control.main,
    aws_wafv2_web_acl.main
  ]
}

# ============================================================================
# S3 BUCKET POLICY FOR ORIGIN ACCESS CONTROL
# ============================================================================

# IAM policy document allowing CloudFront to access S3 bucket via OAC
data "aws_iam_policy_document" "s3_policy" {
  statement {
    sid    = "AllowCloudFrontServicePrincipalReadOnly"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    actions = [
      "s3:GetObject"
    ]

    resources = [
      "${aws_s3_bucket.content.arn}/*"
    ]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.main.arn]
    }
  }
}

# Apply the bucket policy to allow CloudFront access
resource "aws_s3_bucket_policy" "content" {
  bucket = aws_s3_bucket.content.id
  policy = data.aws_iam_policy_document.s3_policy.json

  depends_on = [aws_cloudfront_distribution.main]
}

# ============================================================================
# SAMPLE CONTENT UPLOAD
# ============================================================================

# Upload sample HTML content
resource "aws_s3_object" "index_html" {
  bucket       = aws_s3_bucket.content.id
  key          = "index.html"
  content_type = "text/html"

  content = <<-EOT
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>CloudFront CDN Test Page</title>
    <link rel="stylesheet" href="/css/styles.css">
</head>
<body>
    <div class="container">
        <h1>CloudFront CDN Test</h1>
        <p>This page is being served through Amazon CloudFront's global edge network.</p>
        <div class="features">
            <h2>Features Enabled:</h2>
            <ul>
                <li>✅ Origin Access Control (OAC) Security</li>
                <li>✅ AWS WAF Protection</li>
                <li>✅ HTTPS Redirect</li>
                <li>✅ HTTP/2 and HTTP/3 Support</li>
                <li>✅ Gzip Compression</li>
                <li>✅ Security Headers</li>
            </ul>
        </div>
        <img src="/images/test-image.jpg" alt="Test Image" class="test-image">
    </div>
    <script src="/js/main.js"></script>
</body>
</html>
EOT

  tags = local.common_tags
}

# Upload sample CSS content
resource "aws_s3_object" "styles_css" {
  bucket       = aws_s3_bucket.content.id
  key          = "css/styles.css"
  content_type = "text/css"

  content = <<-EOT
/* CloudFront CDN Test Styles */
body {
    font-family: 'Arial', sans-serif;
    line-height: 1.6;
    margin: 0;
    padding: 20px;
    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
    color: #333;
    min-height: 100vh;
}

.container {
    max-width: 800px;
    margin: 0 auto;
    background: white;
    padding: 40px;
    border-radius: 10px;
    box-shadow: 0 10px 30px rgba(0,0,0,0.2);
}

h1 {
    color: #232F3E;
    text-align: center;
    margin-bottom: 30px;
    font-size: 2.5em;
}

h2 {
    color: #146EB4;
    border-bottom: 2px solid #FF9900;
    padding-bottom: 10px;
}

.features {
    margin: 30px 0;
    padding: 20px;
    background: #f8f9fa;
    border-radius: 5px;
    border-left: 4px solid #232F3E;
}

.features ul {
    list-style: none;
    padding: 0;
}

.features li {
    padding: 8px 0;
    font-weight: bold;
}

.test-image {
    max-width: 100%;
    height: auto;
    display: block;
    margin: 30px auto;
    border-radius: 8px;
    box-shadow: 0 4px 8px rgba(0,0,0,0.1);
}

p {
    font-size: 1.1em;
    text-align: center;
    margin-bottom: 30px;
    color: #666;
}
EOT

  tags = local.common_tags
}

# Upload sample JavaScript content
resource "aws_s3_object" "main_js" {
  bucket       = aws_s3_bucket.content.id
  key          = "js/main.js"
  content_type = "application/javascript"

  content = <<-EOT
// CloudFront CDN Test JavaScript
console.log('CloudFront CDN assets loaded successfully!');

// Display load time information
document.addEventListener('DOMContentLoaded', function() {
    const loadTime = (performance.timing.loadEventEnd - performance.timing.navigationStart) / 1000;
    console.log(`Page load time: ${loadTime.toFixed(2)} seconds`);
    
    // Add dynamic content to show the CDN is working
    const container = document.querySelector('.container');
    if (container) {
        const infoDiv = document.createElement('div');
        infoDiv.style.cssText = `
            margin-top: 30px;
            padding: 15px;
            background: #e8f5e8;
            border-radius: 5px;
            border-left: 4px solid #28a745;
            text-align: center;
        `;
        infoDiv.innerHTML = `
            <strong>CDN Performance:</strong><br>
            Page loaded in ${loadTime.toFixed(2)} seconds<br>
            <small>Served via CloudFront Edge Location</small>
        `;
        container.appendChild(infoDiv);
    }
    
    // Check if we're being served through CloudFront
    fetch(window.location.origin + '/css/styles.css')
        .then(response => {
            const cacheStatus = response.headers.get('x-cache');
            const cloudFrontId = response.headers.get('x-amz-cf-id');
            
            if (cacheStatus || cloudFrontId) {
                console.log('✅ Content is being served through CloudFront');
                if (cacheStatus) {
                    console.log(`Cache Status: ${cacheStatus}`);
                }
            }
        })
        .catch(error => {
            console.log('Could not verify CloudFront headers:', error);
        });
});
EOT

  tags = local.common_tags
}

# Upload sample image placeholder
resource "aws_s3_object" "test_image" {
  bucket       = aws_s3_bucket.content.id
  key          = "images/test-image.jpg"
  content_type = "image/jpeg"

  # Create a simple SVG that will be served as a JPEG for testing
  content = <<-EOT
<svg width="400" height="200" xmlns="http://www.w3.org/2000/svg">
  <rect width="100%" height="100%" fill="#232F3E"/>
  <text x="50%" y="50%" text-anchor="middle" dy=".3em" fill="#FF9900" font-size="24" font-family="Arial">
    CloudFront CDN Test Image
  </text>
  <text x="50%" y="70%" text-anchor="middle" dy=".3em" fill="#white" font-size="14" font-family="Arial">
    Delivered via Global Edge Network
  </text>
</svg>
EOT

  tags = local.common_tags
}

# ============================================================================
# CLOUDWATCH MONITORING AND ALARMS
# ============================================================================

# CloudWatch alarm for high 4xx error rate
resource "aws_cloudwatch_metric_alarm" "high_4xx_error_rate" {
  count = var.enable_monitoring ? 1 : 0

  alarm_name          = "CloudFront-4xx-Errors-${aws_cloudfront_distribution.main.id}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "4xxErrorRate"
  namespace           = "AWS/CloudFront"
  period              = "300"
  statistic           = "Average"
  threshold           = var.error_threshold
  alarm_description   = "This metric monitors CloudFront 4xx error rate"
  alarm_actions       = []

  dimensions = {
    DistributionId = aws_cloudfront_distribution.main.id
  }

  tags = merge(local.common_tags, {
    Name        = "${local.name_suffix}-4xx-errors-alarm"
    Description = "CloudWatch alarm for high 4xx error rate"
  })
}

# CloudWatch alarm for low cache hit rate
resource "aws_cloudwatch_metric_alarm" "low_cache_hit_rate" {
  count = var.enable_monitoring ? 1 : 0

  alarm_name          = "CloudFront-Low-Cache-Hit-Rate-${aws_cloudfront_distribution.main.id}"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "3"
  metric_name         = "CacheHitRate"
  namespace           = "AWS/CloudFront"
  period              = "300"
  statistic           = "Average"
  threshold           = var.cache_hit_threshold
  alarm_description   = "This metric monitors CloudFront cache hit rate"
  alarm_actions       = []

  dimensions = {
    DistributionId = aws_cloudfront_distribution.main.id
  }

  tags = merge(local.common_tags, {
    Name        = "${local.name_suffix}-cache-hit-rate-alarm"
    Description = "CloudWatch alarm for low cache hit rate"
  })
}

# CloudWatch alarm for high 5xx error rate
resource "aws_cloudwatch_metric_alarm" "high_5xx_error_rate" {
  count = var.enable_monitoring ? 1 : 0

  alarm_name          = "CloudFront-5xx-Errors-${aws_cloudfront_distribution.main.id}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "5xxErrorRate"
  namespace           = "AWS/CloudFront"
  period              = "300"
  statistic           = "Average"
  threshold           = "1.0"
  alarm_description   = "This metric monitors CloudFront 5xx error rate"
  alarm_actions       = []

  dimensions = {
    DistributionId = aws_cloudfront_distribution.main.id
  }

  tags = merge(local.common_tags, {
    Name        = "${local.name_suffix}-5xx-errors-alarm"
    Description = "CloudWatch alarm for high 5xx error rate"
  })
}