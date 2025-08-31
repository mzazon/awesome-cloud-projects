# ============================================================================
# TERRAFORM OUTPUTS FOR SIMPLE IMAGE METADATA EXTRACTOR
# ============================================================================
# This file defines outputs that provide information about created resources,
# including resource identifiers, URLs, and usage examples for the deployed
# infrastructure.
# ============================================================================

# ============================================================================
# S3 BUCKET OUTPUTS
# ============================================================================

output "s3_bucket_name" {
  description = "Name of the S3 bucket for image uploads"
  value       = aws_s3_bucket.image_bucket.bucket
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket"
  value       = aws_s3_bucket.image_bucket.arn
}

output "s3_bucket_domain_name" {
  description = "Domain name of the S3 bucket"
  value       = aws_s3_bucket.image_bucket.bucket_domain_name
}

output "s3_bucket_regional_domain_name" {
  description = "Regional domain name of the S3 bucket"
  value       = aws_s3_bucket.image_bucket.bucket_regional_domain_name
}

output "s3_bucket_region" {
  description = "AWS region where the S3 bucket is located"
  value       = aws_s3_bucket.image_bucket.region
}

# ============================================================================
# LAMBDA FUNCTION OUTPUTS
# ============================================================================

output "lambda_function_name" {
  description = "Name of the Lambda function for metadata extraction"
  value       = aws_lambda_function.metadata_extractor.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function"
  value       = aws_lambda_function.metadata_extractor.arn
}

output "lambda_function_invoke_arn" {
  description = "Invoke ARN of the Lambda function"
  value       = aws_lambda_function.metadata_extractor.invoke_arn
}

output "lambda_function_qualified_arn" {
  description = "Qualified ARN of the Lambda function (includes version)"
  value       = aws_lambda_function.metadata_extractor.qualified_arn
}

output "lambda_function_version" {
  description = "Version of the Lambda function"
  value       = aws_lambda_function.metadata_extractor.version
}

output "lambda_function_last_modified" {
  description = "Date when the Lambda function was last modified"
  value       = aws_lambda_function.metadata_extractor.last_modified
}

output "lambda_function_source_code_hash" {
  description = "Base64-encoded SHA256 hash of the deployment package"
  value       = aws_lambda_function.metadata_extractor.source_code_hash
}

output "lambda_function_source_code_size" {
  description = "Size of the Lambda function deployment package in bytes"
  value       = aws_lambda_function.metadata_extractor.source_code_size
}

# ============================================================================
# LAMBDA LAYER OUTPUTS
# ============================================================================

output "lambda_layer_arn" {
  description = "ARN of the Pillow Lambda layer"
  value       = aws_lambda_layer_version.pillow_layer.arn
}

output "lambda_layer_version" {
  description = "Version of the Pillow Lambda layer"
  value       = aws_lambda_layer_version.pillow_layer.version
}

output "lambda_layer_source_code_hash" {
  description = "Base64-encoded SHA256 hash of the layer package"
  value       = aws_lambda_layer_version.pillow_layer.source_code_hash
}

output "lambda_layer_source_code_size" {
  description = "Size of the layer package in bytes"
  value       = aws_lambda_layer_version.pillow_layer.source_code_size
}

output "lambda_layer_compatible_runtimes" {
  description = "Compatible runtimes for the Lambda layer"
  value       = aws_lambda_layer_version.pillow_layer.compatible_runtimes
}

output "lambda_layer_compatible_architectures" {
  description = "Compatible architectures for the Lambda layer"
  value       = aws_lambda_layer_version.pillow_layer.compatible_architectures
}

# ============================================================================
# IAM ROLE AND POLICY OUTPUTS
# ============================================================================

output "iam_role_name" { 
  description = "Name of the IAM role for Lambda execution"
  value       = aws_iam_role.lambda_execution_role.name
}

output "iam_role_arn" {
  description = "ARN of the IAM role for Lambda execution"
  value       = aws_iam_role.lambda_execution_role.arn
}

output "iam_role_unique_id" {
  description = "Unique ID of the IAM role"
  value       = aws_iam_role.lambda_execution_role.unique_id
}

