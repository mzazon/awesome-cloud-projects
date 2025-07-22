# S3 Bucket Information
output "s3_bucket_name" {
  description = "Name of the S3 bucket for IoT data storage"
  value       = aws_s3_bucket.iot_data.bucket
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket for IoT data storage"
  value       = aws_s3_bucket.iot_data.arn
}

# Kinesis Stream Information
output "kinesis_stream_name" {
  description = "Name of the Kinesis Data Stream"
  value       = aws_kinesis_stream.iot_data.name
}

output "kinesis_stream_arn" {
  description = "ARN of the Kinesis Data Stream"
  value       = aws_kinesis_stream.iot_data.arn
}

# Kinesis Firehose Information
output "firehose_delivery_stream_name" {
  description = "Name of the Kinesis Data Firehose delivery stream"
  value       = aws_kinesis_firehose_delivery_stream.iot_data.name
}

output "firehose_delivery_stream_arn" {
  description = "ARN of the Kinesis Data Firehose delivery stream"
  value       = aws_kinesis_firehose_delivery_stream.iot_data.arn
}

# IoT Resources
output "iot_thing_name" {
  description = "Name of the IoT thing (sensor device)"
  value       = aws_iot_thing.sensor_device.name
}

output "iot_thing_arn" {
  description = "ARN of the IoT thing (sensor device)"
  value       = aws_iot_thing.sensor_device.arn
}

output "iot_policy_name" {
  description = "Name of the IoT policy"
  value       = aws_iot_policy.device_policy.name
}

output "iot_topic_rule_name" {
  description = "Name of the IoT topic rule"
  value       = aws_iot_topic_rule.route_to_kinesis.name
}

output "iot_topic_rule_arn" {
  description = "ARN of the IoT topic rule"
  value       = aws_iot_topic_rule.route_to_kinesis.arn
}

output "iot_topic_name" {
  description = "IoT topic name for publishing sensor data"
  value       = var.iot_topic_name
}

# Glue Data Catalog Information
output "glue_database_name" {
  description = "Name of the Glue database"
  value       = aws_glue_catalog_database.iot_analytics.name
}

output "glue_table_name" {
  description = "Name of the Glue table for IoT sensor data"
  value       = aws_glue_catalog_table.iot_sensor_data.name
}

# QuickSight Information
output "quicksight_data_source_id" {
  description = "ID of the QuickSight data source"
  value       = aws_quicksight_data_source.iot_athena.data_source_id
}

output "quicksight_data_source_arn" {
  description = "ARN of the QuickSight data source"
  value       = aws_quicksight_data_source.iot_athena.arn
}

output "quicksight_dataset_id" {
  description = "ID of the QuickSight dataset"
  value       = aws_quicksight_data_set.iot_sensor_dataset.data_set_id
}

output "quicksight_dataset_arn" {
  description = "ARN of the QuickSight dataset"
  value       = aws_quicksight_data_set.iot_sensor_dataset.arn
}

# IAM Role Information
output "iot_kinesis_role_arn" {
  description = "ARN of the IAM role for IoT Rules Engine to access Kinesis"
  value       = aws_iam_role.iot_kinesis_role.arn
}

output "firehose_delivery_role_arn" {
  description = "ARN of the IAM role for Kinesis Data Firehose"
  value       = aws_iam_role.firehose_delivery_role.arn
}

# CloudWatch Log Groups
output "iot_rule_log_group_name" {
  description = "Name of the CloudWatch log group for IoT rule"
  value       = aws_cloudwatch_log_group.iot_rule_logs.name
}

output "firehose_log_group_name" {
  description = "Name of the CloudWatch log group for Firehose"
  value       = aws_cloudwatch_log_group.firehose_logs.name
}

# Connection Information
output "region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "account_id" {
  description = "AWS account ID"
  value       = data.aws_caller_identity.current.account_id
}

# Resource Name Suffix
output "resource_suffix" {
  description = "Random suffix used for resource names"
  value       = local.suffix
}

# Sample IoT Data Publishing Command
output "sample_iot_publish_command" {
  description = "Sample AWS CLI command to publish IoT data"
  value = "aws iot-data publish --topic '${var.iot_topic_name}' --payload '{\"device_id\":\"${aws_iot_thing.sensor_device.name}\",\"temperature\":25,\"humidity\":60,\"pressure\":1013,\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)\"}'"
}

# QuickSight Console URL
output "quicksight_console_url" {
  description = "URL to access QuickSight console"
  value       = "https://${data.aws_region.current.name}.quicksight.aws.amazon.com/sn/start"
}

# Athena Query Examples
output "athena_query_examples" {
  description = "Example Athena queries for IoT data analysis"
  value = {
    "Select all data" = "SELECT * FROM ${aws_glue_catalog_database.iot_analytics.name}.${aws_glue_catalog_table.iot_sensor_data.name} LIMIT 10;"
    "Average temperature" = "SELECT device_id, AVG(temperature) as avg_temp FROM ${aws_glue_catalog_database.iot_analytics.name}.${aws_glue_catalog_table.iot_sensor_data.name} GROUP BY device_id;"
    "Recent data" = "SELECT * FROM ${aws_glue_catalog_database.iot_analytics.name}.${aws_glue_catalog_table.iot_sensor_data.name} WHERE year = '2025' AND month = '01' ORDER BY timestamp DESC LIMIT 100;"
  }
}

# Cost Optimization Tips
output "cost_optimization_tips" {
  description = "Tips for optimizing costs"
  value = {
    "S3 Lifecycle" = "Data automatically transitions to IA after ${var.s3_lifecycle_days} days and to Glacier after ${var.s3_lifecycle_days * 3} days"
    "Kinesis Shards" = "Monitor shard utilization and adjust shard count based on actual data volume"
    "QuickSight" = "Use QuickSight SPICE for frequently accessed data to reduce Athena query costs"
    "Firehose Buffer" = "Adjust buffer size (${var.firehose_buffer_size}MB) and interval (${var.firehose_buffer_interval}s) based on data volume"
  }
}