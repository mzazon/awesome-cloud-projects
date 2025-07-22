# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 4
}

# Data sources for current AWS account and caller identity
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Data sources for cache and origin request policies
data "aws_cloudfront_cache_policy" "caching_optimized" {
  name = "Managed-CachingOptimized"
}

data "aws_cloudfront_cache_policy" "caching_disabled" {
  name = "Managed-CachingDisabled"
}

data "aws_cloudfront_origin_request_policy" "cors_s3_origin" {
  name = "Managed-CORS-S3Origin"
}

data "aws_cloudfront_origin_request_policy" "all_viewer" {
  name = "Managed-AllViewer"
}

# Local values for resource naming and configuration
locals {
  suffix                = random_id.suffix.hex
  s3_bucket_name       = var.s3_bucket_name != "" ? var.s3_bucket_name : "${var.project_name}-content-${local.suffix}"
  lambda_function_name = "${var.project_name}-edge-processor-${local.suffix}"
  waf_webacl_name     = "${var.project_name}-security-${local.suffix}"
  cf_function_name    = "${var.project_name}-request-processor-${local.suffix}"
  kvs_name            = "${var.project_name}-config-${local.suffix}"
  
  # Common tags
  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
    },
    var.additional_tags
  )
}

# S3 Bucket for static content
resource "aws_s3_bucket" "content" {
  bucket        = local.s3_bucket_name
  force_destroy = var.s3_force_destroy
  
  tags = merge(local.common_tags, {
    Name = local.s3_bucket_name
    Type = "content-bucket"
  })
}

# S3 Bucket versioning
resource "aws_s3_bucket_versioning" "content" {
  bucket = aws_s3_bucket.content.id
  
  versioning_configuration {
    status = var.enable_s3_versioning ? "Enabled" : "Disabled"
  }
}

# S3 Bucket server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "content" {
  bucket = aws_s3_bucket.content.id
  
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# S3 Bucket public access block
resource "aws_s3_bucket_public_access_block" "content" {
  bucket = aws_s3_bucket.content.id
  
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Sample content for S3 bucket
resource "aws_s3_object" "index" {
  bucket       = aws_s3_bucket.content.id
  key          = "index.html"
  content      = "<html><body><h1>Advanced CDN</h1><p>Version: 1.0</p><p>Served from CloudFront</p></body></html>"
  content_type = "text/html"
  etag         = md5("<html><body><h1>Advanced CDN</h1><p>Version: 1.0</p><p>Served from CloudFront</p></body></html>")
  
  tags = local.common_tags
}

resource "aws_s3_object" "api_index" {
  bucket       = aws_s3_bucket.content.id
  key          = "api/index.html"
  content      = "<html><body><h1>API Documentation</h1><p>Version: 2.0</p></body></html>"
  content_type = "text/html"
  etag         = md5("<html><body><h1>API Documentation</h1><p>Version: 2.0</p></body></html>")
  
  tags = local.common_tags
}

resource "aws_s3_object" "api_status" {
  bucket       = aws_s3_bucket.content.id
  key          = "api/status.json"
  content      = jsonencode({
    message   = "Hello from API"
    timestamp = timestamp()
    version   = "1.0"
  })
  content_type = "application/json"
  
  tags = local.common_tags
}

# CloudFront Origin Access Control
resource "aws_cloudfront_origin_access_control" "s3_oac" {
  name                              = "${var.project_name}-oac-${local.suffix}"
  description                       = "Origin Access Control for S3 bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# S3 Bucket Policy for CloudFront OAC
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
  
  depends_on = [aws_cloudfront_distribution.main]
}

# WAF Web ACL for CloudFront
resource "aws_wafv2_web_acl" "cloudfront" {
  count = var.enable_waf ? 1 : 0
  
  name  = local.waf_webacl_name
  scope = "CLOUDFRONT"
  
  default_action {
    allow {}
  }
  
  # AWS Managed Rules - Common Rule Set
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
      metric_name                 = "CommonRuleSetMetric"
      sampled_requests_enabled    = true
    }
  }
  
  # AWS Managed Rules - Known Bad Inputs
  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 2
    
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
      metric_name                 = "KnownBadInputsRuleSetMetric"
      sampled_requests_enabled    = true
    }
  }
  
  # Rate Limiting Rule
  rule {
    name     = "RateLimitRule"
    priority = 3
    
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
      metric_name                 = "RateLimitRuleMetric"
      sampled_requests_enabled    = true
    }
  }
  
  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                 = local.waf_webacl_name
    sampled_requests_enabled    = true
  }
  
  tags = merge(local.common_tags, {
    Name = local.waf_webacl_name
    Type = "waf-webacl"
  })
}

