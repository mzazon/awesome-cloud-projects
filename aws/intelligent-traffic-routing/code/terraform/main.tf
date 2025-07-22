# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 4
}

# Get current AWS account ID and caller identity
data "aws_caller_identity" "current" {}

# Data sources for availability zones in each region
data "aws_availability_zones" "primary" {
  provider = aws.primary
  state    = "available"
}

data "aws_availability_zones" "secondary" {
  provider = aws.secondary
  state    = "available"
}

data "aws_availability_zones" "tertiary" {
  provider = aws.tertiary
  state    = "available"
}

# Data source for latest Amazon Linux 2 AMI in each region
data "aws_ami" "amazon_linux_primary" {
  provider    = aws.primary
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

data "aws_ami" "amazon_linux_secondary" {
  provider    = aws.secondary
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

data "aws_ami" "amazon_linux_tertiary" {
  provider    = aws.tertiary
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

# Local values for resource naming and configuration
locals {
  project_suffix = "${var.project_name}-${random_id.suffix.hex}"
  domain_name    = var.domain_name != "" ? var.domain_name : "example-${random_id.suffix.hex}.com"
  
  # Regional CIDR blocks
  vpc_cidrs = {
    primary   = "10.10.0.0/16"
    secondary = "10.20.0.0/16"
    tertiary  = "10.30.0.0/16"
  }
  
  # Region mappings for geo-location
  geo_locations = {
    primary   = { continent_code = "NA" }  # North America
    secondary = { continent_code = "EU" }  # Europe  
    tertiary  = { continent_code = "AS" }  # Asia
  }
  
  # Common tags
  common_tags = merge({
    Project     = var.project_name
    Environment = var.environment
    Recipe      = "global-load-balancing-route53-cloudfront"
    ManagedBy   = "terraform"
  }, var.additional_tags)
}

# =====================================================
# S3 BUCKET FOR FALLBACK CONTENT
# =====================================================

# S3 bucket for fallback content
resource "aws_s3_bucket" "fallback" {
  count         = var.create_fallback_bucket ? 1 : 0
  provider      = aws.us_east_1
  bucket        = "global-lb-fallback-${random_id.suffix.hex}"
  force_destroy = var.fallback_bucket_force_destroy

  tags = merge(local.common_tags, {
    Name = "Global LB Fallback Bucket"
  })
}

# S3 bucket public access block
resource "aws_s3_bucket_public_access_block" "fallback" {
  count   = var.create_fallback_bucket ? 1 : 0
  provider = aws.us_east_1
  bucket  = aws_s3_bucket.fallback[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket versioning
resource "aws_s3_bucket_versioning" "fallback" {
  count    = var.create_fallback_bucket ? 1 : 0
  provider = aws.us_east_1
  bucket   = aws_s3_bucket.fallback[0].id
  
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "fallback" {
  count    = var.create_fallback_bucket ? 1 : 0
  provider = aws.us_east_1
  bucket   = aws_s3_bucket.fallback[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# Fallback HTML content
resource "aws_s3_object" "fallback_index" {
  count        = var.create_fallback_bucket ? 1 : 0
  provider     = aws.us_east_1
  bucket       = aws_s3_bucket.fallback[0].id
  key          = "index.html"
  content_type = "text/html"
  
  content = <<-HTML
<!DOCTYPE html>
<html>
<head>
    <title>Service Temporarily Unavailable</title>
    <style>
        body { font-family: Arial, sans-serif; text-align: center; padding: 50px; }
        .message { background: #f8f9fa; padding: 20px; border-radius: 5px; margin: 20px auto; max-width: 600px; }
        .status { color: #dc3545; font-size: 18px; font-weight: bold; }
    </style>
</head>
<body>
    <div class="message">
        <h1>Service Temporarily Unavailable</h1>
        <p class="status">We're working to restore service as quickly as possible.</p>
        <p>Please try again in a few minutes. If the problem persists, contact support.</p>
        <p><small>Error Code: GLB-FALLBACK</small></p>
    </div>
</body>
</html>
HTML
  
  tags = local.common_tags
}

# Fallback health check JSON
resource "aws_s3_object" "fallback_health" {
  count        = var.create_fallback_bucket ? 1 : 0
  provider     = aws.us_east_1
  bucket       = aws_s3_bucket.fallback[0].id
  key          = "health"
  content_type = "application/json"
  
  content = jsonencode({
    status    = "maintenance"
    message   = "Service temporarily unavailable"
    timestamp = timestamp()
  })
  
  tags = local.common_tags
}

# =====================================================
# VPC AND NETWORKING INFRASTRUCTURE
# =====================================================

# Module for primary region infrastructure
module "vpc_primary" {
  source = "./modules/regional-infrastructure"
  
  providers = {
    aws = aws.primary
  }
  
  project_name             = local.project_suffix
  region                  = var.primary_region
  vpc_cidr               = local.vpc_cidrs.primary
  availability_zones     = slice(data.aws_availability_zones.primary.names, 0, var.availability_zones_count)
  instance_type          = var.instance_type
  ami_id                 = data.aws_ami.amazon_linux_primary.id
  min_capacity          = var.min_capacity
  max_capacity          = var.max_capacity
  desired_capacity      = var.desired_capacity
  health_check_path     = var.health_check_path
  alb_idle_timeout      = var.alb_idle_timeout
  
  # Target group health check configuration
  target_group_health_check_interval    = var.target_group_health_check_interval
  target_group_health_check_timeout     = var.target_group_health_check_timeout
  target_group_healthy_threshold        = var.target_group_healthy_threshold
  target_group_unhealthy_threshold      = var.target_group_unhealthy_threshold
  
  tags = local.common_tags
}

# Module for secondary region infrastructure
module "vpc_secondary" {
  source = "./modules/regional-infrastructure"
  
  providers = {
    aws = aws.secondary
  }
  
  project_name             = local.project_suffix
  region                  = var.secondary_region
  vpc_cidr               = local.vpc_cidrs.secondary
  availability_zones     = slice(data.aws_availability_zones.secondary.names, 0, var.availability_zones_count)
  instance_type          = var.instance_type
  ami_id                 = data.aws_ami.amazon_linux_secondary.id
  min_capacity          = var.min_capacity
  max_capacity          = var.max_capacity
  desired_capacity      = var.desired_capacity
  health_check_path     = var.health_check_path
  alb_idle_timeout      = var.alb_idle_timeout
  
  # Target group health check configuration
  target_group_health_check_interval    = var.target_group_health_check_interval
  target_group_health_check_timeout     = var.target_group_health_check_timeout
  target_group_healthy_threshold        = var.target_group_healthy_threshold
  target_group_unhealthy_threshold      = var.target_group_unhealthy_threshold
  
  tags = local.common_tags
}

# Module for tertiary region infrastructure
module "vpc_tertiary" {
  source = "./modules/regional-infrastructure"
  
  providers = {
    aws = aws.tertiary
  }
  
  project_name             = local.project_suffix
  region                  = var.tertiary_region
  vpc_cidr               = local.vpc_cidrs.tertiary
  availability_zones     = slice(data.aws_availability_zones.tertiary.names, 0, var.availability_zones_count)
  instance_type          = var.instance_type
  ami_id                 = data.aws_ami.amazon_linux_tertiary.id
  min_capacity          = var.min_capacity
  max_capacity          = var.max_capacity
  desired_capacity      = var.desired_capacity
  health_check_path     = var.health_check_path
  alb_idle_timeout      = var.alb_idle_timeout
  
  # Target group health check configuration
  target_group_health_check_interval    = var.target_group_health_check_interval
  target_group_health_check_timeout     = var.target_group_health_check_timeout
  target_group_healthy_threshold        = var.target_group_healthy_threshold
  target_group_unhealthy_threshold      = var.target_group_unhealthy_threshold
  
  tags = local.common_tags
}

# =====================================================
# ROUTE53 HEALTH CHECKS
# =====================================================

# Health check for primary region
resource "aws_route53_health_check" "primary" {
  provider                        = aws.us_east_1
  fqdn                           = module.vpc_primary.alb_dns_name
  port                           = 80
  type                           = "HTTP"
  resource_path                  = var.health_check_path
  failure_threshold              = var.health_check_failure_threshold
  request_interval               = var.health_check_interval
  cloudwatch_alarm_region        = var.primary_region
  cloudwatch_alarm_name          = "${local.project_suffix}-alb-health-primary"
  insufficient_data_health_status = "Failure"

  tags = merge(local.common_tags, {
    Name   = "${local.project_suffix}-health-check-primary"
    Region = var.primary_region
  })
}

# Health check for secondary region
resource "aws_route53_health_check" "secondary" {
  provider                        = aws.us_east_1
  fqdn                           = module.vpc_secondary.alb_dns_name
  port                           = 80
  type                           = "HTTP"
  resource_path                  = var.health_check_path
  failure_threshold              = var.health_check_failure_threshold
  request_interval               = var.health_check_interval
  cloudwatch_alarm_region        = var.secondary_region
  cloudwatch_alarm_name          = "${local.project_suffix}-alb-health-secondary"
  insufficient_data_health_status = "Failure"

  tags = merge(local.common_tags, {
    Name   = "${local.project_suffix}-health-check-secondary"
    Region = var.secondary_region
  })
}

# Health check for tertiary region
resource "aws_route53_health_check" "tertiary" {
  provider                        = aws.us_east_1
  fqdn                           = module.vpc_tertiary.alb_dns_name
  port                           = 80
  type                           = "HTTP"
  resource_path                  = var.health_check_path
  failure_threshold              = var.health_check_failure_threshold
  request_interval               = var.health_check_interval
  cloudwatch_alarm_region        = var.tertiary_region
  cloudwatch_alarm_name          = "${local.project_suffix}-alb-health-tertiary"
  insufficient_data_health_status = "Failure"

  tags = merge(local.common_tags, {
    Name   = "${local.project_suffix}-health-check-tertiary"
    Region = var.tertiary_region
  })
}

# =====================================================
# ROUTE53 HOSTED ZONE AND DNS RECORDS
# =====================================================

# Route53 hosted zone (create new or use existing)
resource "aws_route53_zone" "main" {
  count    = var.create_hosted_zone ? 1 : 0
  provider = aws.us_east_1
  name     = local.domain_name
  comment  = "Global load balancer demo zone for ${var.project_name}"

  tags = merge(local.common_tags, {
    Name = "${local.project_suffix}-hosted-zone"
  })
}

# Data source for existing hosted zone (if not creating new one)
data "aws_route53_zone" "existing" {
  count    = var.create_hosted_zone ? 0 : 1
  provider = aws.us_east_1
  zone_id  = var.hosted_zone_id
}

locals {
  hosted_zone_id = var.create_hosted_zone ? aws_route53_zone.main[0].zone_id : data.aws_route53_zone.existing[0].zone_id
}

# Weighted routing policy records for failover testing
resource "aws_route53_record" "app_weighted_primary" {
  provider = aws.us_east_1
  zone_id  = local.hosted_zone_id
  name     = "app.${local.domain_name}"
  type     = "CNAME"
  ttl      = 60

  weighted_routing_policy {
    weight = var.primary_weight
  }

  set_identifier  = "primary"
  health_check_id = aws_route53_health_check.primary.id
  records         = [module.vpc_primary.alb_dns_name]
}

resource "aws_route53_record" "app_weighted_secondary" {
  provider = aws.us_east_1
  zone_id  = local.hosted_zone_id
  name     = "app.${local.domain_name}"
  type     = "CNAME"
  ttl      = 60

  weighted_routing_policy {
    weight = var.secondary_weight
  }

  set_identifier  = "secondary"
  health_check_id = aws_route53_health_check.secondary.id
  records         = [module.vpc_secondary.alb_dns_name]
}

resource "aws_route53_record" "app_weighted_tertiary" {
  provider = aws.us_east_1
  zone_id  = local.hosted_zone_id
  name     = "app.${local.domain_name}"
  type     = "CNAME"
  ttl      = 60

  weighted_routing_policy {
    weight = var.tertiary_weight
  }

  set_identifier  = "tertiary"
  health_check_id = aws_route53_health_check.tertiary.id
  records         = [module.vpc_tertiary.alb_dns_name]
}

# Geolocation-based routing records
resource "aws_route53_record" "geo_primary" {
  provider = aws.us_east_1
  zone_id  = local.hosted_zone_id
  name     = "geo.${local.domain_name}"
  type     = "CNAME"
  ttl      = 60

  geolocation_routing_policy {
    continent = local.geo_locations.primary.continent_code
  }

  set_identifier  = "primary-geo"
  health_check_id = aws_route53_health_check.primary.id
  records         = [module.vpc_primary.alb_dns_name]
}

resource "aws_route53_record" "geo_secondary" {
  provider = aws.us_east_1
  zone_id  = local.hosted_zone_id
  name     = "geo.${local.domain_name}"
  type     = "CNAME"
  ttl      = 60

  geolocation_routing_policy {
    continent = local.geo_locations.secondary.continent_code
  }

  set_identifier  = "secondary-geo"
  health_check_id = aws_route53_health_check.secondary.id
  records         = [module.vpc_secondary.alb_dns_name]
}

resource "aws_route53_record" "geo_tertiary" {
  provider = aws.us_east_1
  zone_id  = local.hosted_zone_id
  name     = "geo.${local.domain_name}"
  type     = "CNAME"
  ttl      = 60

  geolocation_routing_policy {
    continent = local.geo_locations.tertiary.continent_code
  }

  set_identifier  = "tertiary-geo"
  health_check_id = aws_route53_health_check.tertiary.id
  records         = [module.vpc_tertiary.alb_dns_name]
}

# Default geolocation record (fallback to primary)
resource "aws_route53_record" "geo_default" {
  provider = aws.us_east_1
  zone_id  = local.hosted_zone_id
  name     = "geo.${local.domain_name}"
  type     = "CNAME"
  ttl      = 60

  geolocation_routing_policy {
    country = "*"
  }

  set_identifier  = "default-geo"
  health_check_id = aws_route53_health_check.primary.id
  records         = [module.vpc_primary.alb_dns_name]
}

# =====================================================
# CLOUDFRONT DISTRIBUTION
# =====================================================

# CloudFront Origin Access Control
resource "aws_cloudfront_origin_access_control" "s3_oac" {
  count                             = var.create_fallback_bucket ? 1 : 0
  provider                         = aws.us_east_1
  name                             = "${local.project_suffix}-s3-oac"
  description                      = "OAC for S3 fallback origin"
  origin_access_control_origin_type = "s3"
  signing_behavior                 = "always"
  signing_protocol                 = "sigv4"
}

# CloudFront distribution with origin groups for failover
resource "aws_cloudfront_distribution" "main" {
  provider = aws.us_east_1
  comment  = "Global load balancer with multi-region failover for ${var.project_name}"
  enabled  = true

  # Primary ALB origin
  origin {
    domain_name         = module.vpc_primary.alb_dns_name
    origin_id          = "primary-alb"
    connection_attempts = 3
    connection_timeout  = 10

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
      origin_read_timeout    = 30
      origin_keepalive_timeout = 5
    }
  }

  # Secondary ALB origin
  origin {
    domain_name         = module.vpc_secondary.alb_dns_name
    origin_id          = "secondary-alb"
    connection_attempts = 3
    connection_timeout  = 10

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
      origin_read_timeout    = 30
      origin_keepalive_timeout = 5
    }
  }

  # Tertiary ALB origin
  origin {
    domain_name         = module.vpc_tertiary.alb_dns_name
    origin_id          = "tertiary-alb"
    connection_attempts = 3
    connection_timeout  = 10

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
      origin_read_timeout    = 30
      origin_keepalive_timeout = 5
    }
  }

  # S3 fallback origin (conditional)
  dynamic "origin" {
    for_each = var.create_fallback_bucket ? [1] : []
    content {
      domain_name              = aws_s3_bucket.fallback[0].bucket_regional_domain_name
      origin_id               = "s3-fallback"
      origin_access_control_id = aws_cloudfront_origin_access_control.s3_oac[0].id
      connection_attempts      = 3
      connection_timeout       = 10
    }
  }

  # Origin group for automatic failover
  origin_group {
    origin_id = "main-origin-group"

    failover_criteria {
      status_codes = [403, 404, 500, 502, 503, 504]
    }

    member {
      origin_id = "primary-alb"
    }

    member {
      origin_id = "secondary-alb"
    }

    member {
      origin_id = "tertiary-alb"
    }

    dynamic "member" {
      for_each = var.create_fallback_bucket ? [1] : []
      content {
        origin_id = "s3-fallback"
      }
    }
  }

  # Default cache behavior
  default_cache_behavior {
    target_origin_id       = "main-origin-group"
    viewer_protocol_policy = "redirect-to-https"
    compress               = true

    allowed_methods = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods  = ["GET", "HEAD"]

    # Use managed cache policy for caching optimized for APIs
    cache_policy_id = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"

    # Use managed origin request policy for CORS
    origin_request_policy_id = "88a5eaf4-2fd4-4709-b370-b4c650ea3fcf"
  }

  # Cache behavior for health checks
  ordered_cache_behavior {
    path_pattern           = "/health"
    target_origin_id       = "main-origin-group"
    viewer_protocol_policy = "https-only"
    compress               = true

    allowed_methods = ["GET", "HEAD"]
    cached_methods  = ["GET", "HEAD"]

    # Use managed cache policy with shorter TTL for health checks
    cache_policy_id = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"

    # Use managed origin request policy
    origin_request_policy_id = "88a5eaf4-2fd4-4709-b370-b4c650ea3fcf"
  }

  # Custom error responses
  custom_error_response {
    error_code         = 500
    response_code      = 200
    response_page_path = "/index.html"
    error_caching_min_ttl = 0
  }

  custom_error_response {
    error_code         = 502
    response_code      = 200
    response_page_path = "/index.html"
    error_caching_min_ttl = 0
  }

  custom_error_response {
    error_code         = 503
    response_code      = 200
    response_page_path = "/index.html"
    error_caching_min_ttl = 0
  }

  custom_error_response {
    error_code         = 504
    response_code      = 200
    response_page_path = "/index.html"
    error_caching_min_ttl = 0
  }

  # Geographic restrictions
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  # SSL/TLS configuration
  viewer_certificate {
    cloudfront_default_certificate = true
    minimum_protocol_version       = var.cloudfront_minimum_protocol_version
  }

  # Performance settings
  price_class         = var.cloudfront_price_class
  http_version        = "http2and3"
  is_ipv6_enabled     = true
  default_root_object = "index.html"

  tags = merge(local.common_tags, {
    Name = "${local.project_suffix}-cloudfront-distribution"
  })
}

# S3 bucket policy for CloudFront access (if S3 fallback is enabled)
resource "aws_s3_bucket_policy" "fallback_cloudfront_access" {
  count    = var.create_fallback_bucket ? 1 : 0
  provider = aws.us_east_1
  bucket   = aws_s3_bucket.fallback[0].id

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
        Resource = "${aws_s3_bucket.fallback[0].arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.main.arn
          }
        }
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.fallback]
}

# =====================================================
# MONITORING AND ALERTING
# =====================================================

# SNS topic for alerts
resource "aws_sns_topic" "alerts" {
  count    = var.enable_cloudwatch_alarms ? 1 : 0
  provider = aws.us_east_1
  name     = "${local.project_suffix}-alerts"

  tags = merge(local.common_tags, {
    Name = "${local.project_suffix}-alerts-topic"
  })
}

# SNS topic subscription (if email provided)
resource "aws_sns_topic_subscription" "email_alerts" {
  count     = var.enable_cloudwatch_alarms && var.sns_email_endpoint != "" ? 1 : 0
  provider  = aws.us_east_1
  topic_arn = aws_sns_topic.alerts[0].arn
  protocol  = "email"
  endpoint  = var.sns_email_endpoint
}

# CloudWatch alarms for health checks
resource "aws_cloudwatch_metric_alarm" "health_check_primary" {
  count               = var.enable_cloudwatch_alarms ? 1 : 0
  provider            = aws.us_east_1
  alarm_name          = "${local.project_suffix}-health-primary"
  alarm_description   = "Health check alarm for primary region (${var.primary_region})"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "HealthCheckStatus"
  namespace           = "AWS/Route53"
  period              = "60"
  statistic           = "Minimum"
  threshold           = "1"
  alarm_actions       = [aws_sns_topic.alerts[0].arn]
  ok_actions          = [aws_sns_topic.alerts[0].arn]

  dimensions = {
    HealthCheckId = aws_route53_health_check.primary.id
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "health_check_secondary" {
  count               = var.enable_cloudwatch_alarms ? 1 : 0
  provider            = aws.us_east_1
  alarm_name          = "${local.project_suffix}-health-secondary"
  alarm_description   = "Health check alarm for secondary region (${var.secondary_region})"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "HealthCheckStatus"
  namespace           = "AWS/Route53"
  period              = "60"
  statistic           = "Minimum"
  threshold           = "1"
  alarm_actions       = [aws_sns_topic.alerts[0].arn]
  ok_actions          = [aws_sns_topic.alerts[0].arn]

  dimensions = {
    HealthCheckId = aws_route53_health_check.secondary.id
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "health_check_tertiary" {
  count               = var.enable_cloudwatch_alarms ? 1 : 0
  provider            = aws.us_east_1
  alarm_name          = "${local.project_suffix}-health-tertiary"
  alarm_description   = "Health check alarm for tertiary region (${var.tertiary_region})"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "HealthCheckStatus"
  namespace           = "AWS/Route53"
  period              = "60"
  statistic           = "Minimum"
  threshold           = "1"
  alarm_actions       = [aws_sns_topic.alerts[0].arn]
  ok_actions          = [aws_sns_topic.alerts[0].arn]

  dimensions = {
    HealthCheckId = aws_route53_health_check.tertiary.id
  }

  tags = local.common_tags
}

# CloudWatch alarm for CloudFront error rate
resource "aws_cloudwatch_metric_alarm" "cloudfront_errors" {
  count               = var.enable_cloudwatch_alarms ? 1 : 0
  provider            = aws.us_east_1
  alarm_name          = "${local.project_suffix}-cloudfront-errors"
  alarm_description   = "CloudFront 4xx error rate alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "4xxErrorRate"
  namespace           = "AWS/CloudFront"
  period              = "300"
  statistic           = "Average"
  threshold           = "5"
  alarm_actions       = [aws_sns_topic.alerts[0].arn]

  dimensions = {
    DistributionId = aws_cloudfront_distribution.main.id
  }

  tags = local.common_tags
}

# CloudWatch dashboard for monitoring
resource "aws_cloudwatch_dashboard" "main" {
  count          = var.enable_cloudwatch_alarms ? 1 : 0
  provider       = aws.us_east_1
  dashboard_name = "Global-LoadBalancer-${random_id.suffix.hex}"

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
            ["AWS/Route53", "HealthCheckStatus", "HealthCheckId", aws_route53_health_check.primary.id],
            [".", ".", ".", aws_route53_health_check.secondary.id],
            [".", ".", ".", aws_route53_health_check.tertiary.id]
          ]
          period = 300
          stat   = "Minimum"
          region = "us-east-1"
          title  = "Route53 Health Check Status"
          yAxis = {
            left = {
              min = 0
              max = 1
            }
          }
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
            ["AWS/CloudFront", "Requests", "DistributionId", aws_cloudfront_distribution.main.id],
            [".", "4xxErrorRate", ".", "."],
            [".", "5xxErrorRate", ".", "."]
          ]
          period = 300
          stat   = "Average"
          region = "us-east-1"
          title  = "CloudFront Performance"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 24
        height = 6

        properties = {
          metrics = [
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", module.vpc_primary.alb_arn_suffix],
            [".", ".", ".", module.vpc_secondary.alb_arn_suffix],
            [".", ".", ".", module.vpc_tertiary.alb_arn_suffix]
          ]
          period = 300
          stat   = "Average"
          region = "us-east-1"
          title  = "ALB Response Times Across Regions"
        }
      }
    ]
  })

  tags = local.common_tags
}