# Outputs for S3 Multipart Upload Infrastructure

output "bucket_name" {
  description = "Name of the S3 bucket created for multipart upload demonstrations"
  value       = aws_s3_bucket.multipart_demo.id
}

output "bucket_arn" {
  description = "ARN of the S3 bucket"
  value       = aws_s3_bucket.multipart_demo.arn
}

output "bucket_domain_name" {
  description = "Domain name of the S3 bucket"
  value       = aws_s3_bucket.multipart_demo.bucket_domain_name
}

output "bucket_regional_domain_name" {
  description = "Regional domain name of the S3 bucket"
  value       = aws_s3_bucket.multipart_demo.bucket_regional_domain_name
}

output "bucket_website_endpoint" {
  description = "Website endpoint of the S3 bucket (if configured for static hosting)"
  value       = aws_s3_bucket.multipart_demo.website_endpoint
}

output "transfer_acceleration_status" {
  description = "Transfer acceleration status for the S3 bucket"
  value       = var.enable_transfer_acceleration ? "Enabled" : "Disabled"
}

output "transfer_acceleration_endpoint" {
  description = "Transfer acceleration endpoint (if enabled)"
  value = var.enable_transfer_acceleration ? "${aws_s3_bucket.multipart_demo.id}.s3-accelerate.amazonaws.com" : "Not enabled"
}

output "versioning_status" {
  description = "Versioning status of the S3 bucket"
  value       = var.enable_versioning ? "Enabled" : "Disabled"
}

output "lifecycle_policy_status" {
  description = "Lifecycle policy configuration summary"
  value = {
    incomplete_multipart_cleanup_days = var.lifecycle_incomplete_days
    noncurrent_version_expiration_days = var.enable_versioning ? var.lifecycle_noncurrent_days : "Not applicable (versioning disabled)"
  }
}

output "encryption_status" {
  description = "Server-side encryption status"
  value       = var.enable_server_side_encryption ? "AES256 encryption enabled" : "No server-side encryption"
}

output "cloudwatch_dashboard_name" {
  description = "Name of the CloudWatch dashboard for monitoring"
  value       = var.enable_cloudwatch_metrics ? var.cloudwatch_dashboard_name : "CloudWatch metrics disabled"
}

output "cloudwatch_dashboard_url" {
  description = "URL to access the CloudWatch dashboard"
  value = var.enable_cloudwatch_metrics ? "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${var.cloudwatch_dashboard_name}" : "CloudWatch metrics disabled"
}

output "lambda_function_name" {
  description = "Name of the demo Lambda function (if created)"
  value       = var.create_demo_lambda ? aws_lambda_function.multipart_demo[0].function_name : "Demo Lambda not created"
}

output "lambda_function_arn" {
  description = "ARN of the demo Lambda function (if created)"
  value       = var.create_demo_lambda ? aws_lambda_function.multipart_demo[0].arn : "Demo Lambda not created"
}

# AWS CLI Commands for Testing
output "aws_cli_commands" {
  description = "Useful AWS CLI commands for testing multipart uploads"
  value = {
    configure_cli = "Run the generated aws-cli-config.sh script to optimize CLI settings"
    
    list_incomplete_uploads = "aws s3api list-multipart-uploads --bucket ${aws_s3_bucket.multipart_demo.id}"
    
    upload_large_file = "aws s3 cp large-file.bin s3://${aws_s3_bucket.multipart_demo.id}/ --storage-class STANDARD"
    
    list_objects = "aws s3 ls s3://${aws_s3_bucket.multipart_demo.id}/"
    
    get_bucket_metrics = "aws s3api get-bucket-metrics-configuration --bucket ${aws_s3_bucket.multipart_demo.id} --id entire-bucket-metrics"
    
    check_lifecycle_policy = "aws s3api get-bucket-lifecycle-configuration --bucket ${aws_s3_bucket.multipart_demo.id}"
    
    abort_incomplete_uploads = "aws s3api abort-multipart-upload --bucket ${aws_s3_bucket.multipart_demo.id} --key KEY_NAME --upload-id UPLOAD_ID"
  }
}

