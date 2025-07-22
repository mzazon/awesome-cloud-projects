# Multi-tier Content Caching Strategy with CloudFront and ElastiCache
# This Terraform configuration deploys a comprehensive caching architecture
# combining CloudFront for global edge caching with ElastiCache for application-level caching

# Random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Data sources for existing AWS resources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

data "aws_security_group" "default" {
  name   = "default"
  vpc_id = data.aws_vpc.default.id
}

# ============================================================================
# S3 BUCKET FOR STATIC CONTENT
# ============================================================================

# S3 bucket for hosting static content
resource "aws_s3_bucket" "static_content" {
  bucket = "${var.project_name}-${random_id.suffix.hex}"
}

# S3 bucket versioning configuration
resource "aws_s3_bucket_versioning" "static_content" {
  bucket = aws_s3_bucket.static_content.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "static_content" {
  bucket = aws_s3_bucket.static_content.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 bucket public access block (prevent public access)
resource "aws_s3_bucket_public_access_block" "static_content" {
  bucket = aws_s3_bucket.static_content.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Sample static content file
resource "aws_s3_object" "index_html" {
  bucket       = aws_s3_bucket.static_content.id
  key          = "index.html"
  content_type = "text/html"
  content = templatefile("${path.module}/templates/index.html", {
    api_endpoint = aws_apigatewayv2_api.cache_demo.api_endpoint
  })

  etag = md5(templatefile("${path.module}/templates/index.html", {
    api_endpoint = aws_apigatewayv2_api.cache_demo.api_endpoint
  }))
}

# ============================================================================
# ELASTICACHE SUBNET GROUP AND CLUSTER
# ============================================================================

# ElastiCache subnet group for VPC deployment
resource "aws_elasticache_subnet_group" "cache_subnet_group" {
  name       = "${var.project_name}-${random_id.suffix.hex}-subnet-group"
  subnet_ids = data.aws_subnets.default.ids

  tags = {
    Name = "${var.project_name}-cache-subnet-group"
  }
}

# ElastiCache Redis cluster for application-level caching
resource "aws_elasticache_cluster" "redis" {
  cluster_id           = "${var.project_name}-${random_id.suffix.hex}"
  engine               = "redis"
  node_type            = var.elasticache_node_type
  num_cache_nodes      = 1
  parameter_group_name = "default.redis7"
  port                 = var.elasticache_port
  subnet_group_name    = aws_elasticache_subnet_group.cache_subnet_group.name
  security_group_ids   = [data.aws_security_group.default.id]

  # Enable automatic minor version upgrades
  auto_minor_version_upgrade = true

  # Configure maintenance window (UTC)
  maintenance_window = "sun:05:00-sun:06:00"

  tags = {
    Name = "${var.project_name}-redis-cluster"
  }
}

# ============================================================================
# LAMBDA FUNCTION AND IAM ROLE
# ============================================================================

# IAM role for Lambda function
resource "aws_iam_role" "lambda_role" {
  name = "${var.project_name}-lambda-role-${random_id.suffix.hex}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-lambda-role"
  }
}

# Attach AWS managed policies to Lambda role
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.lambda_role.name
}

resource "aws_iam_role_policy_attachment" "lambda_vpc_access" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
  role       = aws_iam_role.lambda_role.name
}

# Lambda function source code
locals {
  lambda_source = templatefile("${path.module}/templates/lambda_function.py", {
    elasticache_ttl = var.elasticache_ttl
  })
}

# Archive Lambda function code
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda_function.zip"
  
  source {
    content  = local.lambda_source
    filename = "lambda_function.py"
  }
}

# Note: Redis library is included directly in the Lambda package
# In production, consider using Lambda layers for dependencies

# Lambda function for cache demo
resource "aws_lambda_function" "cache_demo" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "${var.project_name}-${random_id.suffix.hex}"
  role            = aws_iam_role.lambda_role.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = "python3.9"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  # Note: Using inline deployment for simplicity
  # In production, use Lambda layers for shared dependencies

  # VPC configuration for ElastiCache access
  vpc_config {
    subnet_ids         = data.aws_subnets.default.ids
    security_group_ids = [data.aws_security_group.default.id]
  }

  # Environment variables
  environment {
    variables = {
      REDIS_ENDPOINT = aws_elasticache_cluster.redis.cache_nodes[0].address
      REDIS_PORT     = var.elasticache_port
      TTL_SECONDS    = var.elasticache_ttl
    }
  }

  tags = {
    Name = "${var.project_name}-lambda-function"
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy_attachment.lambda_vpc_access,
    aws_elasticache_cluster.redis,
  ]
}