output "s3_policy_arn" {
  description = "ARN of the S3 access policy"
  value       = aws_iam_policy.lambda_s3_policy.arn
}

output "kms_policy_arn" {
  description = "ARN of the KMS access policy (if KMS encryption is enabled)"
  value       = var.enable_kms_encryption ? aws_iam_policy.lambda_kms_policy[0].arn : null
}

output "xray_policy_arn" {
  description = "ARN of the X-Ray tracing policy (if X-Ray tracing is enabled)"
  value       = var.enable_xray_tracing ? aws_iam_policy.lambda_xray_policy[0].arn : null
}

# ============================================================================
# CLOUDWATCH LOGS OUTPUTS
# ============================================================================

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for Lambda function"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.lambda_logs.arn
}

output "cloudwatch_log_group_retention_in_days" {
  description = "Log retention period for the CloudWatch log group"
  value       = aws_cloudwatch_log_group.lambda_logs.retention_in_days
}

# ============================================================================
# KMS ENCRYPTION OUTPUTS
# ============================================================================

output "s3_kms_key_id" {
  description = "ID of the KMS key used for S3 encryption (if enabled)"
  value       = var.enable_kms_encryption ? aws_kms_key.s3_key[0].key_id : null
}

output "s3_kms_key_arn" {
  description = "ARN of the KMS key used for S3 encryption (if enabled)"
  value       = var.enable_kms_encryption ? aws_kms_key.s3_key[0].arn : null
}

output "s3_kms_key_alias" {
  description = "Alias of the KMS key used for S3 encryption (if enabled)"
  value       = var.enable_kms_encryption ? aws_kms_alias.s3_key[0].name : null
}

output "cloudwatch_kms_key_id" {
  description = "ID of the KMS key used for CloudWatch logs encryption (if enabled)"
  value       = var.enable_kms_encryption ? aws_kms_key.cloudwatch_key[0].key_id : null
}

output "cloudwatch_kms_key_arn" {
  description = "ARN of the KMS key used for CloudWatch logs encryption (if enabled)"
  value       = var.enable_kms_encryption ? aws_kms_key.cloudwatch_key[0].arn : null
}

output "cloudwatch_kms_key_alias" {
  description = "Alias of the KMS key used for CloudWatch logs encryption (if enabled)"
  value       = var.enable_kms_encryption ? aws_kms_alias.cloudwatch_key[0].name : null
}

# ============================================================================
# DEAD LETTER QUEUE OUTPUTS (CONDITIONAL)
# ============================================================================

output "dlq_queue_name" {
  description = "Name of the Dead Letter Queue (if enabled)"
  value       = var.enable_dlq ? aws_sqs_queue.dlq[0].name : null
}

output "dlq_queue_arn" {
  description = "ARN of the Dead Letter Queue (if enabled)"
  value       = var.enable_dlq ? aws_sqs_queue.dlq[0].arn : null
}

output "dlq_queue_url" {
  description = "URL of the Dead Letter Queue (if enabled)"
  value       = var.enable_dlq ? aws_sqs_queue.dlq[0].url : null
}

# ============================================================================
# MONITORING OUTPUTS (CONDITIONAL)
# ============================================================================

output "lambda_errors_alarm_name" {
  description = "Name of the Lambda errors CloudWatch alarm (if monitoring is enabled)"
  value       = var.enable_monitoring ? aws_cloudwatch_metric_alarm.lambda_errors[0].alarm_name : null
}

output "lambda_duration_alarm_name" {
  description = "Name of the Lambda duration CloudWatch alarm (if monitoring is enabled)"
  value       = var.enable_monitoring ? aws_cloudwatch_metric_alarm.lambda_duration[0].alarm_name : null
}

# ============================================================================
# CONFIGURATION OUTPUTS
# ============================================================================

output "supported_image_formats" {
  description = "List of supported image formats configured for processing"
  value       = var.supported_image_formats
}

output "lambda_timeout" {
  description = "Timeout configured for the Lambda function (seconds)"
  value       = aws_lambda_function.metadata_extractor.timeout
}

