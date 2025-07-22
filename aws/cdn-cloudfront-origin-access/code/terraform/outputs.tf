# Output values for the CloudFront CDN infrastructure

# ============================================================================
# CLOUDFRONT DISTRIBUTION OUTPUTS
# ============================================================================

output "cloudfront_distribution_id" {
  description = "The identifier for the CloudFront distribution"
  value       = aws_cloudfront_distribution.main.id
}

output "cloudfront_distribution_arn" {
  description = "The ARN (Amazon Resource Name) for the CloudFront distribution"
  value       = aws_cloudfront_distribution.main.arn
}

output "cloudfront_domain_name" {
  description = "The domain name corresponding to the CloudFront distribution"
  value       = aws_cloudfront_distribution.main.domain_name
}

output "cloudfront_distribution_url" {
  description = "The full HTTPS URL of the CloudFront distribution"
  value       = "https://${aws_cloudfront_distribution.main.domain_name}"
}

output "cloudfront_hosted_zone_id" {
  description = "The CloudFront Route 53 zone ID that can be used to route an alias record to"
  value       = aws_cloudfront_distribution.main.hosted_zone_id
}

output "cloudfront_status" {
  description = "The current status of the CloudFront distribution"
  value       = aws_cloudfront_distribution.main.status
}

# ============================================================================
# S3 BUCKET OUTPUTS
# ============================================================================

output "s3_content_bucket_name" {
  description = "The name of the S3 bucket containing the website content"
  value       = aws_s3_bucket.content.id
}

output "s3_content_bucket_arn" {
  description = "The ARN of the S3 content bucket"
  value       = aws_s3_bucket.content.arn
}

output "s3_content_bucket_domain_name" {
  description = "The bucket domain name of the S3 content bucket"
  value       = aws_s3_bucket.content.bucket_domain_name
}

output "s3_content_bucket_regional_domain_name" {
  description = "The bucket regional domain name of the S3 content bucket"
  value       = aws_s3_bucket.content.bucket_regional_domain_name
}

output "s3_logs_bucket_name" {
  description = "The name of the S3 bucket for CloudFront access logs"
  value       = var.enable_logging ? aws_s3_bucket.logs[0].id : "Logging disabled"
}

output "s3_logs_bucket_arn" {
  description = "The ARN of the S3 logs bucket"
  value       = var.enable_logging ? aws_s3_bucket.logs[0].arn : "Logging disabled"
}

# ============================================================================
# ORIGIN ACCESS CONTROL OUTPUTS
# ============================================================================

output "origin_access_control_id" {
  description = "The unique identifier of the Origin Access Control"
  value       = aws_cloudfront_origin_access_control.main.id
}

output "origin_access_control_etag" {
  description = "The current version of the Origin Access Control"
  value       = aws_cloudfront_origin_access_control.main.etag
}

# ============================================================================
# WAF OUTPUTS
# ============================================================================

output "waf_web_acl_id" {
  description = "The ID of the WAF WebACL"
  value       = var.enable_waf ? aws_wafv2_web_acl.main[0].id : "WAF disabled"
}

output "waf_web_acl_arn" {
  description = "The ARN of the WAF WebACL"
  value       = var.enable_waf ? aws_wafv2_web_acl.main[0].arn : "WAF disabled"
}

output "waf_web_acl_name" {
  description = "The name of the WAF WebACL"
  value       = var.enable_waf ? aws_wafv2_web_acl.main[0].name : "WAF disabled"
}

# ============================================================================
# CLOUDWATCH MONITORING OUTPUTS
# ============================================================================

output "cloudwatch_4xx_alarm_name" {
  description = "The name of the CloudWatch alarm for 4xx errors"
  value       = var.enable_monitoring ? aws_cloudwatch_metric_alarm.high_4xx_error_rate[0].alarm_name : "Monitoring disabled"
}

output "cloudwatch_5xx_alarm_name" {
  description = "The name of the CloudWatch alarm for 5xx errors"
  value       = var.enable_monitoring ? aws_cloudwatch_metric_alarm.high_5xx_error_rate[0].alarm_name : "Monitoring disabled"
}

output "cloudwatch_cache_hit_alarm_name" {
  description = "The name of the CloudWatch alarm for cache hit rate"
  value       = var.enable_monitoring ? aws_cloudwatch_metric_alarm.low_cache_hit_rate[0].alarm_name : "Monitoring disabled"
}

# ============================================================================
# TESTING AND VALIDATION OUTPUTS
# ============================================================================