# CloudFront Function for request processing
resource "aws_cloudfront_function" "request_processor" {
  count = var.enable_cloudfront_functions ? 1 : 0
  
  name    = local.cf_function_name
  runtime = "cloudfront-js-2.0"
  comment = "Request processing function for header manipulation and URL rewriting"
  publish = true
  code    = file("${path.module}/functions/cloudfront-function.js")
}

# IAM Role for Lambda@Edge
resource "aws_iam_role" "lambda_edge" {
  count = var.enable_lambda_edge ? 1 : 0
  
  name = "${local.lambda_function_name}-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = [
            "lambda.amazonaws.com",
            "edgelambda.amazonaws.com"
          ]
        }
      }
    ]
  })
  
  tags = local.common_tags
}

# IAM Role Policy Attachment for Lambda@Edge
resource "aws_iam_role_policy_attachment" "lambda_edge_basic" {
  count = var.enable_lambda_edge ? 1 : 0
  
  role       = aws_iam_role.lambda_edge[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Lambda@Edge Function
resource "aws_lambda_function" "edge_processor" {
  count = var.enable_lambda_edge ? 1 : 0
  
  provider = aws.us_east_1
  
  filename      = data.archive_file.lambda_edge[0].output_path
  function_name = local.lambda_function_name
  role          = aws_iam_role.lambda_edge[0].arn
  handler       = "index.handler"
  runtime       = "nodejs18.x"
  timeout       = var.lambda_edge_timeout
  memory_size   = var.lambda_edge_memory_size
  publish       = true
  
  source_code_hash = data.archive_file.lambda_edge[0].output_base64sha256
  
  tags = merge(local.common_tags, {
    Name = local.lambda_function_name
    Type = "lambda-edge"
  })
}

# Archive file for Lambda@Edge function
data "archive_file" "lambda_edge" {
  count = var.enable_lambda_edge ? 1 : 0
  
  type        = "zip"
  output_path = "${path.module}/lambda-edge.zip"
  
  source {
    content = templatefile("${path.module}/functions/lambda-edge.js", {
      environment = var.environment
    })
    filename = "index.js"
  }
}

# CloudFront KeyValueStore
resource "aws_cloudfront_key_value_store" "config" {
  count = var.enable_key_value_store ? 1 : 0
  
  name    = local.kvs_name
  comment = "Dynamic configuration store for CDN"
  
  tags = merge(local.common_tags, {
    Name = local.kvs_name
    Type = "key-value-store"
  })
}

# Kinesis Data Stream for real-time logs
resource "aws_kinesis_stream" "realtime_logs" {
  count = var.enable_real_time_logs ? 1 : 0
  
  name             = "cloudfront-realtime-logs-${local.suffix}"
  shard_count      = var.real_time_logs_kinesis_shard_count
  retention_period = 24
  
  shard_level_metrics = [
    "IncomingRecords",
    "OutgoingRecords",
  ]
  
  stream_mode_details {
    stream_mode = "PROVISIONED"
  }
  
  tags = merge(local.common_tags, {
    Name = "cloudfront-realtime-logs-${local.suffix}"
    Type = "kinesis-stream"
  })
}

# IAM Role for CloudFront real-time logs
resource "aws_iam_role" "realtime_logs" {
  count = var.enable_real_time_logs ? 1 : 0
  
  name = "CloudFront-RealTimeLogs-${local.suffix}"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
      }
    ]
  })
  
  inline_policy {
    name = "KinesisAccess"
    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect = "Allow"
          Action = [
            "kinesis:PutRecords",
            "kinesis:PutRecord"
          ]
          Resource = var.enable_real_time_logs ? aws_kinesis_stream.realtime_logs[0].arn : "*"
        }
      ]
    })
  }
  
  tags = local.common_tags
}

