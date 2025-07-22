# OpenSearch Domain Outputs
output "opensearch_domain_arn" {
  description = "ARN of the OpenSearch domain"
  value       = aws_opensearch_domain.logging_domain.arn
}

output "opensearch_domain_id" {
  description = "Unique identifier for the OpenSearch domain"
  value       = aws_opensearch_domain.logging_domain.domain_id
}

output "opensearch_endpoint" {
  description = "Domain-specific endpoint used to submit index, search, and data upload requests"
  value       = aws_opensearch_domain.logging_domain.endpoint
}

output "opensearch_dashboard_endpoint" {
  description = "OpenSearch Dashboards endpoint"
  value       = aws_opensearch_domain.logging_domain.dashboard_endpoint
}

output "opensearch_domain_name" {
  description = "Name of the OpenSearch domain"
  value       = aws_opensearch_domain.logging_domain.domain_name
}

# Kinesis Stream Outputs
output "kinesis_stream_arn" {
  description = "ARN of the Kinesis Data Stream"
  value       = aws_kinesis_stream.log_stream.arn
}

output "kinesis_stream_name" {
  description = "Name of the Kinesis Data Stream"
  value       = aws_kinesis_stream.log_stream.name
}

output "kinesis_stream_shard_count" {
  description = "Number of shards in the Kinesis Data Stream"
  value       = aws_kinesis_stream.log_stream.shard_count
}

# Kinesis Firehose Outputs
output "firehose_delivery_stream_arn" {
  description = "ARN of the Kinesis Data Firehose delivery stream"
  value       = aws_kinesis_firehose_delivery_stream.opensearch_delivery_stream.arn
}

output "firehose_delivery_stream_name" {
  description = "Name of the Kinesis Data Firehose delivery stream"
  value       = aws_kinesis_firehose_delivery_stream.opensearch_delivery_stream.name
}

# Lambda Function Outputs
output "lambda_function_arn" {
  description = "ARN of the log processing Lambda function"
  value       = aws_lambda_function.log_processor.arn
}

output "lambda_function_name" {
  description = "Name of the log processing Lambda function"
  value       = aws_lambda_function.log_processor.function_name
}

output "lambda_function_invoke_arn" {
  description = "ARN to be used for invoking Lambda function from API Gateway"
  value       = aws_lambda_function.log_processor.invoke_arn
}

# S3 Bucket Outputs
output "backup_bucket_name" {
  description = "Name of the S3 bucket used for backup storage"
  value       = aws_s3_bucket.backup_bucket.bucket
}

output "backup_bucket_arn" {
  description = "ARN of the S3 bucket used for backup storage"
  value       = aws_s3_bucket.backup_bucket.arn
}

# IAM Role Outputs
output "cloudwatch_logs_role_arn" {
  description = "ARN of the CloudWatch Logs role for Kinesis integration"
  value       = aws_iam_role.cloudwatch_logs_role.arn
}

output "lambda_execution_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_role.arn
}

output "firehose_delivery_role_arn" {
  description = "ARN of the Firehose delivery role"
  value       = aws_iam_role.firehose_role.arn
}

# CloudWatch Log Groups
output "opensearch_log_group_name" {
  description = "Name of the OpenSearch CloudWatch log group"
  value       = var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.opensearch_logs[0].name : null
}

output "lambda_log_group_name" {
  description = "Name of the Lambda CloudWatch log group"
  value       = aws_cloudwatch_log_group.lambda_log_group.name
}

output "firehose_log_group_name" {
  description = "Name of the Firehose CloudWatch log group"
  value       = aws_cloudwatch_log_group.firehose_log_group.name
}

output "test_log_group_name" {
  description = "Name of the test CloudWatch log group (if created)"
  value       = var.create_test_log_group ? aws_cloudwatch_log_group.test_log_group[0].name : null
}

# Deployment Information
output "deployment_region" {
  description = "AWS region where resources were deployed"
  value       = data.aws_region.current.name
}

output "account_id" {
  description = "AWS account ID where resources were deployed"
  value       = data.aws_caller_identity.current.account_id
}

output "resource_name_suffix" {
  description = "Random suffix used for resource naming"
  value       = local.name_suffix
}

