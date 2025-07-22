# Output values for CloudFront and S3 CDN infrastructure

# CloudFront Distribution outputs
output "cloudfront_distribution_id" {
  description = "ID of the CloudFront distribution"
  value       = aws_cloudfront_distribution.cdn_distribution.id
}

output "cloudfront_distribution_arn" {
  description = "ARN of the CloudFront distribution"
  value       = aws_cloudfront_distribution.cdn_distribution.arn
}

output "cloudfront_domain_name" {
  description = "Domain name of the CloudFront distribution"
  value       = aws_cloudfront_distribution.cdn_distribution.domain_name
}

output "cloudfront_hosted_zone_id" {
  description = "CloudFront hosted zone ID for Route 53 alias records"
  value       = aws_cloudfront_distribution.cdn_distribution.hosted_zone_id
}

output "cloudfront_status" {
  description = "Current status of the CloudFront distribution"
  value       = aws_cloudfront_distribution.cdn_distribution.status
}

output "cloudfront_etag" {
  description = "Current version of the CloudFront distribution's configuration"
  value       = aws_cloudfront_distribution.cdn_distribution.etag
}

# S3 Content Bucket outputs
output "content_bucket_id" {
  description = "ID of the S3 content bucket"
  value       = aws_s3_bucket.content_bucket.id
}

output "content_bucket_arn" {
  description = "ARN of the S3 content bucket"
  value       = aws_s3_bucket.content_bucket.arn
}

output "content_bucket_domain_name" {
  description = "Domain name of the S3 content bucket"
  value       = aws_s3_bucket.content_bucket.bucket_domain_name
}

output "content_bucket_regional_domain_name" {
  description = "Regional domain name of the S3 content bucket"
  value       = aws_s3_bucket.content_bucket.bucket_regional_domain_name
}

# S3 Logs Bucket outputs (conditional)
output "logs_bucket_id" {
  description = "ID of the S3 logs bucket"
  value       = var.enable_cloudfront_logging ? aws_s3_bucket.logs_bucket[0].id : null
}

output "logs_bucket_arn" {
  description = "ARN of the S3 logs bucket"
  value       = var.enable_cloudfront_logging ? aws_s3_bucket.logs_bucket[0].arn : null
}

output "logs_bucket_domain_name" {
  description = "Domain name of the S3 logs bucket"
  value       = var.enable_cloudfront_logging ? aws_s3_bucket.logs_bucket[0].bucket_domain_name : null
}

# Origin Access Control outputs
output "origin_access_control_id" {
  description = "ID of the CloudFront Origin Access Control"
  value       = aws_cloudfront_origin_access_control.oac.id
}

output "origin_access_control_etag" {
  description = "ETag of the CloudFront Origin Access Control"
  value       = aws_cloudfront_origin_access_control.oac.etag
}

# Response Headers Policy outputs
output "response_headers_policy_id" {
  description = "ID of the CloudFront Response Headers Policy"
  value       = aws_cloudfront_response_headers_policy.security_headers.id
}

output "response_headers_policy_etag" {
  description = "ETag of the CloudFront Response Headers Policy"
  value       = aws_cloudfront_response_headers_policy.security_headers.etag
}

# CloudWatch Alarms outputs (conditional)
output "high_error_rate_alarm_arn" {
  description = "ARN of the CloudWatch alarm for high error rate"
  value       = var.enable_cloudwatch_monitoring ? aws_cloudwatch_metric_alarm.high_error_rate[0].arn : null
}

output "high_origin_latency_alarm_arn" {
  description = "ARN of the CloudWatch alarm for high origin latency"
  value       = var.enable_cloudwatch_monitoring ? aws_cloudwatch_metric_alarm.high_origin_latency[0].arn : null
}

output "cloudwatch_dashboard_url" {
  description = "URL of the CloudWatch dashboard"
  value       = var.enable_cloudwatch_monitoring ? "https://console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.cdn_dashboard[0].dashboard_name}" : null
}

# Testing and validation outputs
output "test_urls" {
  description = "URLs for testing different cache behaviors"
  value = {
    main_page = "https://${aws_cloudfront_distribution.cdn_distribution.domain_name}/"
    css_file  = "https://${aws_cloudfront_distribution.cdn_distribution.domain_name}/styles.css"
    api_endpoint = "https://${aws_cloudfront_distribution.cdn_distribution.domain_name}/api/response.json"
  }
}

# Deployment information
output "deployment_info" {
  description = "Important deployment information"
  value = {
    distribution_deployed = aws_cloudfront_distribution.cdn_distribution.status == "Deployed"
    cache_invalidation_command = "aws cloudfront create-invalidation --distribution-id ${aws_cloudfront_distribution.cdn_distribution.id} --paths '/*'"
    s3_sync_command = "aws s3 sync ./content/ s3://${aws_s3_bucket.content_bucket.id}/"
  }
}

# Security information
output "security_info" {
  description = "Security configuration information"
  value = {
    origin_access_control_enabled = true
    s3_bucket_public_access_blocked = true
    https_redirect_enabled = true
    security_headers_enabled = true
    minimum_tls_version = "TLSv1.2_2021"
  }
}

# Cost optimization information
output "cost_optimization_info" {
  description = "Cost optimization settings"
  value = {
    price_class = var.cloudfront_price_class
    compression_enabled = var.enable_compression
    logging_enabled = var.enable_cloudfront_logging
    edge_locations = var.cloudfront_price_class == "PriceClass_100" ? "US and Europe" : var.cloudfront_price_class == "PriceClass_200" ? "US, Europe, and Asia" : "Global"
  }
}

# Cache configuration summary
output "cache_configuration" {
  description = "Cache configuration summary"
  value = {
    default_ttl = var.cloudfront_default_ttl
    max_ttl = var.cloudfront_max_ttl
    min_ttl = var.cloudfront_min_ttl
    css_default_ttl = 2592000  # 30 days
    js_default_ttl = 2592000   # 30 days
    images_default_ttl = 2592000 # 30 days
    api_default_ttl = 3600     # 1 hour
  }
}

# Random suffix for reference
output "resource_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_string.suffix.result
}