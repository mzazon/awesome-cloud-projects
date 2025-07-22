# Outputs for Amazon Timestream Time-Series Data Solution
# This file defines all output values from the Terraform configuration

# === TIMESTREAM DATABASE OUTPUTS ===

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

# === DATA RETENTION OUTPUTS ===

output "memory_store_retention_hours" {
  description = "Memory store retention period in hours"
  value       = var.memory_store_retention_hours
}

output "magnetic_store_retention_days" {
  description = "Magnetic store retention period in days"
  value       = var.magnetic_store_retention_days
}

# === LAMBDA FUNCTION OUTPUTS ===

output "lambda_function_name" {
  description = "Name of the Lambda function for data ingestion"
  value       = aws_lambda_function.data_ingestion.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function"
  value       = aws_lambda_function.data_ingestion.arn
}

output "lambda_function_invoke_arn" {
  description = "Invoke ARN of the Lambda function"
  value       = aws_lambda_function.data_ingestion.invoke_arn
}

output "lambda_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_role.arn
}

# === IOT CORE OUTPUTS ===

output "iot_rule_name" {
  description = "Name of the IoT Core rule"
  value       = aws_iot_topic_rule.sensor_data_rule.name
}

output "iot_rule_arn" {
  description = "ARN of the IoT Core rule"
  value       = aws_iot_topic_rule.sensor_data_rule.arn
}

output "iot_topic_pattern" {
  description = "MQTT topic pattern for IoT sensor data"
  value       = var.iot_topic_pattern
}

output "iot_role_arn" {
  description = "ARN of the IoT Core execution role"
  value       = aws_iam_role.iot_timestream_role.arn
}

# === S3 OUTPUTS ===

output "rejected_data_bucket_name" {
  description = "Name of the S3 bucket for rejected data"
  value       = var.enable_rejected_data_location ? aws_s3_bucket.rejected_data[0].bucket : null
}

output "rejected_data_bucket_arn" {
  description = "ARN of the S3 bucket for rejected data"
  value       = var.enable_rejected_data_location ? aws_s3_bucket.rejected_data[0].arn : null
}

output "rejected_data_prefix" {
  description = "S3 prefix for rejected data objects"
  value       = var.rejected_data_prefix
}

# === CLOUDWATCH MONITORING OUTPUTS ===

output "ingestion_latency_alarm_name" {
  description = "Name of the CloudWatch alarm for ingestion latency"
  value       = var.enable_cloudwatch_alarms ? aws_cloudwatch_metric_alarm.ingestion_latency[0].alarm_name : null
}

output "query_latency_alarm_name" {
  description = "Name of the CloudWatch alarm for query latency"
  value       = var.enable_cloudwatch_alarms ? aws_cloudwatch_metric_alarm.query_latency[0].alarm_name : null
}

output "lambda_errors_alarm_name" {
  description = "Name of the CloudWatch alarm for Lambda errors"
  value       = var.enable_cloudwatch_alarms ? aws_cloudwatch_metric_alarm.lambda_errors[0].alarm_name : null
}

output "lambda_duration_alarm_name" {
  description = "Name of the CloudWatch alarm for Lambda duration"
  value       = var.enable_cloudwatch_alarms ? aws_cloudwatch_metric_alarm.lambda_duration[0].alarm_name : null
}

