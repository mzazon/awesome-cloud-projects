# Output values for the content caching strategies infrastructure

# ============================================================================
# CLOUDFRONT DISTRIBUTION OUTPUTS
# ============================================================================

output "cloudfront_distribution_id" {
  description = "ID of the CloudFront distribution"
  value       = aws_cloudfront_distribution.cache_demo.id
}

output "cloudfront_distribution_arn" {
  description = "ARN of the CloudFront distribution"
  value       = aws_cloudfront_distribution.cache_demo.arn
}

output "cloudfront_domain_name" {
  description = "Domain name of the CloudFront distribution"
  value       = aws_cloudfront_distribution.cache_demo.domain_name
}

output "cloudfront_hosted_zone_id" {
  description = "CloudFront Route 53 zone ID"
  value       = aws_cloudfront_distribution.cache_demo.hosted_zone_id
}

output "cloudfront_distribution_url" {
  description = "URL of the CloudFront distribution"
  value       = "https://${aws_cloudfront_distribution.cache_demo.domain_name}"
}

output "cloudfront_status" {
  description = "Current status of the CloudFront distribution"
  value       = aws_cloudfront_distribution.cache_demo.status
}

# ============================================================================
# S3 BUCKET OUTPUTS
# ============================================================================

output "s3_bucket_name" {
  description = "Name of the S3 bucket for static content"
  value       = aws_s3_bucket.static_content.bucket
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket for static content"
  value       = aws_s3_bucket.static_content.arn
}

output "s3_bucket_domain_name" {
  description = "Domain name of the S3 bucket"
  value       = aws_s3_bucket.static_content.bucket_domain_name
}

output "s3_bucket_regional_domain_name" {
  description = "Regional domain name of the S3 bucket"
  value       = aws_s3_bucket.static_content.bucket_regional_domain_name
}

output "cloudfront_logs_bucket_name" {
  description = "Name of the S3 bucket for CloudFront logs"
  value       = aws_s3_bucket.cloudfront_logs.bucket
}

# ============================================================================
# ELASTICACHE OUTPUTS
# ============================================================================

output "elasticache_cluster_id" {
  description = "ID of the ElastiCache Redis cluster"
  value       = aws_elasticache_cluster.redis.cluster_id
}

output "elasticache_cluster_address" {
  description = "Address of the ElastiCache Redis cluster"
  value       = aws_elasticache_cluster.redis.cache_nodes[0].address
  sensitive   = true
}

output "elasticache_cluster_port" {
  description = "Port of the ElastiCache Redis cluster"
  value       = aws_elasticache_cluster.redis.cache_nodes[0].port
}

output "elasticache_subnet_group_name" {
  description = "Name of the ElastiCache subnet group"
  value       = aws_elasticache_subnet_group.cache_subnet_group.name
}

output "elasticache_engine_version" {
  description = "Engine version of the ElastiCache cluster"
  value       = aws_elasticache_cluster.redis.engine_version_actual
}

# ============================================================================
# LAMBDA FUNCTION OUTPUTS
# ============================================================================

output "lambda_function_name" {
  description = "Name of the Lambda function"
  value       = aws_lambda_function.cache_demo.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function"
  value       = aws_lambda_function.cache_demo.arn
}

output "lambda_function_invoke_arn" {
  description = "Invoke ARN of the Lambda function"
  value       = aws_lambda_function.cache_demo.invoke_arn
}

output "lambda_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_role.arn
}

output "lambda_runtime" {
  description = "Runtime version of the Lambda function"
  value       = aws_lambda_function.cache_demo.runtime
}

# ============================================================================
# API GATEWAY OUTPUTS
# ============================================================================

output "api_gateway_id" {
  description = "ID of the API Gateway"
  value       = aws_apigatewayv2_api.cache_demo.id
}

output "api_gateway_arn" {
  description = "ARN of the API Gateway"
  value       = aws_apigatewayv2_api.cache_demo.arn
}

output "api_gateway_endpoint" {
  description = "Endpoint URL of the API Gateway"
  value       = aws_apigatewayv2_api.cache_demo.api_endpoint
}

output "api_gateway_execution_arn" {
  description = "Execution ARN of the API Gateway"
  value       = aws_apigatewayv2_api.cache_demo.execution_arn
}

output "api_data_url" {
  description = "Full URL for the API data endpoint"
  value       = "${aws_apigatewayv2_api.cache_demo.api_endpoint}/prod/api/data"
}

# ============================================================================
# CLOUDWATCH MONITORING OUTPUTS
# ============================================================================

output "cloudwatch_log_group_api_gateway" {
  description = "Name of the CloudWatch log group for API Gateway"
  value       = aws_cloudwatch_log_group.api_gateway.name
}

output "cloudwatch_log_group_lambda" {
  description = "Name of the CloudWatch log group for Lambda"
  value       = aws_cloudwatch_log_group.lambda.name
}

