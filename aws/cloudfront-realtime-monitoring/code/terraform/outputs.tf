# CloudFront Real-time Monitoring and Analytics - Terraform Outputs
# This file defines all output values for important resource information

#------------------------------------------------------------------------------
# GENERAL INFORMATION
#------------------------------------------------------------------------------

output "project_name" {
  description = "The project name used for resource naming"
  value       = var.project_name
}

output "environment" {
  description = "The environment name"
  value       = var.environment
}

output "aws_region" {
  description = "The AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "resource_name_prefix" {
  description = "The prefix used for all resource names"
  value       = local.name_prefix
}

#------------------------------------------------------------------------------
# S3 BUCKET INFORMATION
#------------------------------------------------------------------------------

output "content_bucket_name" {
  description = "Name of the S3 bucket containing CloudFront content"
  value       = aws_s3_bucket.content.id
}

output "content_bucket_arn" {
  description = "ARN of the S3 bucket containing CloudFront content"
  value       = aws_s3_bucket.content.arn
}

output "content_bucket_domain" {
  description = "Regional domain name of the content S3 bucket"
  value       = aws_s3_bucket.content.bucket_regional_domain_name
}

output "logs_bucket_name" {
  description = "Name of the S3 bucket for storing processed logs"
  value       = aws_s3_bucket.logs.id
}

output "logs_bucket_arn" {
  description = "ARN of the S3 bucket for storing processed logs"
  value       = aws_s3_bucket.logs.arn
}

#------------------------------------------------------------------------------
# KINESIS STREAMS INFORMATION
#------------------------------------------------------------------------------

output "kinesis_stream_name" {
  description = "Name of the primary Kinesis stream for real-time logs"
  value       = aws_kinesis_stream.cloudfront_logs.name
}

output "kinesis_stream_arn" {
  description = "ARN of the primary Kinesis stream for real-time logs"
  value       = aws_kinesis_stream.cloudfront_logs.arn
}

output "processed_kinesis_stream_name" {
  description = "Name of the processed Kinesis stream"
  value       = aws_kinesis_stream.processed_logs.name
}

output "processed_kinesis_stream_arn" {
  description = "ARN of the processed Kinesis stream"
  value       = aws_kinesis_stream.processed_logs.arn
}

#------------------------------------------------------------------------------
# OPENSEARCH INFORMATION
#------------------------------------------------------------------------------

output "opensearch_domain_name" {
  description = "Name of the OpenSearch domain"
  value       = aws_opensearch_domain.analytics.domain_name
}

output "opensearch_domain_arn" {
  description = "ARN of the OpenSearch domain"
  value       = aws_opensearch_domain.analytics.arn
}

output "opensearch_endpoint" {
  description = "Endpoint URL of the OpenSearch domain"
  value       = "https://${aws_opensearch_domain.analytics.endpoint}"
}

output "opensearch_dashboard_url" {
  description = "URL for OpenSearch Dashboards (Kibana)"
  value       = "https://${aws_opensearch_domain.analytics.endpoint}/_dashboards/"
}

output "opensearch_domain_id" {
  description = "Unique identifier for the OpenSearch domain"
  value       = aws_opensearch_domain.analytics.domain_id
}

#------------------------------------------------------------------------------
# LAMBDA FUNCTION INFORMATION
#------------------------------------------------------------------------------

output "lambda_function_name" {
  description = "Name of the Lambda function for log processing"
  value       = aws_lambda_function.log_processor.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function for log processing"
  value       = aws_lambda_function.log_processor.arn
}

output "lambda_log_group_name" {
  description = "CloudWatch log group name for the Lambda function"
  value       = aws_cloudwatch_log_group.lambda.name
}

#------------------------------------------------------------------------------
# DYNAMODB INFORMATION
#------------------------------------------------------------------------------

output "dynamodb_table_name" {
  description = "Name of the DynamoDB table for metrics storage"
  value       = aws_dynamodb_table.metrics.name
}

output "dynamodb_table_arn" {
  description = "ARN of the DynamoDB table for metrics storage"
  value       = aws_dynamodb_table.metrics.arn
}

#------------------------------------------------------------------------------
# CLOUDFRONT INFORMATION
#------------------------------------------------------------------------------

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

