# Output values for the static website hosting infrastructure

output "website_url" {
  description = "Primary website URL (www subdomain)"
  value       = "https://${local.www_domain_name}"
}

output "root_domain_url" {
  description = "Root domain URL (redirects to www)"
  value       = "https://${var.domain_name}"
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID for www subdomain"
  value       = aws_cloudfront_distribution.www_distribution.id
}

output "cloudfront_distribution_domain_name" {
  description = "CloudFront distribution domain name for www subdomain"
  value       = aws_cloudfront_distribution.www_distribution.domain_name
}

output "root_cloudfront_distribution_id" {
  description = "CloudFront distribution ID for root domain redirect"
  value       = aws_cloudfront_distribution.root_distribution.id
}

output "root_cloudfront_distribution_domain_name" {
  description = "CloudFront distribution domain name for root domain"
  value       = aws_cloudfront_distribution.root_distribution.domain_name
}

output "s3_bucket_name" {
  description = "Name of the S3 bucket hosting the website content"
  value       = aws_s3_bucket.www_bucket.id
}

output "s3_bucket_website_endpoint" {
  description = "Website endpoint for the S3 bucket"
  value       = aws_s3_bucket_website_configuration.www_bucket.website_endpoint
}

output "s3_root_bucket_name" {
  description = "Name of the S3 bucket for root domain redirect"
  value       = aws_s3_bucket.root_bucket.id
}

output "s3_root_bucket_website_endpoint" {
  description = "Website endpoint for the root domain redirect bucket"
  value       = aws_s3_bucket_website_configuration.root_bucket.website_endpoint
}

output "ssl_certificate_arn" {
  description = "ARN of the SSL certificate"
  value       = aws_acm_certificate.cert.arn
}

output "ssl_certificate_status" {
  description = "Status of the SSL certificate"
  value       = aws_acm_certificate.cert.status
}

output "route53_zone_id" {
  description = "Route 53 hosted zone ID"
  value       = var.create_route53_zone ? aws_route53_zone.main[0].zone_id : data.aws_route53_zone.main[0].zone_id
}

output "route53_zone_name_servers" {
  description = "Name servers for the Route 53 hosted zone (if created)"
  value       = var.create_route53_zone ? aws_route53_zone.main[0].name_servers : null
}

output "cloudfront_hosted_zone_id" {
  description = "CloudFront hosted zone ID for Route 53 alias records"
  value       = aws_cloudfront_distribution.www_distribution.hosted_zone_id
}

output "deployment_commands" {
  description = "Commands to deploy content to the website"
  value = {
    sync_content = "aws s3 sync ./website-content/ s3://${aws_s3_bucket.www_bucket.id}/ --delete"
    invalidate_cache = "aws cloudfront create-invalidation --distribution-id ${aws_cloudfront_distribution.www_distribution.id} --paths '/*'"
  }
}

# Cost estimation information
output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown (USD)"
  value = {
    cloudfront_requests = "First 1B requests per month: $0.0075 per 10,000 requests"
    cloudfront_data_transfer = "First 10 TB per month: $0.085 per GB"
    s3_storage = "Standard storage: $0.023 per GB per month"
    s3_requests = "PUT/POST requests: $0.0005 per 1,000 requests"
    route53_hosted_zone = "$0.50 per hosted zone per month"
    route53_queries = "First 1B queries per month: $0.40 per million queries"
    ssl_certificate = "Free when used with CloudFront"
    note = "Actual costs vary based on usage patterns and AWS region"
  }
}

# DNS configuration instructions
output "dns_configuration" {
  description = "DNS configuration instructions"
  value = var.create_route53_zone ? {
    message = "Route 53 hosted zone created. Update your domain registrar's name servers to:"
    name_servers = aws_route53_zone.main[0].name_servers
  } : {
    message = "Using existing Route 53 hosted zone"
    zone_id = data.aws_route53_zone.main[0].zone_id
  }
}

# Validation URLs for testing
output "validation_urls" {
  description = "URLs for validating the deployment"
  value = {
    primary_site = "https://${local.www_domain_name}"
    root_redirect = "https://${var.domain_name}"
    ssl_test = "https://www.ssllabs.com/ssltest/analyze.html?d=${local.www_domain_name}"
    performance_test = "https://developers.google.com/speed/pagespeed/insights/?url=https://${local.www_domain_name}"
  }
}

# Security headers recommendations
output "security_recommendations" {
  description = "Recommended security enhancements"
  value = {
    lambda_at_edge = "Consider implementing Lambda@Edge for security headers"
    cloudfront_functions = "Use CloudFront Functions for lightweight request/response modifications"
    waf = "Consider AWS WAF for additional protection against common web exploits"
    shield = "AWS Shield Standard is automatically enabled for CloudFront distributions"
  }
}