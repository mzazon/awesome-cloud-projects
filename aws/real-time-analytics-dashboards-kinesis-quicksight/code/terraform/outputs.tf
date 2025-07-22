# Output values for real-time analytics dashboards infrastructure
# These outputs provide important information for validation and integration

output "kinesis_stream_name" {
  description = "Name of the Kinesis Data Stream for data ingestion"
  value       = aws_kinesis_stream.analytics_stream.name
}

output "kinesis_stream_arn" {
  description = "ARN of the Kinesis Data Stream"
  value       = aws_kinesis_stream.analytics_stream.arn
}

output "kinesis_stream_shard_count" {
  description = "Number of shards in the Kinesis Data Stream"
  value       = aws_kinesis_stream.analytics_stream.shard_count
}

output "flink_application_name" {
  description = "Name of the Managed Service for Apache Flink application"
  value       = aws_kinesisanalyticsv2_application.analytics_app.name
}

output "flink_application_arn" {
  description = "ARN of the Flink application"
  value       = aws_kinesisanalyticsv2_application.analytics_app.arn
}

output "flink_application_version_id" {
  description = "Version ID of the Flink application"
  value       = aws_kinesisanalyticsv2_application.analytics_app.version_id
}

output "flink_service_execution_role_arn" {
  description = "ARN of the IAM role used by the Flink application"
  value       = aws_iam_role.flink_analytics_role.arn
}

output "analytics_results_bucket_name" {
  description = "Name of S3 bucket storing processed analytics data"
  value       = aws_s3_bucket.analytics_results.bucket
}

output "analytics_results_bucket_arn" {
  description = "ARN of S3 bucket storing processed analytics data"
  value       = aws_s3_bucket.analytics_results.arn
}

output "analytics_results_bucket_domain_name" {
  description = "Domain name of the analytics results S3 bucket"
  value       = aws_s3_bucket.analytics_results.bucket_domain_name
}

output "flink_code_bucket_name" {
  description = "Name of S3 bucket storing Flink application code"
  value       = aws_s3_bucket.flink_code.bucket
}

output "flink_code_bucket_arn" {
  description = "ARN of S3 bucket storing Flink application code"
  value       = aws_s3_bucket.flink_code.arn
}

output "quicksight_manifest_s3_url" {
  description = "S3 URL of the QuickSight manifest file for data source configuration"
  value       = "s3://${aws_s3_bucket.analytics_results.bucket}/${aws_s3_object.quicksight_manifest.key}"
}

output "quicksight_data_source_s3_path" {
  description = "S3 path containing analytics data for QuickSight dashboard"
  value       = "s3://${aws_s3_bucket.analytics_results.bucket}/analytics-results/"
}

output "cloudwatch_log_group_name" {
  description = "Name of CloudWatch log group for Flink application logs"
  value       = aws_cloudwatch_log_group.flink_application.name
}

output "cloudwatch_log_group_arn" {
  description = "ARN of CloudWatch log group for Flink application logs"
  value       = aws_cloudwatch_log_group.flink_application.arn
}

output "cloudwatch_dashboard_url" {
  description = "URL to access the CloudWatch monitoring dashboard"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.analytics_dashboard.dashboard_name}"
}

output "sns_alerts_topic_arn" {
  description = "ARN of SNS topic for analytics pipeline alerts"
  value       = aws_sns_topic.analytics_alerts.arn
}

# Regional and account information
output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "aws_account_id" {
  description = "AWS account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

# Resource naming information
output "resource_name_prefix" {
  description = "Common name prefix used for all resources"
  value       = local.name_prefix
}

output "resource_name_suffix" {
  description = "Random suffix used for unique resource naming"
  value       = local.name_suffix
}

# Instructions for next steps
output "deployment_instructions" {
  description = "Instructions for completing the deployment"
  value = {
    step1 = "Upload your Flink application JAR file to: s3://${aws_s3_bucket.flink_code.bucket}/${var.flink_jar_key}"
    step2 = "Start the Flink application using: aws kinesisanalyticsv2 start-application --application-name ${aws_kinesisanalyticsv2_application.analytics_app.name}"
    step3 = "Configure QuickSight data source using S3 path: ${aws_s3_bucket.analytics_results.bucket}/analytics-results/"
    step4 = "Use manifest file for QuickSight: s3://${aws_s3_bucket.analytics_results.bucket}/${aws_s3_object.quicksight_manifest.key}"
    step5 = "Monitor the pipeline using CloudWatch dashboard: ${aws_cloudwatch_dashboard.analytics_dashboard.dashboard_name}"
  }
}

# Sample data generation command
output "sample_data_generator_command" {
  description = "Command to generate sample data for testing (set environment variables first)"
  value = "export STREAM_NAME=${aws_kinesis_stream.analytics_stream.name} && python3 generate_sample_data.py"
}

# Validation commands
output "validation_commands" {
  description = "Commands to validate the deployment"
  value = {
    check_kinesis_stream = "aws kinesis describe-stream --stream-name ${aws_kinesis_stream.analytics_stream.name}"
    check_flink_app      = "aws kinesisanalyticsv2 describe-application --application-name ${aws_kinesisanalyticsv2_application.analytics_app.name}"
    list_s3_analytics    = "aws s3 ls s3://${aws_s3_bucket.analytics_results.bucket}/analytics-results/ --recursive"
    view_logs           = "aws logs describe-log-groups --log-group-name-prefix '${aws_cloudwatch_log_group.flink_application.name}'"
  }
}

# Cost estimation
output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown (USD) for moderate usage (1GB/day)"
  value = {
    kinesis_data_streams = "~$10-20 (based on shard hours and data volume)"
    flink_application   = "~$30-50 (based on KPU hours and parallelism)"
    s3_storage         = "~$5-10 (based on data retention and storage class)"
    cloudwatch_logs    = "~$2-5 (based on log volume and retention)"
    total_estimated    = "~$50-100/month"
    note              = "Actual costs depend on data volume, retention, and usage patterns"
  }
}