# Bucket Configuration Summary
output "bucket_configuration_summary" {
  description = "Summary of S3 bucket configuration"
  value = {
    bucket_name                    = aws_s3_bucket.multipart_demo.id
    region                        = data.aws_region.current.name
    versioning                    = var.enable_versioning ? "Enabled" : "Disabled"
    encryption                    = var.enable_server_side_encryption ? "AES256" : "Disabled"
    transfer_acceleration         = var.enable_transfer_acceleration ? "Enabled" : "Disabled"
    cloudwatch_metrics           = var.enable_cloudwatch_metrics ? "Enabled" : "Disabled"
    lifecycle_incomplete_cleanup = "${var.lifecycle_incomplete_days} days"
    public_access_blocked        = "Yes (all public access blocked)"
    cors_configured              = "Yes (for web uploads)"
  }
}

# Cost Estimation Information
output "estimated_costs" {
  description = "Estimated costs for different usage scenarios (approximate)"
  value = {
    storage_per_gb_month = "$0.023 USD (S3 Standard in us-east-1)"
    put_requests_per_1000 = "$0.0005 USD"
    get_requests_per_1000 = "$0.0004 USD"
    multipart_upload_cost = "Same as regular PUT requests"
    transfer_acceleration_cost = "Additional $0.04-$0.08 per GB (if enabled)"
    cloudwatch_metrics_cost = "$0.30 per metric per month (if detailed metrics enabled)"
    note = "Actual costs may vary by region and usage patterns. Monitor AWS billing dashboard for precise costs."
  }
}

# Security and Best Practices
output "security_features" {
  description = "Security features and best practices implemented"
  value = {
    public_access_blocked = "All public access is blocked by default"
    encryption_at_rest = var.enable_server_side_encryption ? "AES256 server-side encryption enabled" : "Encryption disabled"
    lifecycle_management = "Automatic cleanup of incomplete multipart uploads after ${var.lifecycle_incomplete_days} days"
    iam_least_privilege = var.create_demo_lambda ? "Lambda function has minimal required S3 permissions" : "N/A"
    cors_configuration = "CORS configured for secure web-based uploads"
    versioning = var.enable_versioning ? "Object versioning enabled for data protection" : "Versioning disabled"
  }
}

# Performance Optimization Tips
output "performance_tips" {
  description = "Performance optimization recommendations"
  value = {
    multipart_threshold = "Set to 100MB for optimal performance with large files"
    part_size = "Use 100MB parts for balanced performance and reliability"
    concurrent_uploads = "Configure max 10 concurrent requests to avoid overwhelming connections"
    transfer_acceleration = var.enable_transfer_acceleration ? "Transfer Acceleration enabled for global performance" : "Consider enabling Transfer Acceleration for global users"
    monitoring = var.enable_cloudwatch_metrics ? "CloudWatch metrics enabled for performance monitoring" : "Enable CloudWatch metrics for performance insights"
    regional_considerations = "Choose bucket region closest to your users for best performance"
  }
}

# Quick Start Guide
output "quick_start_guide" {
  description = "Quick start guide for using the multipart upload infrastructure"
  value = {
    step_1 = "Run 'chmod +x aws-cli-config.sh && ./aws-cli-config.sh' to configure AWS CLI"
    step_2 = "Create a large test file: 'dd if=/dev/urandom of=test-file.bin bs=1M count=1024'"
    step_3 = "Upload using multipart: 'aws s3 cp test-file.bin s3://${aws_s3_bucket.multipart_demo.id}/'"
    step_4 = "Monitor progress: 'aws s3api list-multipart-uploads --bucket ${aws_s3_bucket.multipart_demo.id}'"
    step_5 = var.enable_cloudwatch_metrics ? "View metrics in CloudWatch dashboard: ${var.cloudwatch_dashboard_name}" : "Enable CloudWatch metrics for monitoring"
    step_6 = "Clean up: 'aws s3 rm s3://${aws_s3_bucket.multipart_demo.id}/ --recursive'"
  }
}