# ============================================================================
# API GATEWAY V2 (HTTP API)
# ============================================================================

# API Gateway HTTP API
resource "aws_apigatewayv2_api" "cache_demo" {
  name          = "${var.project_name}-api-${random_id.suffix.hex}"
  protocol_type = "HTTP"
  description   = "API for content caching demonstration"

  cors_configuration {
    allow_credentials = false
    allow_headers     = ["content-type", "x-amz-date", "authorization", "x-api-key"]
    allow_methods     = ["GET", "POST", "OPTIONS"]
    allow_origins     = ["*"]
    expose_headers    = ["date", "keep-alive"]
    max_age          = 86400
  }

  tags = {
    Name = "${var.project_name}-api-gateway"
  }
}

# API Gateway integration with Lambda
resource "aws_apigatewayv2_integration" "lambda_integration" {
  api_id           = aws_apigatewayv2_api.cache_demo.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.cache_demo.invoke_arn
  
  integration_method      = "POST"
  payload_format_version  = "2.0"
  timeout_milliseconds    = 30000
}

# API Gateway route
resource "aws_apigatewayv2_route" "api_data" {
  api_id    = aws_apigatewayv2_api.cache_demo.id
  route_key = "GET /api/data"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

# API Gateway stage
resource "aws_apigatewayv2_stage" "prod" {
  api_id      = aws_apigatewayv2_api.cache_demo.id
  name        = "prod"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      ip            = "$context.identity.sourceIp"
      requestTime   = "$context.requestTime"
      httpMethod    = "$context.httpMethod"
      routeKey      = "$context.routeKey"
      status        = "$context.status"
      protocol      = "$context.protocol"
      responseLength = "$context.responseLength"
      error         = "$context.error.message"
      integrationError = "$context.integrationErrorMessage"
    })
  }

  tags = {
    Name = "${var.project_name}-api-stage"
  }

  depends_on = [aws_cloudwatch_log_group.api_gateway]
}

