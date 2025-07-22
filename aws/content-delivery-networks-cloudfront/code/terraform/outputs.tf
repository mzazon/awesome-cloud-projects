# CloudFront Distribution Outputs
output "cloudfront_distribution_id" {
  description = "The identifier for the CloudFront distribution"
  value       = aws_cloudfront_distribution.main.id
}

output "cloudfront_distribution_arn" {
  description = "The ARN (Amazon Resource Name) for the CloudFront distribution"
  value       = aws_cloudfront_distribution.main.arn
}

output "cloudfront_distribution_domain_name" {
  description = "The domain name corresponding to the CloudFront distribution"
  value       = aws_cloudfront_distribution.main.domain_name
}

output "cloudfront_distribution_hosted_zone_id" {
  description = "The CloudFront Route 53 zone ID"
  value       = aws_cloudfront_distribution.main.hosted_zone_id
}

output "cloudfront_distribution_status" {
  description = "The current status of the CloudFront distribution"
  value       = aws_cloudfront_distribution.main.status
}

output "cloudfront_distribution_url" {
  description = "The HTTPS URL for the CloudFront distribution"
  value       = "https://${aws_cloudfront_distribution.main.domain_name}"
}

# S3 Bucket Outputs
output "s3_bucket_name" {
  description = "The name of the S3 bucket"
  value       = aws_s3_bucket.content.id
}

output "s3_bucket_arn" {
  description = "The ARN of the S3 bucket"
  value       = aws_s3_bucket.content.arn
}

output "s3_bucket_domain_name" {
  description = "The bucket domain name"
  value       = aws_s3_bucket.content.bucket_domain_name
}

output "s3_bucket_regional_domain_name" {
  description = "The bucket regional domain name"
  value       = aws_s3_bucket.content.bucket_regional_domain_name
}

# Origin Access Control Outputs
output "origin_access_control_id" {
  description = "The unique identifier of the Origin Access Control"
  value       = aws_cloudfront_origin_access_control.s3_oac.id
}

output "origin_access_control_etag" {
  description = "The current version of the Origin Access Control"
  value       = aws_cloudfront_origin_access_control.s3_oac.etag
}

# WAF Outputs
output "waf_web_acl_id" {
  description = "The ID of the WAF WebACL"
  value       = var.enable_waf ? aws_wafv2_web_acl.cloudfront[0].id : null
}

output "waf_web_acl_arn" {
  description = "The ARN of the WAF WebACL"
  value       = var.enable_waf ? aws_wafv2_web_acl.cloudfront[0].arn : null
}

output "waf_web_acl_name" {
  description = "The name of the WAF WebACL"
  value       = var.enable_waf ? aws_wafv2_web_acl.cloudfront[0].name : null
}

# Lambda@Edge Outputs
output "lambda_edge_function_name" {
  description = "The name of the Lambda@Edge function"
  value       = var.enable_lambda_edge ? aws_lambda_function.edge_processor[0].function_name : null
}

output "lambda_edge_function_arn" {
  description = "The ARN of the Lambda@Edge function"
  value       = var.enable_lambda_edge ? aws_lambda_function.edge_processor[0].arn : null
}

output "lambda_edge_qualified_arn" {
  description = "The qualified ARN of the Lambda@Edge function (with version)"
  value       = var.enable_lambda_edge ? aws_lambda_function.edge_processor[0].qualified_arn : null
}

output "lambda_edge_version" {
  description = "The version of the Lambda@Edge function"
  value       = var.enable_lambda_edge ? aws_lambda_function.edge_processor[0].version : null
}

output "lambda_edge_role_arn" {
  description = "The ARN of the IAM role for Lambda@Edge"
  value       = var.enable_lambda_edge ? aws_iam_role.lambda_edge[0].arn : null
}

# CloudFront Function Outputs
output "cloudfront_function_name" {
  description = "The name of the CloudFront function"
  value       = var.enable_cloudfront_functions ? aws_cloudfront_function.request_processor[0].name : null
}

output "cloudfront_function_arn" {
  description = "The ARN of the CloudFront function"
  value       = var.enable_cloudfront_functions ? aws_cloudfront_function.request_processor[0].arn : null
}

output "cloudfront_function_etag" {
  description = "The ETag of the CloudFront function"
  value       = var.enable_cloudfront_functions ? aws_cloudfront_function.request_processor[0].etag : null
}

# KeyValueStore Outputs
output "key_value_store_name" {
  description = "The name of the CloudFront KeyValueStore"
  value       = var.enable_key_value_store ? aws_cloudfront_key_value_store.config[0].name : null
}

