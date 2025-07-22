# Output Values for Static Website Infrastructure
# These outputs provide important information about the created resources

output "website_url" {
  description = "Primary website URL with HTTPS"
  value       = "https://${var.domain_name}"
}

output "website_subdomain_url" {
  description = "Subdomain website URL with HTTPS"
  value       = "https://${local.subdomain_fqdn}"
}

output "cloudfront_distribution_id" {
  description = "CloudFront Distribution ID for cache invalidation and management"
  value       = aws_cloudfront_distribution.website.id
}

output "cloudfront_distribution_arn" {
  description = "CloudFront Distribution ARN for IAM policies and resource references"
  value       = aws_cloudfront_distribution.website.arn
}

output "cloudfront_domain_name" {
  description = "CloudFront distribution domain name (for direct access without custom domain)"
  value       = aws_cloudfront_distribution.website.domain_name
}

output "s3_bucket_name" {
  description = "S3 bucket name for website content uploads"
  value       = aws_s3_bucket.website.id
}

output "s3_bucket_arn" {
  description = "S3 bucket ARN for IAM policies and resource references"
  value       = aws_s3_bucket.website.arn
}

output "s3_bucket_domain_name" {
  description = "S3 bucket regional domain name"
  value       = aws_s3_bucket.website.bucket_regional_domain_name
}

output "s3_website_endpoint" {
  description = "S3 website endpoint (for reference, not for direct access)"
  value       = aws_s3_bucket_website_configuration.website.website_endpoint
}

output "certificate_arn" {
  description = "SSL certificate ARN from AWS Certificate Manager"
  value       = aws_acm_certificate.website.arn
}

output "certificate_status" {
  description = "SSL certificate validation status"
  value       = aws_acm_certificate.website.status
}

output "certificate_domain_validation_options" {
  description = "Domain validation options for the SSL certificate"
  value       = aws_acm_certificate.website.domain_validation_options
  sensitive   = true
}

output "hosted_zone_id" {
  description = "Route 53 hosted zone ID used for DNS records"
  value       = local.hosted_zone_id
}

output "origin_access_control_id" {
  description = "CloudFront Origin Access Control ID"
  value       = aws_cloudfront_origin_access_control.website.id
}

output "dns_records_created" {
  description = "DNS records created for the website"
  value = {
    root_domain = {
      name = aws_route53_record.website_root.name
      type = aws_route53_record.website_root.type
    }
    subdomain = {
      name = aws_route53_record.website_subdomain.name
      type = aws_route53_record.website_subdomain.type
    }
  }
}

# Deployment and management information
output "deployment_info" {
  description = "Important deployment and management information"
  value = {
    # Upload files to S3 bucket using AWS CLI
    s3_upload_command = "aws s3 sync ./website-content/ s3://${aws_s3_bucket.website.id}/ --delete"
    
    # Invalidate CloudFront cache after content updates
    cloudfront_invalidation_command = "aws cloudfront create-invalidation --distribution-id ${aws_cloudfront_distribution.website.id} --paths '/*'"
    
    # Check website certificate status
    certificate_check_command = "aws acm describe-certificate --certificate-arn ${aws_acm_certificate.website.arn} --region us-east-1"
    
    # Website testing commands
    test_commands = {
      curl_https = "curl -I https://${var.domain_name}"
      curl_subdomain = "curl -I https://${local.subdomain_fqdn}"
      ssl_check = "openssl s_client -connect ${var.domain_name}:443 -servername ${var.domain_name} < /dev/null 2>/dev/null | openssl x509 -text -noout | grep -A 2 'Subject:'"
    }
  }
}

# Cost optimization information
output "cost_optimization_tips" {
  description = "Tips for optimizing costs"
  value = {
    cloudfront_price_class = "Current price class: ${var.price_class}. Consider PriceClass_100 for cost optimization if global reach is not critical."
    s3_storage_class = "Consider using S3 Intelligent-Tiering or lifecycle policies for cost optimization of static assets."
    certificate_cost = "ACM certificates are free when used with AWS services like CloudFront."
    monitoring_suggestion = "Enable CloudWatch billing alerts to monitor costs."
  }
}

# Security information
output "security_features" {
  description = "Security features implemented"
  value = {
    ssl_tls = "SSL/TLS certificate with minimum protocol version: ${var.minimum_protocol_version}"
    https_redirect = "Automatic HTTP to HTTPS redirect enabled"
    origin_access_control = "Origin Access Control prevents direct S3 access"
    s3_public_access = "S3 public access blocked for security"
    certificate_validation = "Domain validation method: ${var.certificate_validation_method}"
  }
}

# Performance information
output "performance_features" {
  description = "Performance optimization features"
  value = {
    cdn = "Global CloudFront CDN for fast content delivery"
    compression = var.enable_compression ? "Gzip compression enabled" : "Gzip compression disabled"
    ipv6 = var.enable_ipv6 ? "IPv6 support enabled" : "IPv6 support disabled"
    cache_ttl = "Default cache TTL: ${var.cloudfront_cache_ttl} seconds"
    edge_locations = "Content cached at AWS edge locations worldwide"
  }
}