output "lambda_log_group_name" {
  description = "Name of the CloudWatch log group for Lambda function"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

# === CONFIGURATION OUTPUTS ===

output "environment" {
  description = "Environment name"
  value       = var.environment
}

output "project_name" {
  description = "Project name"
  value       = var.project_name
}

output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "aws_account_id" {
  description = "AWS account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

# === VPC ENDPOINT OUTPUTS ===

output "vpc_endpoint_id" {
  description = "ID of the Timestream VPC endpoint"
  value       = var.enable_vpc_endpoint ? aws_vpc_endpoint.timestream[0].id : null
}

output "vpc_endpoint_dns_entries" {
  description = "DNS entries for the Timestream VPC endpoint"
  value       = var.enable_vpc_endpoint ? aws_vpc_endpoint.timestream[0].dns_entry : null
}

# === SAMPLE QUERY EXAMPLES ===

output "sample_queries" {
  description = "Sample SQL queries for Timestream analytics"
  value = {
    latest_readings = "SELECT device_id, location, measure_name, measure_value::double, time FROM \"${aws_timestreamwrite_database.iot_database.database_name}\".\"${aws_timestreamwrite_table.sensor_data.table_name}\" WHERE time >= ago(1h) ORDER BY time DESC LIMIT 20"
    
    temperature_trends = "SELECT device_id, bin(time, 10m) as time_bucket, AVG(measure_value::double) as avg_temperature, MIN(measure_value::double) as min_temperature, MAX(measure_value::double) as max_temperature FROM \"${aws_timestreamwrite_database.iot_database.database_name}\".\"${aws_timestreamwrite_table.sensor_data.table_name}\" WHERE measure_name = 'temperature' AND time >= ago(1d) GROUP BY device_id, bin(time, 10m) ORDER BY time_bucket DESC"
    
    anomaly_detection = "WITH stats AS (SELECT device_id, AVG(measure_value::double) as avg_value, STDDEV(measure_value::double) as stddev_value FROM \"${aws_timestreamwrite_database.iot_database.database_name}\".\"${aws_timestreamwrite_table.sensor_data.table_name}\" WHERE measure_name = 'temperature' AND time >= ago(7d) GROUP BY device_id) SELECT s.device_id, s.time, s.measure_value::double, ABS(s.measure_value::double - stats.avg_value) / stats.stddev_value as z_score FROM \"${aws_timestreamwrite_database.iot_database.database_name}\".\"${aws_timestreamwrite_table.sensor_data.table_name}\" s JOIN stats ON s.device_id = stats.device_id WHERE s.measure_name = 'temperature' AND s.time >= ago(1d) AND ABS(s.measure_value::double - stats.avg_value) / stats.stddev_value > 2 ORDER BY z_score DESC"
    
    device_summary = "SELECT device_id, location, COUNT(*) as total_records, COUNT(DISTINCT measure_name) as sensor_types, MIN(time) as first_reading, MAX(time) as last_reading FROM \"${aws_timestreamwrite_database.iot_database.database_name}\".\"${aws_timestreamwrite_table.sensor_data.table_name}\" WHERE time >= ago(1d) GROUP BY device_id, location ORDER BY total_records DESC"
  }
}

# === TESTING OUTPUTS ===

output "test_commands" {
  description = "Commands for testing the deployed infrastructure"
  value = {
    test_lambda_invocation = "aws lambda invoke --function-name ${aws_lambda_function.data_ingestion.function_name} --payload '{\"device_id\":\"test-sensor-001\",\"location\":\"test-location\",\"sensors\":{\"temperature\":23.5,\"humidity\":68.0,\"pressure\":1015.0}}' --cli-binary-format raw-in-base64-out response.json"
    
    publish_iot_message = "aws iot-data publish --topic '${var.iot_topic_pattern}' --payload '{\"device_id\":\"iot-sensor-001\",\"location\":\"production-line-1\",\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"temperature\":26.5,\"humidity\":72.0,\"pressure\":1012.0}'"
    
    query_recent_data = "aws timestream-query query --query-string \"SELECT device_id, location, measure_name, measure_value::double, time FROM \\\"${aws_timestreamwrite_database.iot_database.database_name}\\\".\\\"${aws_timestreamwrite_table.sensor_data.table_name}\\\" WHERE time >= ago(1h) ORDER BY time DESC LIMIT 10\""
    
    check_cloudwatch_metrics = "aws cloudwatch get-metric-statistics --namespace 'AWS/Timestream' --metric-name 'SuccessfulRequestLatency' --dimensions Name=DatabaseName,Value=${aws_timestreamwrite_database.iot_database.database_name} Name=TableName,Value=${aws_timestreamwrite_table.sensor_data.table_name} Name=Operation,Value=WriteRecords --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) --end-time $(date -u +%Y-%m-%dT%H:%M:%S) --period 300 --statistics Average"
  }
}

# === COST ESTIMATION ===

output "estimated_monthly_costs" {
  description = "Estimated monthly costs for the solution (USD)"
  value = {
    timestream_memory_store = "Based on data ingestion volume and query frequency"
    timestream_magnetic_store = "~$0.03 per GB stored per month"
    lambda_execution = "Based on number of invocations and execution time"
    cloudwatch_logs = "~$0.50 per GB ingested"
    iot_core_messaging = "~$1.00 per million messages"
    s3_storage = "~$0.023 per GB per month for standard storage"
    note = "Actual costs depend on data volume, query patterns, and usage frequency"
  }
}

# === NEXT STEPS ===

output "next_steps" {
  description = "Recommended next steps after deployment"
  value = [
    "1. Test Lambda function with sample IoT data using the test_lambda_invocation command",
    "2. Publish test messages to IoT Core using the publish_iot_message command",
    "3. Verify data ingestion by running the query_recent_data command",
    "4. Set up Grafana or QuickSight for data visualization",
    "5. Configure SNS notifications for CloudWatch alarms",
    "6. Implement data quality checks and validation rules",
    "7. Set up automated data generation for testing",
    "8. Review and optimize retention policies based on usage patterns",
    "9. Implement cross-region replication for disaster recovery",
    "10. Add machine learning models for predictive analytics"
  ]
}