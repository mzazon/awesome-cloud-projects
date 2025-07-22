# Outputs for IoT Analytics Pipeline Infrastructure

# ============================================================================
# GENERAL OUTPUTS
# ============================================================================

output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "aws_account_id" {
  description = "AWS account ID"
  value       = data.aws_caller_identity.current.account_id
}

output "random_suffix" {
  description = "Random suffix used for resource names"
  value       = local.suffix
}

# ============================================================================
# IOT ANALYTICS OUTPUTS (LEGACY)
# ============================================================================

output "iot_analytics_channel_name" {
  description = "Name of the IoT Analytics channel"
  value       = aws_iotanalytics_channel.sensor_channel.name
}

output "iot_analytics_channel_arn" {
  description = "ARN of the IoT Analytics channel"
  value       = aws_iotanalytics_channel.sensor_channel.arn
}

output "iot_analytics_datastore_name" {
  description = "Name of the IoT Analytics datastore"
  value       = aws_iotanalytics_datastore.sensor_datastore.name
}

output "iot_analytics_datastore_arn" {
  description = "ARN of the IoT Analytics datastore"
  value       = aws_iotanalytics_datastore.sensor_datastore.arn
}

output "iot_analytics_pipeline_name" {
  description = "Name of the IoT Analytics pipeline"
  value       = aws_iotanalytics_pipeline.sensor_pipeline.name
}

output "iot_analytics_pipeline_arn" {
  description = "ARN of the IoT Analytics pipeline"
  value       = aws_iotanalytics_pipeline.sensor_pipeline.arn
}

output "iot_analytics_dataset_name" {
  description = "Name of the IoT Analytics dataset"
  value       = aws_iotanalytics_dataset.sensor_dataset.name
}

output "iot_analytics_dataset_arn" {
  description = "ARN of the IoT Analytics dataset"
  value       = aws_iotanalytics_dataset.sensor_dataset.arn
}

# ============================================================================
# MODERN ALTERNATIVE OUTPUTS
# ============================================================================

output "kinesis_stream_name" {
  description = "Name of the Kinesis Data Stream"
  value       = aws_kinesis_stream.sensor_stream.name
}

output "kinesis_stream_arn" {
  description = "ARN of the Kinesis Data Stream"
  value       = aws_kinesis_stream.sensor_stream.arn
}

output "timestream_database_name" {
  description = "Name of the Timestream database"
  value       = aws_timestreamwrite_database.iot_database.database_name
}

output "timestream_database_arn" {
  description = "ARN of the Timestream database"
  value       = aws_timestreamwrite_database.iot_database.arn
}

output "timestream_table_name" {
  description = "Name of the Timestream table"
  value       = aws_timestreamwrite_table.sensor_data.table_name
}

output "timestream_table_arn" {
  description = "ARN of the Timestream table"
  value       = aws_timestreamwrite_table.sensor_data.arn
}

output "lambda_function_name" {
  description = "Name of the Lambda function"
  value       = aws_lambda_function.process_iot_data.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function"
  value       = aws_lambda_function.process_iot_data.arn
}

# ============================================================================
# IOT RULES ENGINE OUTPUTS
# ============================================================================

output "iot_topic_rule_name" {
  description = "Name of the IoT topic rule"
  value       = aws_iot_topic_rule.sensor_data_rule.name
}

output "iot_topic_rule_arn" {
  description = "ARN of the IoT topic rule"
  value       = aws_iot_topic_rule.sensor_data_rule.arn
}

output "iot_topic_name" {
  description = "IoT topic name for sensor data"
  value       = var.iot_topic_name
}

# ============================================================================
# IAM ROLE OUTPUTS
# ============================================================================

output "iot_analytics_role_arn" {
  description = "ARN of the IoT Analytics service role"
  value       = aws_iam_role.iot_analytics_role.arn
}

output "lambda_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_role.arn
}

output "iot_rule_role_arn" {
  description = "ARN of the IoT rule execution role"
  value       = aws_iam_role.iot_rule_role.arn
}

