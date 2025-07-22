# Output Values for Real-time Anomaly Detection Infrastructure
# This file defines the outputs that will be displayed after deployment

output "kinesis_stream_name" {
  description = "Name of the Kinesis Data Stream"
  value       = aws_kinesis_stream.transaction_stream.name
}

output "kinesis_stream_arn" {
  description = "ARN of the Kinesis Data Stream"
  value       = aws_kinesis_stream.transaction_stream.arn
}

output "kinesis_stream_shard_count" {
  description = "Number of shards in the Kinesis Data Stream"
  value       = aws_kinesis_stream.transaction_stream.shard_count
}

output "flink_application_name" {
  description = "Name of the Managed Service for Apache Flink application"
  value       = aws_kinesisanalyticsv2_application.anomaly_detector.name
}

output "flink_application_arn" {
  description = "ARN of the Managed Service for Apache Flink application"
  value       = aws_kinesisanalyticsv2_application.anomaly_detector.arn
}

output "flink_application_version_id" {
  description = "Version ID of the Flink application"
  value       = aws_kinesisanalyticsv2_application.anomaly_detector.version_id
}

output "s3_bucket_name" {
  description = "Name of the S3 bucket for data storage"
  value       = aws_s3_bucket.anomaly_data.bucket
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket for data storage"
  value       = aws_s3_bucket.anomaly_data.arn
}

output "s3_bucket_domain_name" {
  description = "Domain name of the S3 bucket"
  value       = aws_s3_bucket.anomaly_data.bucket_domain_name
}

output "sns_topic_name" {
  description = "Name of the SNS topic for alerts"
  value       = aws_sns_topic.anomaly_alerts.name
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for alerts"
  value       = aws_sns_topic.anomaly_alerts.arn
}

output "lambda_function_name" {
  description = "Name of the Lambda function for anomaly processing"
  value       = aws_lambda_function.anomaly_processor.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function for anomaly processing"
  value       = aws_lambda_function.anomaly_processor.arn
}

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for Flink application"
  value       = aws_cloudwatch_log_group.flink_app_logs.name
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group for Flink application"
  value       = aws_cloudwatch_log_group.flink_app_logs.arn
}

output "iam_role_flink_arn" {
  description = "ARN of the IAM role for Flink application"
  value       = aws_iam_role.flink_service_role.arn
}

output "iam_role_lambda_arn" {
  description = "ARN of the IAM role for Lambda function"
  value       = aws_iam_role.lambda_execution_role.arn
}

output "cloudwatch_alarm_arn" {
  description = "ARN of the CloudWatch alarm for anomaly detection"
  value       = aws_cloudwatch_metric_alarm.anomaly_detection_alarm.arn
}

output "kinesis_firehose_delivery_stream_name" {
  description = "Name of the Kinesis Data Firehose delivery stream"
  value       = aws_kinesis_firehose_delivery_stream.anomaly_data_stream.name
}

output "kinesis_firehose_delivery_stream_arn" {
  description = "ARN of the Kinesis Data Firehose delivery stream"
  value       = aws_kinesis_firehose_delivery_stream.anomaly_data_stream.arn
}

# Deployment information
output "deployment_info" {
  description = "Deployment information and next steps"
  value = {
    region                    = var.aws_region
    environment              = var.environment
    flink_application_status = "READY_TO_START"
    next_steps = [
      "1. Start the Flink application using: aws kinesisanalyticsv2 start-application --application-name ${aws_kinesisanalyticsv2_application.anomaly_detector.name} --run-configuration '{\"FlinkRunConfiguration\": {\"AllowNonRestoredState\": true}}'",
      "2. Send test data to Kinesis stream: ${aws_kinesis_stream.transaction_stream.name}",
      "3. Monitor CloudWatch logs: ${aws_cloudwatch_log_group.flink_app_logs.name}",
      "4. Subscribe to SNS topic for alerts: ${aws_sns_topic.anomaly_alerts.arn}",
      "5. Check S3 bucket for stored data: ${aws_s3_bucket.anomaly_data.bucket}"
    ]
  }
}

# Connection strings for testing
output "test_commands" {
  description = "Useful commands for testing the deployment"
  value = {
    send_test_data = "aws kinesis put-record --stream-name ${aws_kinesis_stream.transaction_stream.name} --data '{\"userId\":\"test-user\",\"amount\":1000.0,\"timestamp\":${timestamp()},\"transactionId\":\"test-txn-001\"}' --partition-key test-user"
    check_stream_status = "aws kinesis describe-stream --stream-name ${aws_kinesis_stream.transaction_stream.name}"
    view_flink_logs = "aws logs describe-log-streams --log-group-name ${aws_cloudwatch_log_group.flink_app_logs.name}"
    subscribe_to_sns = "aws sns subscribe --topic-arn ${aws_sns_topic.anomaly_alerts.arn} --protocol email --notification-endpoint YOUR_EMAIL@example.com"
  }
}