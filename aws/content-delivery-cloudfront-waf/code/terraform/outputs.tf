# Output values for secure content delivery infrastructure

# CloudFront Distribution Information
output "cloudfront_distribution_id" {
  description = "ID of the CloudFront distribution"
  value       = aws_cloudfront_distribution.main.id
}

output "cloudfront_distribution_arn" {
  description = "ARN of the CloudFront distribution"
  value       = aws_cloudfront_distribution.main.arn
}

output "cloudfront_domain_name" {
  description = "Domain name of the CloudFront distribution"
  value       = aws_cloudfront_distribution.main.domain_name
}

output "cloudfront_hosted_zone_id" {
  description = "CloudFront Route 53 hosted zone ID"
  value       = aws_cloudfront_distribution.main.hosted_zone_id
}

output "cloudfront_distribution_url" {
  description = "HTTPS URL of the CloudFront distribution"
  value       = "https://${aws_cloudfront_distribution.main.domain_name}"
}

output "cloudfront_status" {
  description = "Current status of the CloudFront distribution"
  value       = aws_cloudfront_distribution.main.status
}

# S3 Bucket Information
output "s3_bucket_name" {
  description = "Name of the S3 bucket storing content"
  value       = aws_s3_bucket.content.id
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket storing content"
  value       = aws_s3_bucket.content.arn
}

output "s3_bucket_domain_name" {
  description = "Domain name of the S3 bucket"
  value       = aws_s3_bucket.content.bucket_domain_name
}

output "s3_bucket_regional_domain_name" {
  description = "Regional domain name of the S3 bucket"
  value       = aws_s3_bucket.content.bucket_regional_domain_name
}

# WAF Information
output "waf_web_acl_id" {
  description = "ID of the WAF Web ACL"
  value       = aws_wafv2_web_acl.main.id
}

output "waf_web_acl_arn" {
  description = "ARN of the WAF Web ACL"
  value       = aws_wafv2_web_acl.main.arn
}

output "waf_web_acl_name" {
  description = "Name of the WAF Web ACL"
  value       = aws_wafv2_web_acl.main.name
}

output "waf_rate_limit" {
  description = "Configured rate limit for WAF rate-based rule"
  value       = var.waf_rate_limit
}

# Origin Access Control Information
output "origin_access_control_id" {
  description = "ID of the CloudFront Origin Access Control"
  value       = aws_cloudfront_origin_access_control.main.id
}

output "origin_access_control_etag" {
  description = "ETag of the CloudFront Origin Access Control"
  value       = aws_cloudfront_origin_access_control.main.etag
}

# Security Configuration
output "blocked_countries" {
  description = "List of countries blocked by geographic restrictions"
  value       = var.enable_geo_restrictions ? var.blocked_countries : []
}

output "geo_restrictions_enabled" {
  description = "Whether geographic restrictions are enabled"
  value       = var.enable_geo_restrictions
}

output "waf_managed_rules" {
  description = "List of enabled WAF managed rules"
  value = [
    for rule in var.waf_managed_rules : {
      name     = rule.name
      priority = rule.priority
      action   = rule.action
    }
  ]
}

# Monitoring Information
output "cloudwatch_dashboard_url" {
  description = "URL to the CloudWatch dashboard"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.main.dashboard_name}"
}

output "waf_logs_group_name" {
  description = "Name of the CloudWatch log group for WAF logs (if enabled)"
  value       = var.enable_waf_logging ? aws_cloudwatch_log_group.waf_logs[0].name : null
}

output "waf_logs_group_arn" {
  description = "ARN of the CloudWatch log group for WAF logs (if enabled)"
  value       = var.enable_waf_logging ? aws_cloudwatch_log_group.waf_logs[0].arn : null
}

# CloudFront Logs Bucket (if enabled)
output "cloudfront_logs_bucket_name" {
  description = "Name of the S3 bucket for CloudFront logs (if enabled)"
  value       = var.enable_cloudfront_logging ? aws_s3_bucket.cloudfront_logs[0].id : null
}

output "cloudfront_logs_bucket_arn" {
  description = "ARN of the S3 bucket for CloudFront logs (if enabled)"
  value       = var.enable_cloudfront_logging ? aws_s3_bucket.cloudfront_logs[0].arn : null
}

# Testing Information
output "sample_content_url" {
  description = "URL to test the sample content (if created)"
  value       = var.create_sample_content ? "https://${aws_cloudfront_distribution.main.domain_name}/index.html" : null
}

output "curl_test_command" {
  description = "Command to test the CloudFront distribution with curl"
  value       = "curl -I https://${aws_cloudfront_distribution.main.domain_name}/index.html"
}

# Resource Tags
output "common_tags" {
  description = "Common tags applied to all resources"
  value = merge(
    {
      Project     = "secure-content-delivery"
      Environment = var.environment
      ManagedBy   = "terraform"
      Recipe      = "content-delivery-cloudfront-waf"
    },
    var.tags
  )
}

# Cost Information
output "estimated_monthly_cost_info" {
  description = "Information about estimated monthly costs"
  value = {
    note = "Costs depend on traffic volume and features enabled"
    components = [
      "CloudFront: $0.085/GB for data transfer + $0.0075 per 10,000 requests",
      "WAF: $1.00/month per Web ACL + $0.60 per million requests",
      "S3: $0.023/GB/month for Standard storage",
      "CloudWatch: $0.50/GB for log ingestion (if logging enabled)"
    ]
    calculator_url = "https://calculator.aws/"
  }
}

# Security Validation Commands
output "validation_commands" {
  description = "Commands to validate the deployment"
  value = {
    test_https_access = "curl -I https://${aws_cloudfront_distribution.main.domain_name}/index.html"
    test_http_redirect = "curl -I http://${aws_cloudfront_distribution.main.domain_name}/index.html"
    check_s3_direct_access = "curl -I https://${aws_s3_bucket.content.bucket_regional_domain_name}/index.html"
    check_waf_status = "aws wafv2 get-web-acl --scope CLOUDFRONT --region us-east-1 --id ${aws_wafv2_web_acl.main.id}"
    check_cloudfront_status = "aws cloudfront get-distribution --id ${aws_cloudfront_distribution.main.id}"
  }
}