# CloudFront Real-time Log Configuration
resource "aws_cloudfront_realtime_log_config" "main" {
  count = var.enable_real_time_logs ? 1 : 0
  
  name = "realtime-logs-${local.suffix}"
  
  endpoint {
    stream_type = "Kinesis"
    
    kinesis_stream_config {
      role_arn   = aws_iam_role.realtime_logs[0].arn
      stream_arn = aws_kinesis_stream.realtime_logs[0].arn
    }
  }
  
  fields = [
    "timestamp",
    "c-ip",
    "sc-status",
    "cs-method",
    "cs-uri-stem",
    "cs-uri-query",
    "cs-referer",
    "cs-user-agent"
  ]
}

# CloudFront Distribution
resource "aws_cloudfront_distribution" "main" {
  comment             = "Advanced CDN with multiple origins and edge functions"
  default_root_object = var.default_root_object
  enabled             = true
  is_ipv6_enabled     = var.enable_ipv6
  price_class         = var.price_class
  web_acl_id          = var.enable_waf ? aws_wafv2_web_acl.cloudfront[0].arn : null
  
  # S3 Origin
  origin {
    domain_name              = aws_s3_bucket.content.bucket_regional_domain_name
    origin_id                = "S3Origin"
    origin_access_control_id = aws_cloudfront_origin_access_control.s3_oac.id
    
    origin_shield {
      enabled = false
    }
  }
  
  # Custom Origin
  origin {
    domain_name = var.custom_origin_domain
    origin_id   = "CustomOrigin"
    
    custom_origin_config {
      http_port                = 80
      https_port               = 443
      origin_protocol_policy   = "https-only"
      origin_ssl_protocols     = ["TLSv1.2"]
      origin_read_timeout      = 30
      origin_keepalive_timeout = 5
    }
    
    origin_shield {
      enabled = false
    }
  }
  
  # Default Cache Behavior
  default_cache_behavior {
    target_origin_id         = "S3Origin"
    viewer_protocol_policy   = "redirect-to-https"
    cached_methods           = ["GET", "HEAD"]
    allowed_methods          = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    compress                 = var.enable_compression
    cache_policy_id          = data.aws_cloudfront_cache_policy.caching_optimized.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.cors_s3_origin.id
    
    # CloudFront Function Association
    dynamic "function_association" {
      for_each = var.enable_cloudfront_functions ? [1] : []
      content {
        event_type   = "viewer-request"
        function_arn = aws_cloudfront_function.request_processor[0].arn
      }
    }
    
    # Lambda@Edge Association
    dynamic "lambda_function_association" {
      for_each = var.enable_lambda_edge ? [1] : []
      content {
        event_type   = "origin-response"
        lambda_arn   = aws_lambda_function.edge_processor[0].qualified_arn
        include_body = false
      }
    }
  }
  
  # API Cache Behavior
  ordered_cache_behavior {
    path_pattern             = "/api/*"
    target_origin_id         = "CustomOrigin"
    viewer_protocol_policy   = "redirect-to-https"
    cached_methods           = ["GET", "HEAD"]
    allowed_methods          = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    compress                 = var.enable_compression
    cache_policy_id          = data.aws_cloudfront_cache_policy.caching_optimized.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer.id
    
    # Lambda@Edge Association for API paths
    dynamic "lambda_function_association" {
      for_each = var.enable_lambda_edge ? [1] : []
      content {
        event_type   = "origin-response"
        lambda_arn   = aws_lambda_function.edge_processor[0].qualified_arn
        include_body = false
      }
    }
  }
  
  # Static Content Cache Behavior
  ordered_cache_behavior {
    path_pattern             = "/static/*"
    target_origin_id         = "S3Origin"
    viewer_protocol_policy   = "redirect-to-https"
    cached_methods           = ["GET", "HEAD"]
    allowed_methods          = ["GET", "HEAD"]
    compress                 = var.enable_compression
    cache_policy_id          = data.aws_cloudfront_cache_policy.caching_optimized.id
  }
  
  # Custom Error Responses
  custom_error_response {
    error_code            = 404
    response_code         = 404
    response_page_path    = "/404.html"
    error_caching_min_ttl = 300
  }
  
  custom_error_response {
    error_code            = 500
    response_code         = 500
    response_page_path    = "/500.html"
    error_caching_min_ttl = 0
  }
  
  # Geographic Restrictions
  restrictions {
    geo_restriction {
      restriction_type = var.waf_geo_restriction_type
      locations        = var.waf_geo_restriction_locations
    }
  }
  
  # SSL Certificate
  viewer_certificate {
    cloudfront_default_certificate = true
    minimum_protocol_version       = var.minimum_protocol_version
  }
  
  # Logging Configuration
  logging_config {
    bucket          = aws_s3_bucket.content.bucket_domain_name
    prefix          = "cloudfront-logs/"
    include_cookies = false
  }
  
  tags = merge(local.common_tags, {
    Name = "${var.project_name}-distribution"
    Type = "cloudfront-distribution"
  })
}