output "cloudfront_distribution_url" {
  description = "HTTPS URL of the CloudFront distribution"
  value       = "https://${aws_cloudfront_distribution.main.domain_name}"
}

output "cloudfront_origin_access_control_id" {
  description = "ID of the CloudFront Origin Access Control"
  value       = aws_cloudfront_origin_access_control.content.id
}

output "cloudfront_realtime_log_config_arn" {
  description = "ARN of the CloudFront real-time log configuration"
  value       = var.enable_real_time_logs ? aws_cloudfront_realtime_log_config.main[0].arn : null
}

#------------------------------------------------------------------------------
# KINESIS FIREHOSE INFORMATION
#------------------------------------------------------------------------------

output "firehose_delivery_stream_name" {
  description = "Name of the Kinesis Data Firehose delivery stream"
  value       = aws_kinesis_firehose_delivery_stream.logs_to_s3_opensearch.name
}

output "firehose_delivery_stream_arn" {
  description = "ARN of the Kinesis Data Firehose delivery stream"
  value       = aws_kinesis_firehose_delivery_stream.logs_to_s3_opensearch.arn
}

#------------------------------------------------------------------------------
# IAM ROLES INFORMATION
#------------------------------------------------------------------------------

output "lambda_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_role.arn
}

output "firehose_role_arn" {
  description = "ARN of the Kinesis Data Firehose delivery role"
  value       = aws_iam_role.firehose_role.arn
}

output "cloudfront_logs_role_arn" {
  description = "ARN of the CloudFront real-time logs role"
  value       = aws_iam_role.cloudfront_realtime_logs_role.arn
}

#------------------------------------------------------------------------------
# MONITORING INFORMATION
#------------------------------------------------------------------------------

output "cloudwatch_dashboard_name" {
  description = "Name of the CloudWatch dashboard"
  value       = var.enable_dashboard ? aws_cloudwatch_dashboard.main[0].dashboard_name : null
}

output "cloudwatch_dashboard_url" {
  description = "URL to view the CloudWatch dashboard"
  value       = var.enable_dashboard ? "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.main[0].dashboard_name}" : null
}

output "lambda_log_group_url" {
  description = "URL to view Lambda function logs in CloudWatch"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#logsV2:log-groups/log-group/${replace(aws_cloudwatch_log_group.lambda.name, "/", "$252F")}"
}

output "firehose_log_group_url" {
  description = "URL to view Firehose logs in CloudWatch"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#logsV2:log-groups/log-group/${replace(aws_cloudwatch_log_group.firehose.name, "/", "$252F")}"
}

#------------------------------------------------------------------------------
# SAMPLE CONTENT INFORMATION
#------------------------------------------------------------------------------

output "sample_content_created" {
  description = "Whether sample content was created for testing"
  value       = var.create_sample_content
}

output "sample_content_urls" {
  description = "URLs to access sample content through CloudFront"
  value = var.create_sample_content ? {
    home_page = "https://${aws_cloudfront_distribution.main.domain_name}/"
    css_file  = "https://${aws_cloudfront_distribution.main.domain_name}/css/style.css"
    js_file   = "https://${aws_cloudfront_distribution.main.domain_name}/js/app.js"
    api_data  = "https://${aws_cloudfront_distribution.main.domain_name}/api/data"
  } : {}
}

#------------------------------------------------------------------------------
# COST AND OPERATIONAL INFORMATION
#------------------------------------------------------------------------------

output "estimated_monthly_cost_usd" {
  description = "Estimated monthly cost in USD (varies by usage)"
  value = {
    cloudfront_requests_per_10k = "0.0075"
    cloudfront_data_transfer_gb = "0.085"
    kinesis_shard_hours         = "${var.kinesis_shard_count + var.kinesis_processed_shard_count} * 0.015"
    kinesis_put_payload_units   = "0.014 per million"
    lambda_requests_per_million = "0.20"
    lambda_gb_seconds          = "0.0000166667"
    opensearch_instance_hours   = "${var.opensearch_instance_type} * 24 * 30"
    dynamodb_requests_per_million = "0.25"
    s3_storage_gb              = "0.023"
    total_estimated_range      = "50-150 USD/month (varies by traffic)"
  }
}

