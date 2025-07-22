# Outputs for Real-Time IoT Analytics Infrastructure
# This file defines outputs that provide important information about the deployed resources

# ===================================
# KINESIS OUTPUTS
# ===================================

output "kinesis_stream_name" {
  description = "Name of the Kinesis Data Stream"
  value       = aws_kinesis_stream.iot_stream.name
}

output "kinesis_stream_arn" {
  description = "ARN of the Kinesis Data Stream"
  value       = aws_kinesis_stream.iot_stream.arn
}

output "kinesis_shard_count" {
  description = "Number of shards in the Kinesis stream"
  value       = aws_kinesis_stream.iot_stream.shard_count
}

# ===================================
# S3 OUTPUTS
# ===================================

output "s3_bucket_name" {
  description = "Name of the S3 bucket for data storage"
  value       = aws_s3_bucket.data_bucket.id
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket for data storage"
  value       = aws_s3_bucket.data_bucket.arn
}

output "s3_bucket_domain_name" {
  description = "Domain name of the S3 bucket"
  value       = aws_s3_bucket.data_bucket.bucket_domain_name
}

# ===================================
# LAMBDA OUTPUTS
# ===================================

output "lambda_function_name" {
  description = "Name of the Lambda function"
  value       = aws_lambda_function.iot_processor.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function"
  value       = aws_lambda_function.iot_processor.arn
}

output "lambda_function_version" {
  description = "Version of the Lambda function"
  value       = aws_lambda_function.iot_processor.version
}

output "lambda_log_group_name" {
  description = "Name of the Lambda CloudWatch Log Group"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

# ===================================
# FLINK OUTPUTS
# ===================================

output "flink_application_name" {
  description = "Name of the Flink application"
  value       = aws_kinesisanalyticsv2_application.flink_app.name
}

output "flink_application_arn" {
  description = "ARN of the Flink application"
  value       = aws_kinesisanalyticsv2_application.flink_app.arn
}

output "flink_application_version" {
  description = "Version of the Flink application"
  value       = aws_kinesisanalyticsv2_application.flink_app.version_id
}

# ===================================
# SNS OUTPUTS
# ===================================

output "sns_topic_arn" {
  description = "ARN of the SNS topic for alerts"
  value       = aws_sns_topic.alerts.arn
}

output "sns_topic_name" {
  description = "Name of the SNS topic for alerts"
  value       = aws_sns_topic.alerts.name
}

# ===================================
# IAM OUTPUTS
# ===================================

output "lambda_role_arn" {
  description = "ARN of the Lambda IAM role"
  value       = aws_iam_role.lambda_role.arn
}

output "lambda_role_name" {
  description = "Name of the Lambda IAM role"
  value       = aws_iam_role.lambda_role.name
}

output "flink_role_arn" {
  description = "ARN of the Flink IAM role"
  value       = aws_iam_role.flink_role.arn
}

output "flink_role_name" {
  description = "Name of the Flink IAM role"
  value       = aws_iam_role.flink_role.name
}

# ===================================
# CLOUDWATCH OUTPUTS
# ===================================

output "cloudwatch_dashboard_name" {
  description = "Name of the CloudWatch dashboard"
  value       = aws_cloudwatch_dashboard.iot_analytics.dashboard_name
}

output "cloudwatch_dashboard_url" {
  description = "URL to access the CloudWatch dashboard"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.iot_analytics.dashboard_name}"
}

output "kinesis_alarm_name" {
  description = "Name of the Kinesis records CloudWatch alarm"
  value       = aws_cloudwatch_metric_alarm.kinesis_records.alarm_name
}

output "lambda_alarm_name" {
  description = "Name of the Lambda errors CloudWatch alarm"
  value       = aws_cloudwatch_metric_alarm.lambda_errors.alarm_name
}

# ===================================
# CONFIGURATION OUTPUTS
# ===================================

output "project_name" {
  description = "Project name used for resource naming"
  value       = var.project_name
}

output "environment" {
  description = "Environment name"
  value       = var.environment
}