output "key_value_store_id" {
  description = "The ID of the CloudFront KeyValueStore"
  value       = var.enable_key_value_store ? aws_cloudfront_key_value_store.config[0].id : null
}

output "key_value_store_arn" {
  description = "The ARN of the CloudFront KeyValueStore"
  value       = var.enable_key_value_store ? aws_cloudfront_key_value_store.config[0].arn : null
}

# Kinesis Stream Outputs
output "kinesis_stream_name" {
  description = "The name of the Kinesis stream for real-time logs"
  value       = var.enable_real_time_logs ? aws_kinesis_stream.realtime_logs[0].name : null
}

output "kinesis_stream_arn" {
  description = "The ARN of the Kinesis stream for real-time logs"
  value       = var.enable_real_time_logs ? aws_kinesis_stream.realtime_logs[0].arn : null
}

output "kinesis_stream_shard_count" {
  description = "The number of shards in the Kinesis stream"
  value       = var.enable_real_time_logs ? aws_kinesis_stream.realtime_logs[0].shard_count : null
}

# Real-time Log Configuration Outputs
output "realtime_log_config_name" {
  description = "The name of the real-time log configuration"
  value       = var.enable_real_time_logs ? aws_cloudfront_realtime_log_config.main[0].name : null
}

output "realtime_log_config_arn" {
  description = "The ARN of the real-time log configuration"
  value       = var.enable_real_time_logs ? aws_cloudfront_realtime_log_config.main[0].arn : null
}

# CloudWatch Outputs
output "cloudwatch_log_group_name" {
  description = "The name of the CloudWatch log group for real-time logs"
  value       = var.enable_real_time_logs ? aws_cloudwatch_log_group.realtime_logs[0].name : null
}

output "cloudwatch_log_group_arn" {
  description = "The ARN of the CloudWatch log group for real-time logs"
  value       = var.enable_real_time_logs ? aws_cloudwatch_log_group.realtime_logs[0].arn : null
}

output "cloudwatch_dashboard_name" {
  description = "The name of the CloudWatch dashboard"
  value       = var.enable_cloudwatch_dashboard ? aws_cloudwatch_dashboard.main[0].dashboard_name : null
}

output "cloudwatch_dashboard_url" {
  description = "The URL to access the CloudWatch dashboard"
  value       = var.enable_cloudwatch_dashboard ? "https://console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.main[0].dashboard_name}" : null
}

# Infrastructure Information
output "aws_region" {
  description = "The AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "aws_account_id" {
  description = "The AWS account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

output "project_name" {
  description = "The project name used for resource naming"
  value       = var.project_name
}

output "environment" {
  description = "The environment name"
  value       = var.environment
}

output "random_suffix" {
  description = "The random suffix used for unique resource names"
  value       = local.suffix
}

# Cache Policy Information
output "cache_policy_optimized_id" {
  description = "The ID of the managed caching optimized policy"
  value       = data.aws_cloudfront_cache_policy.caching_optimized.id
}

output "cache_policy_disabled_id" {
  description = "The ID of the managed caching disabled policy"
  value       = data.aws_cloudfront_cache_policy.caching_disabled.id
}

output "origin_request_policy_cors_s3_id" {
  description = "The ID of the managed CORS S3 origin request policy"
  value       = data.aws_cloudfront_origin_request_policy.cors_s3_origin.id
}

output "origin_request_policy_all_viewer_id" {
  description = "The ID of the managed all viewer origin request policy"
  value       = data.aws_cloudfront_origin_request_policy.all_viewer.id
}

# Testing URLs
output "test_urls" {
  description = "URLs for testing the CloudFront distribution"
  value = {
    main_site        = "https://${aws_cloudfront_distribution.main.domain_name}/"
    api_endpoint     = "https://${aws_cloudfront_distribution.main.domain_name}/api/"
    static_content   = "https://${aws_cloudfront_distribution.main.domain_name}/static/"
    status_endpoint  = "https://${aws_cloudfront_distribution.main.domain_name}/api/status.json"
  }
}

# Resource Count Summary
output "resource_summary" {
  description = "Summary of created resources"
  value = {
    cloudfront_distribution = 1
    s3_bucket              = 1
    waf_web_acl            = var.enable_waf ? 1 : 0
    lambda_edge_function   = var.enable_lambda_edge ? 1 : 0
    cloudfront_function    = var.enable_cloudfront_functions ? 1 : 0
    kinesis_stream         = var.enable_real_time_logs ? 1 : 0
    key_value_store        = var.enable_key_value_store ? 1 : 0
    cloudwatch_dashboard   = var.enable_cloudwatch_dashboard ? 1 : 0
  }
}