output "operational_notes" {
  description = "Important operational information"
  value = {
    opensearch_access = "Configure IP ranges in opensearch_access_ip_ranges variable"
    real_time_logs   = "Real-time logs may incur additional costs based on request volume"
    data_retention   = "DynamoDB metrics retained for ${var.dynamodb_ttl_days} days"
    log_retention    = "CloudWatch logs retained for ${var.cloudwatch_log_retention_days} days"
    scaling_note     = "Kinesis shards and OpenSearch instances can be scaled based on traffic"
  }
}

#------------------------------------------------------------------------------
# TESTING AND VALIDATION URLS
#------------------------------------------------------------------------------

output "validation_commands" {
  description = "Commands to validate the infrastructure deployment"
  value = {
    test_cloudfront = "curl -I https://${aws_cloudfront_distribution.main.domain_name}/"
    check_kinesis   = "aws kinesis describe-stream --stream-name ${aws_kinesis_stream.cloudfront_logs.name}"
    check_lambda    = "aws lambda get-function --function-name ${aws_lambda_function.log_processor.function_name}"
    check_opensearch = "curl -s https://${aws_opensearch_domain.analytics.endpoint}/_cluster/health"
    view_metrics    = "aws cloudwatch get-metric-statistics --namespace CloudFront/RealTime --metric-name RequestCount --start-time $(date -d '1 hour ago' --iso-8601) --end-time $(date --iso-8601) --period 300 --statistics Sum"
  }
}

output "management_console_urls" {
  description = "AWS Management Console URLs for key resources"
  value = {
    cloudfront_console = "https://console.aws.amazon.com/cloudfront/v3/home?region=${data.aws_region.current.name}#/distributions/${aws_cloudfront_distribution.main.id}"
    kinesis_console    = "https://${data.aws_region.current.name}.console.aws.amazon.com/kinesis/home?region=${data.aws_region.current.name}#/streams/details/${aws_kinesis_stream.cloudfront_logs.name}/monitoring"
    lambda_console     = "https://${data.aws_region.current.name}.console.aws.amazon.com/lambda/home?region=${data.aws_region.current.name}#/functions/${aws_lambda_function.log_processor.function_name}"
    opensearch_console = "https://${data.aws_region.current.name}.console.aws.amazon.com/esv3/home?region=${data.aws_region.current.name}#opensearch/domains/${aws_opensearch_domain.analytics.domain_name}"
    dynamodb_console   = "https://${data.aws_region.current.name}.console.aws.amazon.com/dynamodbv2/home?region=${data.aws_region.current.name}#table?name=${aws_dynamodb_table.metrics.name}"
    s3_content_console = "https://s3.console.aws.amazon.com/s3/buckets/${aws_s3_bucket.content.id}?region=${data.aws_region.current.name}"
    s3_logs_console    = "https://s3.console.aws.amazon.com/s3/buckets/${aws_s3_bucket.logs.id}?region=${data.aws_region.current.name}"
  }
}

#------------------------------------------------------------------------------
# SECURITY AND COMPLIANCE INFORMATION
#------------------------------------------------------------------------------

output "security_features" {
  description = "Security features enabled in the deployment"
  value = {
    s3_encryption           = "Server-side encryption enabled with AES256"
    s3_public_access_block  = var.enable_s3_public_access_block
    kinesis_encryption      = "KMS encryption enabled for Kinesis streams"
    opensearch_encryption   = "Encryption at rest and in transit enabled"
    cloudfront_https        = "HTTPS enforced with minimum TLS 1.2"
    iam_least_privilege     = "IAM roles follow least privilege principle"
    ip_anonymization        = "Client IP addresses are anonymized in processed logs"
  }
}

#------------------------------------------------------------------------------
# TROUBLESHOOTING INFORMATION
#------------------------------------------------------------------------------

output "troubleshooting_info" {
  description = "Information for troubleshooting common issues"
  value = {
    opensearch_domain_status = "Check domain status: aws opensearch describe-domain --domain-name ${aws_opensearch_domain.analytics.domain_name}"
    lambda_errors           = "View Lambda errors in CloudWatch Logs: ${aws_cloudwatch_log_group.lambda.name}"
    kinesis_metrics         = "Monitor Kinesis metrics in CloudWatch console"
    cloudfront_distribution = "CloudFront distribution may take 10-15 minutes to deploy"
    real_time_logs_delay    = "Real-time logs may have 1-2 minute delay initially"
  }
}