# ============================================================================
# TESTING AND VALIDATION OUTPUTS
# ============================================================================

output "test_commands" {
  description = "Commands to test the IoT Analytics pipeline"
  value = {
    # Send test data to IoT Analytics channel
    send_test_data_analytics = "aws iotanalytics batch-put-message --channel-name ${aws_iotanalytics_channel.sensor_channel.name} --messages '[{\"messageId\": \"test-msg-001\", \"payload\": \"'$(echo -n '{\"timestamp\": \"'$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)'\", \"deviceId\": \"sensor001\", \"temperature\": 23.5, \"humidity\": 65.2}' | base64)'\"}]'"
    
    # Send test data to Kinesis
    send_test_data_kinesis = "aws kinesis put-record --stream-name ${aws_kinesis_stream.sensor_stream.name} --partition-key sensor001 --data '{\"timestamp\": \"'$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)'\", \"deviceId\": \"sensor001\", \"temperature\": 26.3, \"humidity\": 60.1}'"
    
    # Check IoT Analytics dataset
    check_dataset = "aws iotanalytics get-dataset-content --dataset-name ${aws_iotanalytics_dataset.sensor_dataset.name} --version-id '$LATEST'"
    
    # Query Timestream data
    query_timestream = "aws timestream-query query --query-string \"SELECT * FROM \\\"${aws_timestreamwrite_database.iot_database.database_name}\\\".\\\"${aws_timestreamwrite_table.sensor_data.table_name}\\\" WHERE time > ago(1h) ORDER BY time DESC LIMIT 10\""
    
    # Check Lambda logs
    check_lambda_logs = "aws logs describe-log-groups --log-group-name-prefix /aws/lambda/${aws_lambda_function.process_iot_data.function_name}"
  }
}

output "dashboard_urls" {
  description = "URLs for monitoring and visualization"
  value = {
    # CloudWatch dashboard for Lambda metrics
    lambda_metrics = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#metricsV2:graph=~();query=AWS%2FLambda%20FunctionName%3D${aws_lambda_function.process_iot_data.function_name}"
    
    # Kinesis monitoring
    kinesis_monitoring = "https://${data.aws_region.current.name}.console.aws.amazon.com/kinesis/home?region=${data.aws_region.current.name}#/streams/details/${aws_kinesis_stream.sensor_stream.name}/monitoring"
    
    # Timestream console
    timestream_console = "https://${data.aws_region.current.name}.console.aws.amazon.com/timestream/home?region=${data.aws_region.current.name}#databases/${aws_timestreamwrite_database.iot_database.database_name}/tables/${aws_timestreamwrite_table.sensor_data.table_name}"
    
    # IoT Analytics console
    iot_analytics_console = "https://${data.aws_region.current.name}.console.aws.amazon.com/iotanalytics/home?region=${data.aws_region.current.name}#/datasets/${aws_iotanalytics_dataset.sensor_dataset.name}"
  }
}

# ============================================================================
# MIGRATION GUIDANCE
# ============================================================================

output "migration_notes" {
  description = "Important notes about migrating from IoT Analytics to modern alternatives"
  value = {
    deprecation_notice = "AWS IoT Analytics will reach end-of-support on December 15, 2025. Please plan migration to the modern alternative using Kinesis and Timestream."
    
    modern_alternative = {
      data_ingestion = "Use Kinesis Data Streams instead of IoT Analytics channels"
      data_processing = "Use Lambda functions instead of IoT Analytics pipelines"
      data_storage = "Use Amazon Timestream instead of IoT Analytics datastores"
      data_analysis = "Use Amazon Athena with Timestream or QuickSight for analytics"
    }
    
    migration_steps = [
      "1. Verify modern alternative is working with test data",
      "2. Update IoT rules to route data to both old and new systems",
      "3. Migrate existing data from IoT Analytics to Timestream",
      "4. Update applications to query Timestream instead of IoT Analytics",
      "5. Remove IoT Analytics resources after validation"
    ]
  }
}