# Lambda permission for API Gateway
resource "aws_lambda_permission" "api_gateway_invoke" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.cache_demo.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.cache_demo.execution_arn}/*/*"
}

# ============================================================================
# CLOUDFRONT DISTRIBUTION
# ============================================================================

# CloudFront Origin Access Control for S3
resource "aws_cloudfront_origin_access_control" "s3_oac" {
  name                              = "${var.project_name}-s3-oac-${random_id.suffix.hex}"
  description                       = "Origin Access Control for S3 bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# CloudFront cache policy for API responses
resource "aws_cloudfront_cache_policy" "api_cache_policy" {
  name        = "${var.project_name}-api-cache-policy-${random_id.suffix.hex}"
  comment     = "Cache policy for API responses"
  default_ttl = var.api_cache_ttl_default
  max_ttl     = var.api_cache_ttl_max
  min_ttl     = 0

  parameters_in_cache_key_and_forwarded_to_origin {
    enable_accept_encoding_gzip   = true
    enable_accept_encoding_brotli = true

    query_strings_config {
      query_string_behavior = "all"
    }

    headers_config {
      header_behavior = "none"
    }

    cookies_config {
      cookie_behavior = "none"
    }
  }
}

# CloudFront distribution with multiple origins
resource "aws_cloudfront_distribution" "cache_demo" {
  comment             = "Multi-tier caching demo distribution"
  default_root_object = "index.html"
  enabled             = true
  is_ipv6_enabled     = true
  price_class         = var.cloudfront_price_class
  retain_on_delete    = !var.enable_deletion_protection

  # S3 origin for static content
  origin {
    domain_name              = aws_s3_bucket.static_content.bucket_regional_domain_name
    origin_id                = "S3-${aws_s3_bucket.static_content.id}"
    origin_access_control_id = aws_cloudfront_origin_access_control.s3_oac.id
  }

  # API Gateway origin for dynamic content
  origin {
    domain_name = replace(aws_apigatewayv2_api.cache_demo.api_endpoint, "https://", "")
    origin_id   = "API-${aws_apigatewayv2_api.cache_demo.id}"
    origin_path = "/prod"

    custom_origin_config {
      http_port              = 443
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  # Default cache behavior for static content
  default_cache_behavior {
    target_origin_id       = "S3-${aws_s3_bucket.static_content.id}"
    viewer_protocol_policy = "redirect-to-https"
    compress               = true

    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods         = ["GET", "HEAD"]
    cache_policy_id        = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad" # Managed-CachingOptimized

    response_headers_policy_id = "67f7725c-6f97-4210-82d7-5512b31e9d03" # Managed-SecurityHeadersPolicy
  }

  # Cache behavior for API endpoints
  ordered_cache_behavior {
    path_pattern           = "/api/*"
    target_origin_id       = "API-${aws_apigatewayv2_api.cache_demo.id}"
    viewer_protocol_policy = "redirect-to-https"
    compress               = true

    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods         = ["GET", "HEAD", "OPTIONS"]
    cache_policy_id        = aws_cloudfront_cache_policy.api_cache_policy.id

    response_headers_policy_id = "67f7725c-6f97-4210-82d7-5512b31e9d03" # Managed-SecurityHeadersPolicy
  }

  # Geographic restrictions (none for demo)
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  # SSL/TLS certificate configuration
  viewer_certificate {
    cloudfront_default_certificate = true
  }

  # Logging configuration
  logging_config {
    bucket          = aws_s3_bucket.cloudfront_logs.bucket_domain_name
    include_cookies = false
    prefix          = "cloudfront-logs/"
  }

  tags = {
    Name = "${var.project_name}-cloudfront-distribution"
  }

  depends_on = [
    aws_s3_bucket_policy.cloudfront_oac,
    aws_apigatewayv2_stage.prod
  ]
}

# S3 bucket for CloudFront logs
resource "aws_s3_bucket" "cloudfront_logs" {
  bucket = "${var.project_name}-cf-logs-${random_id.suffix.hex}"
}

resource "aws_s3_bucket_ownership_controls" "cloudfront_logs" {
  bucket = aws_s3_bucket.cloudfront_logs.id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_acl" "cloudfront_logs" {
  depends_on = [aws_s3_bucket_ownership_controls.cloudfront_logs]

  bucket = aws_s3_bucket.cloudfront_logs.id
  acl    = "private"
}

# S3 bucket policy for CloudFront OAC
resource "aws_s3_bucket_policy" "cloudfront_oac" {
  bucket = aws_s3_bucket.static_content.id

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
        Resource = "${aws_s3_bucket.static_content.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.cache_demo.arn
          }
        }
      }
    ]
  })

  depends_on = [aws_cloudfront_distribution.cache_demo]
}

# ============================================================================
# CLOUDWATCH MONITORING AND ALARMS
# ============================================================================

# CloudWatch log group for API Gateway
resource "aws_cloudwatch_log_group" "api_gateway" {
  name              = "/aws/apigateway/${var.project_name}-${random_id.suffix.hex}"
  retention_in_days = 7

  tags = {
    Name = "${var.project_name}-api-gateway-logs"
  }
}

# CloudWatch log group for Lambda
resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${aws_lambda_function.cache_demo.function_name}"
  retention_in_days = 7

  tags = {
    Name = "${var.project_name}-lambda-logs"
  }
}

# CloudWatch log group for general monitoring
resource "aws_cloudwatch_log_group" "cache_monitoring" {
  name              = "/aws/cloudfront/${var.project_name}"
  retention_in_days = 7

  tags = {
    Name = "${var.project_name}-cache-monitoring"
  }
}

# CloudWatch alarm for CloudFront cache hit ratio
resource "aws_cloudwatch_metric_alarm" "cache_hit_ratio" {
  count = var.enable_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${var.project_name}-cache-hit-ratio-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CacheHitRate"
  namespace           = "AWS/CloudFront"
  period              = "300"
  statistic           = "Average"
  threshold           = var.cache_hit_ratio_threshold
  alarm_description   = "This metric monitors CloudFront cache hit ratio"
  alarm_actions       = []

  dimensions = {
    DistributionId = aws_cloudfront_distribution.cache_demo.id
  }

  tags = {
    Name = "${var.project_name}-cache-hit-ratio-alarm"
  }
}

# CloudWatch alarm for ElastiCache CPU utilization
resource "aws_cloudwatch_metric_alarm" "elasticache_cpu" {
  count = var.enable_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${var.project_name}-elasticache-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ElastiCache"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors ElastiCache CPU utilization"
  alarm_actions       = []

  dimensions = {
    CacheClusterId = aws_elasticache_cluster.redis.cluster_id
  }

  tags = {
    Name = "${var.project_name}-elasticache-cpu-alarm"
  }
}

# CloudWatch alarm for Lambda errors
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  count = var.enable_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${var.project_name}-lambda-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "This metric monitors Lambda function errors"
  alarm_actions       = []

  dimensions = {
    FunctionName = aws_lambda_function.cache_demo.function_name
  }

  tags = {
    Name = "${var.project_name}-lambda-errors-alarm"
  }
}