# CloudWatch Log Group for real-time logs
resource "aws_cloudwatch_log_group" "realtime_logs" {
  count = var.enable_real_time_logs ? 1 : 0
  
  name              = "/aws/cloudfront/realtime-logs/${var.project_name}"
  retention_in_days = var.cloudwatch_log_retention_days
  
  tags = merge(local.common_tags, {
    Name = "cloudfront-realtime-logs"
    Type = "log-group"
  })
}

# CloudWatch Dashboard
resource "aws_cloudwatch_dashboard" "main" {
  count = var.enable_cloudwatch_dashboard ? 1 : 0
  
  dashboard_name = "CloudFront-Advanced-CDN-${local.suffix}"
  
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
            [".", "BytesUploaded", ".", "."]
          ]
          period = 300
          stat   = "Sum"
          region = "us-east-1"
          title  = "CloudFront Traffic"
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
            ["AWS/CloudFront", "4xxErrorRate", "DistributionId", aws_cloudfront_distribution.main.id],
            [".", "5xxErrorRate", ".", "."]
          ]
          period = 300
          stat   = "Average"
          region = "us-east-1"
          title  = "Error Rates"
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
            ["AWS/CloudFront", "CacheHitRate", "DistributionId", aws_cloudfront_distribution.main.id]
          ]
          period = 300
          stat   = "Average"
          region = "us-east-1"
          title  = "Cache Hit Rate"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = var.enable_waf ? {
          metrics = [
            ["AWS/WAFV2", "AllowedRequests", "WebACL", local.waf_webacl_name, "Rule", "ALL", "Region", "CloudFront"],
            [".", "BlockedRequests", ".", ".", ".", ".", ".", "."]
          ]
          period = 300
          stat   = "Sum"
          region = "us-east-1"
          title  = "WAF Activity"
        } : {
          annotations = {
            horizontal = []
          }
          view    = "timeSeries"
          stacked = false
          region  = "us-east-1"
          title   = "WAF Disabled"
        }
      }
    ]
  })
}

# Create function files if they don't exist
resource "local_file" "cloudfront_function" {
  count = var.enable_cloudfront_functions ? 1 : 0
  
  filename = "${path.module}/functions/cloudfront-function.js"
  content = templatefile("${path.module}/templates/cloudfront-function.js.tpl", {
    environment = var.environment
  })
  
  # Only create if file doesn't exist
  lifecycle {
    ignore_changes = [content]
  }
}

resource "local_file" "lambda_edge_function" {
  count = var.enable_lambda_edge ? 1 : 0
  
  filename = "${path.module}/functions/lambda-edge.js"
  content = templatefile("${path.module}/templates/lambda-edge.js.tpl", {
    environment = var.environment
  })
  
  # Only create if file doesn't exist
  lifecycle {
    ignore_changes = [content]
  }
}