output "test_urls" {
  description = "URLs for testing different content types through CloudFront"
  value = {
    main_page = "https://${aws_cloudfront_distribution.main.domain_name}/"
    css_file  = "https://${aws_cloudfront_distribution.main.domain_name}/css/styles.css"
    js_file   = "https://${aws_cloudfront_distribution.main.domain_name}/js/main.js"
    image     = "https://${aws_cloudfront_distribution.main.domain_name}/images/test-image.jpg"
  }
}

output "curl_test_commands" {
  description = "Curl commands for testing the CloudFront distribution"
  value = {
    test_main_page = "curl -I https://${aws_cloudfront_distribution.main.domain_name}/"
    test_css_cache = "curl -I https://${aws_cloudfront_distribution.main.domain_name}/css/styles.css"
    test_security_headers = "curl -I https://${aws_cloudfront_distribution.main.domain_name}/ | grep -E '(X-Frame-Options|X-Content-Type-Options|Strict-Transport-Security)'"
    test_cache_hit = "curl -I https://${aws_cloudfront_distribution.main.domain_name}/css/styles.css | grep X-Cache"
  }
}

# ============================================================================
# SECURITY AND CONFIGURATION OUTPUTS
# ============================================================================

output "security_features_enabled" {
  description = "Summary of security features enabled"
  value = {
    origin_access_control = "Enabled - Modern S3 origin protection"
    waf_protection       = var.enable_waf ? "Enabled - Common rules and rate limiting" : "Disabled"
    https_redirect       = "Enabled - All HTTP traffic redirected to HTTPS"
    security_headers     = "Enabled - AWS managed security headers policy"
    public_access_block  = "Enabled - S3 buckets blocked from public access"
    encryption          = "Enabled - S3 server-side encryption with AES256"
  }
}

output "cache_configuration" {
  description = "Summary of cache configuration"
  value = {
    default_cache_policy    = "AWS Managed - CachingOptimized"
    compression_enabled     = "Yes - Gzip compression for text files"
    custom_cache_behaviors  = "3 - Optimized for /images/*, /css/*, /js/*"
    custom_error_responses  = "2 - SPA-friendly 404/403 handling"
  }
}

# ============================================================================
# COST AND PERFORMANCE INFORMATION
# ============================================================================

output "performance_features" {
  description = "Performance optimization features enabled"
  value = {
    http_version        = "HTTP/2 and HTTP/3 supported"
    ipv6_enabled       = "Yes - Global IPv6 support"
    price_class        = var.price_class
    compression        = "Enabled for all cache behaviors"
    origin_shield      = "Not enabled (can be added for high-traffic scenarios)"
  }
}

output "estimated_monthly_costs" {
  description = "Rough estimated monthly costs for typical usage"
  value = {
    note = "Costs depend on traffic volume and geographic distribution"
    cloudfront_requests = "~$0.0075 per 10,000 requests"
    data_transfer = "~$0.085 per GB (varies by region)"
    s3_storage = "~$0.023 per GB stored"
    waf_web_acl = var.enable_waf ? "~$1.00 base + $0.60 per million requests" : "$0 (disabled)"
    total_minimum = var.enable_waf ? "~$1.00/month minimum (excluding traffic)" : "~$0.023/month per GB stored minimum"
  }
}

# ============================================================================
# NEXT STEPS AND RECOMMENDATIONS
# ============================================================================

output "next_steps" {
  description = "Recommended next steps for production deployment"
  value = {
    custom_domain = var.custom_domain == "" ? "Configure custom domain and SSL certificate" : "Custom domain configured: ${var.custom_domain}"
    monitoring = var.enable_monitoring ? "Review CloudWatch alarms and set notification targets" : "Enable monitoring for production workloads"
    content_upload = "Upload your actual website content to: ${aws_s3_bucket.content.id}"
    performance_tuning = "Monitor cache hit ratios and adjust cache behaviors as needed"
    security_review = "Review WAF rules and consider additional custom rules for your use case"
    backup_strategy = "Implement S3 Cross-Region Replication for disaster recovery"
  }
}

output "useful_aws_cli_commands" {
  description = "Useful AWS CLI commands for managing the infrastructure"
  value = {
    invalidate_cache = "aws cloudfront create-invalidation --distribution-id ${aws_cloudfront_distribution.main.id} --paths '/*'"
    check_distribution_status = "aws cloudfront get-distribution --id ${aws_cloudfront_distribution.main.id} --query 'Distribution.Status'"
    list_s3_objects = "aws s3 ls s3://${aws_s3_bucket.content.id}/ --recursive"
    sync_content = "aws s3 sync ./your-content/ s3://${aws_s3_bucket.content.id}/ --delete"
    view_cloudfront_logs = var.enable_logging ? "aws s3 ls s3://${aws_s3_bucket.logs[0].id}/cloudfront-logs/" : "Logging not enabled"
  }
}