output "cloudwatch_log_group_monitoring" {
  description = "Name of the CloudWatch log group for cache monitoring"
  value       = aws_cloudwatch_log_group.cache_monitoring.name
}

output "cache_hit_ratio_alarm_name" {
  description = "Name of the CloudFront cache hit ratio alarm"
  value       = var.enable_cloudwatch_alarms ? aws_cloudwatch_metric_alarm.cache_hit_ratio[0].alarm_name : "disabled"
}

output "elasticache_cpu_alarm_name" {
  description = "Name of the ElastiCache CPU utilization alarm"
  value       = var.enable_cloudwatch_alarms ? aws_cloudwatch_metric_alarm.elasticache_cpu[0].alarm_name : "disabled"
}

output "lambda_errors_alarm_name" {
  description = "Name of the Lambda errors alarm"
  value       = var.enable_cloudwatch_alarms ? aws_cloudwatch_metric_alarm.lambda_errors[0].alarm_name : "disabled"
}

# ============================================================================
# CLOUDFRONT CACHE POLICY OUTPUTS
# ============================================================================

output "api_cache_policy_id" {
  description = "ID of the custom CloudFront cache policy for API responses"
  value       = aws_cloudfront_cache_policy.api_cache_policy.id
}

output "origin_access_control_id" {
  description = "ID of the CloudFront Origin Access Control"
  value       = aws_cloudfront_origin_access_control.s3_oac.id
}

# ============================================================================
# NETWORK CONFIGURATION OUTPUTS
# ============================================================================

output "vpc_id" {
  description = "ID of the VPC used for ElastiCache and Lambda"
  value       = data.aws_vpc.default.id
}

output "subnet_ids" {
  description = "List of subnet IDs used for ElastiCache and Lambda"
  value       = data.aws_subnets.default.ids
}

output "security_group_id" {
  description = "ID of the default security group used"
  value       = data.aws_security_group.default.id
}

# ============================================================================
# TESTING AND VALIDATION OUTPUTS
# ============================================================================

output "test_commands" {
  description = "Commands to test the caching infrastructure"
  value = {
    "cloudfront_static_content" = "curl -I https://${aws_cloudfront_distribution.cache_demo.domain_name}/"
    "cloudfront_api_endpoint"   = "curl https://${aws_cloudfront_distribution.cache_demo.domain_name}/api/data"
    "api_gateway_direct"        = "curl ${aws_apigatewayv2_api.cache_demo.api_endpoint}/prod/api/data"
    "cache_headers_check"       = "curl -I https://${aws_cloudfront_distribution.cache_demo.domain_name}/api/data"
    "multiple_requests_test"    = "for i in {1..3}; do curl https://${aws_cloudfront_distribution.cache_demo.domain_name}/api/data; echo; done"
  }
}

output "monitoring_urls" {
  description = "URLs for monitoring the caching infrastructure"
  value = {
    "cloudfront_console"   = "https://console.aws.amazon.com/cloudfront/v3/home?region=${data.aws_region.current.name}#/distributions/${aws_cloudfront_distribution.cache_demo.id}"
    "elasticache_console"  = "https://console.aws.amazon.com/elasticache/home?region=${data.aws_region.current.name}#redis-group-nodes:id=${aws_elasticache_cluster.redis.cluster_id}"
    "lambda_console"       = "https://console.aws.amazon.com/lambda/home?region=${data.aws_region.current.name}#/functions/${aws_lambda_function.cache_demo.function_name}"
    "api_gateway_console"  = "https://console.aws.amazon.com/apigateway/main/apis/${aws_apigatewayv2_api.cache_demo.id}/stages/prod?region=${data.aws_region.current.name}"
    "cloudwatch_dashboard" = "https://console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${var.project_name}"
  }
}

# ============================================================================
# DEPLOYMENT SUMMARY
# ============================================================================

output "deployment_summary" {
  description = "Summary of the deployed caching infrastructure"
  value = {
    "project_name"             = var.project_name
    "environment"              = var.environment
    "aws_region"               = data.aws_region.current.name
    "cloudfront_url"           = "https://${aws_cloudfront_distribution.cache_demo.domain_name}"
    "api_endpoint"             = "${aws_apigatewayv2_api.cache_demo.api_endpoint}/prod/api/data"
    "elasticache_cluster"      = aws_elasticache_cluster.redis.cluster_id
    "lambda_function"          = aws_lambda_function.cache_demo.function_name
    "s3_bucket"                = aws_s3_bucket.static_content.bucket
    "cache_policy_configured"  = aws_cloudfront_cache_policy.api_cache_policy.name
    "monitoring_enabled"       = var.enable_cloudwatch_alarms
    "deployment_timestamp"     = timestamp()
  }
}