# Quick Access URLs
output "opensearch_dashboard_url" {
  description = "Direct URL to OpenSearch Dashboards"
  value       = "https://${aws_opensearch_domain.logging_domain.dashboard_endpoint}"
}

output "opensearch_api_url" {
  description = "Direct URL to OpenSearch API endpoint"
  value       = "https://${aws_opensearch_domain.logging_domain.endpoint}"
}

# Command Examples
output "sample_curl_command" {
  description = "Sample curl command to query OpenSearch (requires AWS CLI credentials)"
  value = "curl -X GET 'https://${aws_opensearch_domain.logging_domain.endpoint}/logs-$(date -u +%Y.%m.%d)/_search' -H 'Content-Type: application/json' -d '{\"query\":{\"match_all\":{}},\"size\":10}' --aws-sigv4 'aws:amz:${data.aws_region.current.name}:es' --user '${data.aws_caller_identity.current.access_key}:${data.aws_caller_identity.current.secret_key}'"
}

output "subscription_filter_command_example" {
  description = "Example AWS CLI command to add subscription filter to a log group"
  value = "aws logs put-subscription-filter --log-group-name '/aws/lambda/my-function' --filter-name 'central-logging-filter' --filter-pattern '' --destination-arn '${aws_kinesis_stream.log_stream.arn}' --role-arn '${aws_iam_role.cloudwatch_logs_role.arn}' --region ${data.aws_region.current.name}"
}

# Cost Estimation Information
output "estimated_monthly_cost_info" {
  description = "Information about estimated monthly costs (varies by usage)"
  value = {
    opensearch_domain = "~$50-150/month for t3.small.search instances (varies by instance hours and storage)"
    kinesis_stream    = "~$15-30/month for ${var.kinesis_shard_count} shards (plus data ingestion costs)"
    lambda_function   = "~$1-10/month (depends on number of invocations)"
    firehose_delivery = "~$5-20/month (depends on data volume)"
    s3_storage       = "~$1-5/month for backup storage (depends on failed delivery volume)"
    note             = "Actual costs depend heavily on log volume, retention, and query patterns"
  }
}

# Monitoring and Troubleshooting
output "monitoring_dashboard_metrics" {
  description = "Key CloudWatch metrics to monitor"
  value = {
    kinesis_incoming_records = "AWS/Kinesis - IncomingRecords (${aws_kinesis_stream.log_stream.name})"
    lambda_invocations      = "AWS/Lambda - Invocations (${aws_lambda_function.log_processor.function_name})"
    lambda_errors          = "AWS/Lambda - Errors (${aws_lambda_function.log_processor.function_name})"
    opensearch_indexing    = "AWS/ES - IndexingRate (${aws_opensearch_domain.logging_domain.domain_name})"
    opensearch_search      = "AWS/ES - SearchRate (${aws_opensearch_domain.logging_domain.domain_name})"
    firehose_delivery      = "AWS/KinesisFirehose - DeliveryToElasticsearch.Records (${aws_kinesis_firehose_delivery_stream.opensearch_delivery_stream.name})"
  }
}

output "troubleshooting_commands" {
  description = "Useful commands for troubleshooting the pipeline"
  value = {
    check_kinesis_metrics     = "aws cloudwatch get-metric-statistics --namespace AWS/Kinesis --metric-name IncomingRecords --dimensions Name=StreamName,Value=${aws_kinesis_stream.log_stream.name} --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) --end-time $(date -u +%Y-%m-%dT%H:%M:%S) --period 300 --statistics Sum"
    check_lambda_logs        = "aws logs describe-log-streams --log-group-name ${aws_cloudwatch_log_group.lambda_log_group.name} | aws logs get-log-events --log-group-name ${aws_cloudwatch_log_group.lambda_log_group.name} --log-stream-name STREAM_NAME"
    check_opensearch_indices = "curl -X GET 'https://${aws_opensearch_domain.logging_domain.endpoint}/_cat/indices' --aws-sigv4 'aws:amz:${data.aws_region.current.name}:es'"
    test_log_ingestion      = "aws logs put-log-events --log-group-name ${var.create_test_log_group ? aws_cloudwatch_log_group.test_log_group[0].name : "YOUR_LOG_GROUP"} --log-stream-name test-stream --log-events timestamp=$(date +%s)000,message='Test log message'"
  }
}