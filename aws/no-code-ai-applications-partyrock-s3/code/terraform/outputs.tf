# Output values for PartyRock AI Applications with S3 and CloudFront infrastructure
# These outputs provide important information about the deployed resources

# S3 Bucket Information
output "s3_bucket_name" {
  description = "Name of the S3 bucket hosting the static website"
  value       = aws_s3_bucket.website.bucket
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket hosting the static website"
  value       = aws_s3_bucket.website.arn
}

output "s3_bucket_domain_name" {
  description = "Regional domain name of the S3 bucket"
  value       = aws_s3_bucket.website.bucket_regional_domain_name
}

output "s3_website_endpoint" {
  description = "S3 website endpoint for direct access to the static website"
  value       = aws_s3_bucket_website_configuration.website.website_endpoint
}

output "s3_website_domain" {
  description = "S3 website domain for direct access to the static website"
  value       = aws_s3_bucket_website_configuration.website.website_domain
}

output "s3_website_url" {
  description = "Complete URL for accessing the S3 static website directly"
  value       = "http://${aws_s3_bucket_website_configuration.website.website_endpoint}"
}

# CloudFront Distribution Information
output "cloudfront_distribution_id" {
  description = "ID of the CloudFront distribution"
  value       = var.enable_cloudfront ? aws_cloudfront_distribution.website[0].id : null
}

output "cloudfront_distribution_arn" {
  description = "ARN of the CloudFront distribution"
  value       = var.enable_cloudfront ? aws_cloudfront_distribution.website[0].arn : null
}

output "cloudfront_domain_name" {
  description = "Domain name of the CloudFront distribution"
  value       = var.enable_cloudfront ? aws_cloudfront_distribution.website[0].domain_name : null
}

output "cloudfront_url" {
  description = "Complete HTTPS URL for accessing the website via CloudFront CDN"
  value       = var.enable_cloudfront ? "https://${aws_cloudfront_distribution.website[0].domain_name}" : null
}

output "cloudfront_hosted_zone_id" {
  description = "CloudFront distribution hosted zone ID (useful for Route 53 alias records)"
  value       = var.enable_cloudfront ? aws_cloudfront_distribution.website[0].hosted_zone_id : null
}

output "cloudfront_status" {
  description = "Current status of the CloudFront distribution"
  value       = var.enable_cloudfront ? aws_cloudfront_distribution.website[0].status : null
}

# Website Access Information
output "website_url" {
  description = "Primary URL for accessing the website (CloudFront if enabled, otherwise S3)"
  value = var.enable_cloudfront ? (
    "https://${aws_cloudfront_distribution.website[0].domain_name}"
  ) : (
    "http://${aws_s3_bucket_website_configuration.website.website_endpoint}"
  )
}

output "backup_website_url" {
  description = "Alternative URL for accessing the website (useful for testing)"
  value = var.enable_cloudfront ? (
    "http://${aws_s3_bucket_website_configuration.website.website_endpoint}"
  ) : null
}

# Configuration Information
output "partyrock_app_placeholder" {
  description = "Current PartyRock application URL configured in the website"
  value       = var.partyrock_app_url
}

output "partyrock_setup_instructions" {
  description = "Instructions for setting up and linking your PartyRock application"
  value = <<-EOT
    1. Visit https://partyrock.aws/ to create your PartyRock AI application
    2. Sign in with your Apple, Amazon, or Google account
    3. Create a business name generator app or your custom AI application
    4. Make your application public and copy the public URL
    5. Update the 'partyrock_app_url' variable with your actual PartyRock URL
    6. Run 'terraform apply' to update the website with your PartyRock app link
  EOT
}

# Resource Information
output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "aws_account_id" {
  description = "AWS account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_id.bucket_suffix.hex
}

# Security and Access Information
output "bucket_versioning_enabled" {
  description = "Whether S3 bucket versioning is enabled"
  value       = var.enable_versioning
}

output "bucket_encryption_enabled" {
  description = "Whether S3 bucket encryption is enabled"
  value       = var.enable_encryption
}

output "public_access_enabled" {
  description = "Whether public access to the S3 bucket is enabled"
  value       = var.enable_public_access
}

# CloudFront Configuration Details
output "cloudfront_price_class" {
  description = "CloudFront price class determining global distribution coverage"
  value       = var.enable_cloudfront ? var.cloudfront_price_class : null
}

output "compression_enabled" {
  description = "Whether CloudFront compression is enabled"
  value       = var.enable_cloudfront ? var.enable_compression : null
}

# DNS and Domain Information
output "route53_alias_configuration" {
  description = "Configuration for creating Route 53 alias records (if using custom domain)"
  value = var.enable_cloudfront ? {
    name                   = aws_cloudfront_distribution.website[0].domain_name
    zone_id               = aws_cloudfront_distribution.website[0].hosted_zone_id
    evaluate_target_health = false
  } : null
}

# Cost Estimation Information
output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown for AWS resources"
  value = {
    s3_storage = "~$0.023 per GB stored"
    s3_requests = "~$0.0004 per 1,000 GET requests"
    cloudfront_requests = var.enable_cloudfront ? "~$0.0075 per 10,000 requests" : "Not applicable"
    cloudfront_data_transfer = var.enable_cloudfront ? "~$0.085 per GB (varies by region)" : "Not applicable"
    total_estimated = var.enable_cloudfront ? "$0.50-$2.00 per month for typical usage" : "$0.10-$0.50 per month for S3 only"
  }
}

# Deployment Information
output "deployment_timestamp" {
  description = "Timestamp when the infrastructure was deployed"
  value       = timestamp()
}

output "terraform_workspace" {
  description = "Terraform workspace used for this deployment"
  value       = terraform.workspace
}

# Next Steps and Documentation
output "next_steps" {
  description = "Next steps after deployment"
  value = <<-EOT
    
    🎉 Your PartyRock AI application infrastructure is ready!
    
    📋 Next Steps:
    1. Access your website at: ${var.enable_cloudfront ? "https://${aws_cloudfront_distribution.website[0].domain_name}" : "http://${aws_s3_bucket_website_configuration.website.website_endpoint}"}
    2. Create your PartyRock AI application at: https://partyrock.aws/
    3. Update the partyrock_app_url variable with your actual app URL
    4. Customize the website content by uploading new files to the S3 bucket
    
    🔧 Management Commands:
    - View bucket contents: aws s3 ls s3://${aws_s3_bucket.website.bucket}
    - Upload files: aws s3 cp local-file.html s3://${aws_s3_bucket.website.bucket}/
    - Sync directory: aws s3 sync ./local-dir s3://${aws_s3_bucket.website.bucket}/
    ${var.enable_cloudfront ? "- Invalidate CloudFront cache: aws cloudfront create-invalidation --distribution-id ${aws_cloudfront_distribution.website[0].id} --paths \"/*\"" : ""}
    
    📚 Documentation:
    - PartyRock Guide: https://docs.aws.amazon.com/bedrock/latest/userguide/partyrock.html
    - S3 Website Hosting: https://docs.aws.amazon.com/AmazonS3/latest/userguide/WebsiteHosting.html
    ${var.enable_cloudfront ? "- CloudFront Guide: https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/" : ""}
    
  EOT
}