output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "aws_account_id" {
  description = "AWS account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

output "resource_prefix" {
  description = "Resource prefix used for naming"
  value       = local.resource_prefix
}

# ===================================
# TESTING OUTPUTS
# ===================================

output "test_data_sample" {
  description = "Sample JSON data for testing the pipeline"
  value = jsonencode({
    device_id   = "sensor-1001"
    timestamp   = "2025-01-01T12:00:00Z"
    sensor_type = "temperature"
    value       = 75.5
    unit        = "°C"
    location    = "factory-floor-1"
  })
}

output "kinesis_put_command" {
  description = "AWS CLI command to put test data into Kinesis stream"
  value       = "aws kinesis put-record --stream-name ${aws_kinesis_stream.iot_stream.name} --data '{\"device_id\":\"sensor-1001\",\"timestamp\":\"2025-01-01T12:00:00Z\",\"sensor_type\":\"temperature\",\"value\":75.5,\"unit\":\"°C\",\"location\":\"factory-floor-1\"}' --partition-key sensor-1001"
}

# ===================================
# MANAGEMENT OUTPUTS
# ===================================

output "flink_start_command" {
  description = "AWS CLI command to start the Flink application"
  value       = "aws kinesisanalyticsv2 start-application --application-name ${aws_kinesisanalyticsv2_application.flink_app.name} --run-configuration '{\"ApplicationRestoreConfiguration\":{\"ApplicationRestoreType\":\"SKIP_RESTORE_FROM_SNAPSHOT\"}}'"
}

output "flink_stop_command" {
  description = "AWS CLI command to stop the Flink application"
  value       = "aws kinesisanalyticsv2 stop-application --application-name ${aws_kinesisanalyticsv2_application.flink_app.name}"
}

output "s3_data_locations" {
  description = "S3 locations for different data types"
  value = {
    raw_data         = "s3://${aws_s3_bucket.data_bucket.id}/raw-data/"
    processed_data   = "s3://${aws_s3_bucket.data_bucket.id}/processed-data/"
    analytics_results = "s3://${aws_s3_bucket.data_bucket.id}/analytics-results/"
    metrics_results  = "s3://${aws_s3_bucket.data_bucket.id}/metrics-results/"
  }
}

# ===================================
# MONITORING OUTPUTS
# ===================================

output "lambda_logs_command" {
  description = "AWS CLI command to view Lambda logs"
  value       = "aws logs filter-log-events --log-group-name ${aws_cloudwatch_log_group.lambda_logs.name} --start-time $(date -d '5 minutes ago' +%s)000"
}

output "kinesis_metrics_command" {
  description = "AWS CLI command to view Kinesis metrics"
  value       = "aws cloudwatch get-metric-statistics --namespace AWS/Kinesis --metric-name IncomingRecords --dimensions Name=StreamName,Value=${aws_kinesis_stream.iot_stream.name} --start-time $(date -d '1 hour ago' --iso-8601) --end-time $(date --iso-8601) --period 300 --statistics Sum"
}

# ===================================
# COST OPTIMIZATION OUTPUTS
# ===================================

output "cost_optimization_tips" {
  description = "Tips for optimizing costs"
  value = {
    kinesis_shards     = "Monitor shard utilization and adjust shard count based on actual throughput"
    lambda_memory      = "Monitor Lambda memory usage and adjust memory allocation for cost optimization"
    s3_lifecycle       = "S3 lifecycle policies are configured to transition data to cheaper storage classes"
    log_retention      = "CloudWatch log retention is set to ${var.cloudwatch_log_retention_days} days to control costs"
    flink_parallelism  = "Adjust Flink parallelism based on actual processing requirements"
  }
}

# ===================================
# SECURITY OUTPUTS
# ===================================

output "security_features" {
  description = "Security features implemented"
  value = {
    s3_encryption     = "S3 bucket encrypted with AES256"
    s3_public_access  = "S3 public access blocked"
    iam_least_privilege = "IAM roles follow least privilege principle"
    vpc_optional      = "Consider deploying Lambda in VPC for additional security"
  }
}