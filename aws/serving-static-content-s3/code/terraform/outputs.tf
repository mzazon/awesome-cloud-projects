# Output Values for Static Website Hosting Infrastructure
# These outputs provide important information about the deployed resources

# S3 Bucket Information
output "s3_bucket_name" {
  description = "Name of the S3 bucket hosting the website content"
  value       = aws_s3_bucket.website.id
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket hosting the website content"
  value       = aws_s3_bucket.website.arn
}

output "s3_bucket_domain_name" {
  description = "Domain name of the S3 bucket"
  value       = aws_s3_bucket.website.bucket_domain_name
}

output "s3_bucket_regional_domain_name" {
  description = "Regional domain name of the S3 bucket"
  value       = aws_s3_bucket.website.bucket_regional_domain_name
}

output "s3_logs_bucket_name" {
  description = "Name of the S3 bucket for CloudFront access logs"
  value       = var.enable_logging ? aws_s3_bucket.logs[0].id : null
}

# CloudFront Distribution Information
output "cloudfront_distribution_id" {
  description = "ID of the CloudFront distribution"
  value       = aws_cloudfront_distribution.website.id
}

output "cloudfront_distribution_arn" {
  description = "ARN of the CloudFront distribution"
  value       = aws_cloudfront_distribution.website.arn
}

output "cloudfront_domain_name" {
  description = "Domain name of the CloudFront distribution"
  value       = aws_cloudfront_distribution.website.domain_name
}

output "cloudfront_hosted_zone_id" {
  description = "Hosted zone ID of the CloudFront distribution"
  value       = aws_cloudfront_distribution.website.hosted_zone_id
}

output "cloudfront_status" {
  description = "Current status of the CloudFront distribution"
  value       = aws_cloudfront_distribution.website.status
}

# Website URLs
output "website_url" {
  description = "Primary URL to access the website"
  value       = var.domain_name != "" ? "https://${var.domain_name}" : "https://${aws_cloudfront_distribution.website.domain_name}"
}

output "cloudfront_url" {
  description = "CloudFront distribution URL"
  value       = "https://${aws_cloudfront_distribution.website.domain_name}"
}

# SSL Certificate Information (if custom domain is used)
output "ssl_certificate_arn" {
  description = "ARN of the SSL certificate (if custom domain is configured)"
  value       = local.create_certificate ? aws_acm_certificate.website[0].arn : null
}

output "ssl_certificate_status" {
  description = "Status of the SSL certificate (if custom domain is configured)"
  value       = local.create_certificate ? aws_acm_certificate.website[0].status : null
}

# Route 53 Information (if DNS is managed)
output "route53_hosted_zone_id" {
  description = "Route 53 hosted zone ID (if DNS record was created)"
  value       = local.create_dns_record ? data.aws_route53_zone.main[0].zone_id : null
}

output "route53_name_servers" {
  description = "Route 53 name servers (if DNS record was created)"
  value       = local.create_dns_record ? data.aws_route53_zone.main[0].name_servers : null
}

# Origin Access Control Information
output "origin_access_control_id" {
  description = "ID of the CloudFront Origin Access Control"
  value       = aws_cloudfront_origin_access_control.website.id
}

# Deployment Information
output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_string.bucket_suffix.result
}

output "deployment_region" {
  description = "AWS region where resources were deployed"
  value       = data.aws_region.current.name
}

output "aws_account_id" {
  description = "AWS account ID where resources were deployed"
  value       = data.aws_caller_identity.current.account_id
}

# Instructions and Next Steps
output "deployment_instructions" {
  description = "Instructions for completing the website deployment"
  value = <<-EOT
🎉 Static Website Infrastructure Deployed Successfully!

📋 Deployment Summary:
   • S3 Bucket: ${aws_s3_bucket.website.id}
   • CloudFront Distribution: ${aws_cloudfront_distribution.website.id}
   • Primary URL: ${var.domain_name != "" ? "https://${var.domain_name}" : "https://${aws_cloudfront_distribution.website.domain_name}"}
   ${var.enable_logging ? "• Access Logs: ${aws_s3_bucket.logs[0].id}" : ""}

🚀 Next Steps:
   1. Wait 5-10 minutes for CloudFront deployment to complete
   2. Upload your website content to: s3://${aws_s3_bucket.website.id}/
   3. Access your website at: ${var.domain_name != "" ? "https://${var.domain_name}" : "https://${aws_cloudfront_distribution.website.domain_name}"}
   ${var.domain_name != "" && !var.create_route53_record ? "4. Configure DNS: Point ${var.domain_name} to ${aws_cloudfront_distribution.website.domain_name}" : ""}

📁 File Upload Commands:
   # Upload a file
   aws s3 cp /path/to/your/file.html s3://${aws_s3_bucket.website.id}/

   # Sync entire directory
   aws s3 sync /path/to/your/website/ s3://${aws_s3_bucket.website.id}/

   # Invalidate CloudFront cache after updates
   aws cloudfront create-invalidation --distribution-id ${aws_cloudfront_distribution.website.id} --paths "/*"

💡 Tips:
   • Sample content has been uploaded to get you started
   • All content is served via HTTPS automatically
   • CloudFront provides global caching for better performance
   • Use 'terraform destroy' to remove all resources when done

EOT
}

# Cost Estimation
output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown for the deployed resources"
  value = <<-EOT
💰 Estimated Monthly Costs (for small website):

S3 Storage:
   • First 50 TB: ~$0.023 per GB
   • Example: 1 GB website = ~$0.02/month

CloudFront:
   • Data Transfer Out: ~$0.085 per GB (first 1 TB)
   • HTTP/HTTPS Requests: $0.0075 per 10,000 requests
   • Example: 10 GB transfer + 100K requests = ~$1.60/month

${var.enable_logging ? "S3 Logs Storage: ~$0.023 per GB" : ""}

Total Estimated: $1-5/month for typical small websites

Note: Costs vary based on traffic, content size, and geographic distribution.
AWS Free Tier includes some S3 and CloudFront usage for first 12 months.

EOT
}

# Security Information
output "security_features" {
  description = "Security features enabled in this deployment"
  value = <<-EOT
🔒 Security Features Enabled:

✅ S3 Security:
   • All public access blocked
   • Server-side encryption enabled
   • Versioning enabled for content recovery
   • Secure bucket policy with CloudFront-only access

✅ CloudFront Security:
   • HTTPS redirection enforced
   • Origin Access Control (OAC) implemented
   • Security headers policy applied
   • Modern TLS protocol (${var.minimum_protocol_version}) required
   ${local.create_certificate ? "• Custom SSL certificate from AWS Certificate Manager" : "• CloudFront default SSL certificate"}

✅ DNS Security (if applicable):
   ${local.create_dns_record ? "• DNS managed by Route 53 with alias records" : "• Manual DNS configuration required"}

🛡️ Best Practices Applied:
   • Principle of least privilege access
   • Encryption in transit and at rest
   • No direct S3 bucket access allowed
   • Automated certificate management

EOT
}