output "lambda_memory_size" {
  description = "Memory size configured for the Lambda function (MB)"
  value       = aws_lambda_function.metadata_extractor.memory_size
}

output "lambda_runtime" {
  description = "Runtime configured for the Lambda function"
  value       = aws_lambda_function.metadata_extractor.runtime
}

output "lambda_architecture" {
  description = "Architecture configured for the Lambda function"
  value       = aws_lambda_function.metadata_extractor.architectures[0]
}

output "lambda_environment_variables" {
  description = "Environment variables configured for the Lambda function"
  value       = aws_lambda_function.metadata_extractor.environment[0].variables
  sensitive   = true
}

# ============================================================================
# INFRASTRUCTURE DETAILS
# ============================================================================

output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "aws_account_id" {
  description = "AWS account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

output "random_suffix" {
  description = "Random suffix used for resource names (if enabled)"
  value       = var.use_random_suffix ? random_string.suffix[0].result : null
}

output "project_name" {
  description = "Project name used for resource naming and tagging"
  value       = var.project_name
}

output "environment" {
  description = "Environment name for the deployment"
  value       = var.environment
}

# ============================================================================
# FEATURE FLAGS STATUS
# ============================================================================

output "kms_encryption_enabled" {
  description = "Whether KMS encryption is enabled for resources"
  value       = var.enable_kms_encryption
}

output "xray_tracing_enabled" {
  description = "Whether X-Ray tracing is enabled for Lambda function"
  value       = var.enable_xray_tracing
}

output "s3_versioning_enabled" {
  description = "Whether S3 bucket versioning is enabled"
  value       = var.s3_versioning_enabled
}

output "monitoring_enabled" {
  description = "Whether CloudWatch monitoring alarms are enabled"
  value       = var.enable_monitoring
}

output "dlq_enabled" {
  description = "Whether Dead Letter Queue is enabled"
  value       = var.enable_dlq
}

output "lifecycle_policy_enabled" {
  description = "Whether S3 lifecycle policy is enabled"
  value       = var.enable_lifecycle_policy
}

# ============================================================================
# USAGE EXAMPLES AND COMMANDS
# ============================================================================

output "upload_command_example" {
  description = "Example AWS CLI command to upload an image to trigger processing"
  value       = "aws s3 cp your-image.jpg s3://${aws_s3_bucket.image_bucket.bucket}/your-image.jpg"
}

output "upload_command_curl_example" {
  description = "Example curl command to upload via S3 presigned URL (requires SDK integration)"
  value       = "# Use AWS SDK to generate presigned URL, then: curl -X PUT -T your-image.jpg '<presigned-url>'"
}

output "logs_command" {
  description = "AWS CLI command to view Lambda function logs"
  value       = "aws logs tail ${aws_cloudwatch_log_group.lambda_logs.name} --follow"
}

output "logs_insights_query_example" {
  description = "CloudWatch Logs Insights query to analyze metadata extraction results"
  value       = "fields @timestamp, @message | filter @message like /metadata/ | sort @timestamp desc | limit 20"
}

output "test_function_command" {
  description = "AWS CLI command to test the Lambda function directly"  
  value       = "aws lambda invoke --function-name ${aws_lambda_function.metadata_extractor.function_name} --payload '{\"Records\":[{\"s3\":{\"bucket\":{\"name\":\"${aws_s3_bucket.image_bucket.bucket}\"},\"object\":{\"key\":\"test-image.jpg\"}}}]}' response.json"
}

output "function_metrics_command" {
  description = "AWS CLI command to get Lambda function metrics"
  value       = "aws cloudwatch get-metric-statistics --namespace AWS/Lambda --metric-name Duration --dimensions Name=FunctionName,Value=${aws_lambda_function.metadata_extractor.function_name} --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) --end-time $(date -u +%Y-%m-%dT%H:%M:%S) --period 300 --statistics Average,Maximum"
}

# ============================================================================
# COST AND PERFORMANCE INFORMATION
# ============================================================================

output "lambda_architecture_cost_info" {
  description = "Information about Lambda architecture choice for cost optimization"
  value       = var.lambda_architecture == "arm64" ? "Using ARM64 (Graviton2) for up to 20% better price-performance" : "Using x86_64 architecture"
}

output "estimated_monthly_cost_info" {
  description = "Estimated monthly cost information for AWS Free Tier eligible resources"
  value       = "Lambda: 1M free requests/month, S3: 5GB free storage, CloudWatch: 5GB free log ingestion. Estimated cost: $0.01-$0.05/month for light usage (Free Tier eligible)"
}

output "performance_optimization_tips" {
  description = "Performance optimization recommendations"
  value = {
    memory_optimization = "Monitor CloudWatch metrics to optimize Lambda memory allocation"
    cold_start_reduction = "Consider provisioned concurrency for consistent performance"
    layer_optimization = "Keep Lambda layers under 50MB for faster cold starts"
    timeout_optimization = "Set timeout based on 95th percentile duration + buffer"
  }
}

# ============================================================================
# SECURITY AND COMPLIANCE INFORMATION
# ============================================================================

output "security_features_summary" {
  description = "Summary of implemented security features"
  value = {
    encryption_at_rest = var.enable_kms_encryption ? "Enabled with KMS" : "AES256 encryption"
    encryption_in_transit = "TLS 1.2+ for all API calls"
    iam_least_privilege = "Enabled - Function has minimal required permissions"
    s3_public_access_blocked = "Enabled - All public access blocked"
    vpc_isolation = length(var.lambda_subnet_ids) > 0 ? "Enabled - Function runs in VPC" : "Disabled - Function runs in AWS managed network"
    xray_tracing = var.enable_xray_tracing ? "Enabled" : "Disabled"
  }
}

output "compliance_information" {
  description = "Compliance and governance information"
  value = {
    data_classification = var.data_classification
    logging_retention = "${var.log_retention_days} days"
    versioning_enabled = var.s3_versioning_enabled
    ssl_enforcement = var.enforce_ssl_requests_only
    cloudtrail_logging = var.enable_cloudtrail_logging ? "Enabled" : "Disabled"
  }
}

# ============================================================================
# TROUBLESHOOTING INFORMATION
# ============================================================================

output "troubleshooting_commands" {
  description = "Useful commands for troubleshooting issues"
  value = {
    check_s3_permissions = "aws s3api head-object --bucket ${aws_s3_bucket.image_bucket.bucket} --key test-image.jpg"
    check_lambda_permissions = "aws lambda get-policy --function-name ${aws_lambda_function.metadata_extractor.function_name}"
    check_s3_notifications = "aws s3api get-bucket-notification-configuration --bucket ${aws_s3_bucket.image_bucket.bucket}"
    check_lambda_configuration = "aws lambda get-function-configuration --function-name ${aws_lambda_function.metadata_extractor.function_name}"
    check_recent_executions = "aws logs filter-log-events --log-group-name ${aws_cloudwatch_log_group.lambda_logs.name} --start-time $(date -d '1 hour ago' +%s)000"
  }
}

# ============================================================================
# RESOURCE TAGS SUMMARY
# ============================================================================

output "resource_tags" {
  description = "Common tags applied to all resources"
  value = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Recipe      = "simple-image-metadata-extractor"
      CreatedBy   = "terraform-recipe"
    },
    var.tags
  )
}

# ============================================================================
# NEXT STEPS AND RECOMMENDATIONS
# ============================================================================

output "next_steps" {
  description = "Recommended next steps after deployment"
  value = [
    "1. Upload test images to S3 bucket: ${aws_s3_bucket.image_bucket.bucket}",
    "2. Check CloudWatch logs for processing results: ${aws_cloudwatch_log_group.lambda_logs.name}",
    "3. Monitor Lambda metrics in CloudWatch for performance optimization",
    "4. Consider enabling monitoring alarms for production use (set enable_monitoring = true)",
    "5. Configure SNS notifications for alerts (set sns_alarm_topic_arn)",
    "6. Review security settings and enable additional features as needed",
    "7. Set up automated testing with sample images",
    "8. Configure cost monitoring and budgets for usage tracking"
  ]
}