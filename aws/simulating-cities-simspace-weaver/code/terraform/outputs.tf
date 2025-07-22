# Outputs for Smart City Digital Twins Infrastructure

#########################################
# General Infrastructure Information
#########################################

output "project_name" {
  description = "The project name used for resource naming"
  value       = local.project_name
}

output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "aws_account_id" {
  description = "AWS account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

#########################################
# DynamoDB Outputs
#########################################

output "dynamodb_table_name" {
  description = "Name of the DynamoDB table storing sensor data"
  value       = aws_dynamodb_table.sensor_data.name
}

output "dynamodb_table_arn" {
  description = "ARN of the DynamoDB table"
  value       = aws_dynamodb_table.sensor_data.arn
}

output "dynamodb_stream_arn" {
  description = "ARN of the DynamoDB stream"
  value       = aws_dynamodb_table.sensor_data.stream_arn
}

output "dynamodb_table_id" {
  description = "ID of the DynamoDB table"
  value       = aws_dynamodb_table.sensor_data.id
}

#########################################
# Lambda Function Outputs
#########################################

output "sensor_processor_function_name" {
  description = "Name of the sensor data processor Lambda function"
  value       = aws_lambda_function.sensor_processor.function_name
}

output "sensor_processor_function_arn" {
  description = "ARN of the sensor data processor Lambda function"
  value       = aws_lambda_function.sensor_processor.arn
}

output "stream_processor_function_name" {
  description = "Name of the stream processor Lambda function"
  value       = aws_lambda_function.stream_processor.function_name
}

output "stream_processor_function_arn" {
  description = "ARN of the stream processor Lambda function"
  value       = aws_lambda_function.stream_processor.arn
}

output "analytics_processor_function_name" {
  description = "Name of the analytics processor Lambda function"
  value       = aws_lambda_function.analytics_processor.function_name
}

output "analytics_processor_function_arn" {
  description = "ARN of the analytics processor Lambda function"
  value       = aws_lambda_function.analytics_processor.arn
}

#########################################
# S3 Bucket Outputs
#########################################

output "simulation_artifacts_bucket_name" {
  description = "Name of the S3 bucket for simulation artifacts"
  value       = aws_s3_bucket.simulation_artifacts.id
}

output "simulation_artifacts_bucket_arn" {
  description = "ARN of the S3 bucket for simulation artifacts"
  value       = aws_s3_bucket.simulation_artifacts.arn
}

output "simulation_artifacts_bucket_domain_name" {
  description = "Domain name of the S3 bucket"
  value       = aws_s3_bucket.simulation_artifacts.bucket_domain_name
}

output "simulation_schema_s3_key" {
  description = "S3 key for the simulation schema file"
  value       = aws_s3_object.simulation_schema.key
}

#########################################
# IoT Core Outputs
#########################################

output "iot_thing_group_name" {
  description = "Name of the IoT Thing Group for smart city sensors"
  value       = aws_iot_thing_group.smart_city_sensors.name
}

output "iot_thing_group_arn" {
  description = "ARN of the IoT Thing Group"
  value       = aws_iot_thing_group.smart_city_sensors.arn
}

output "iot_policy_name" {
  description = "Name of the IoT policy for sensor devices"
  value       = aws_iot_policy.sensor_policy.name
}

output "iot_policy_arn" {
  description = "ARN of the IoT policy"
  value       = aws_iot_policy.sensor_policy.arn
}

output "iot_topic_rule_name" {
  description = "Name of the IoT topic rule for data processing"
  value       = aws_iot_topic_rule.sensor_data_processing.name
}

output "iot_topic_rule_arn" {
  description = "ARN of the IoT topic rule"
  value       = aws_iot_topic_rule.sensor_data_processing.arn
}

output "sample_sensor_thing_name" {
  description = "Name of the sample traffic sensor thing"
  value       = aws_iot_thing.sample_traffic_sensor.name
}

output "sample_sensor_thing_arn" {
  description = "ARN of the sample traffic sensor thing"
  value       = aws_iot_thing.sample_traffic_sensor.arn
}

#########################################
# IAM Role Outputs
#########################################

output "lambda_execution_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_execution.arn
}

output "lambda_execution_role_name" {
  description = "Name of the Lambda execution role"
  value       = aws_iam_role.lambda_execution.name
}

output "analytics_lambda_execution_role_arn" {
  description = "ARN of the analytics Lambda execution role"
  value       = aws_iam_role.analytics_lambda_execution.arn
}

output "iot_rule_execution_role_arn" {
  description = "ARN of the IoT rule execution role"
  value       = aws_iam_role.iot_rule_execution.arn
}

#########################################
# CloudWatch Outputs
#########################################

output "cloudwatch_log_groups" {
  description = "CloudWatch log groups created for the solution"
  value = {
    sensor_processor   = aws_cloudwatch_log_group.sensor_processor.name
    stream_processor   = aws_cloudwatch_log_group.stream_processor.name
    analytics_processor = aws_cloudwatch_log_group.analytics_processor.name
    iot_errors         = aws_cloudwatch_log_group.iot_errors.name
  }
}

output "cloudwatch_alarms" {
  description = "CloudWatch alarms created for monitoring"
  value = {
    sensor_processor_errors = aws_cloudwatch_metric_alarm.sensor_processor_errors.alarm_name
    dynamodb_throttles     = aws_cloudwatch_metric_alarm.dynamodb_throttles.alarm_name
  }
}

#########################################
# SNS Topic Outputs
#########################################

output "alerts_topic_arn" {
  description = "ARN of the SNS topic for alerts"
  value       = aws_sns_topic.alerts.arn
}

output "alerts_topic_name" {
  description = "Name of the SNS topic for alerts"
  value       = aws_sns_topic.alerts.name
}

#########################################
# IoT Endpoint Information
#########################################

data "aws_iot_endpoint" "iot_endpoint" {
  endpoint_type = "iot:Data-ATS"
}

output "iot_endpoint_url" {
  description = "IoT Core endpoint URL for device connections"
  value       = data.aws_iot_endpoint.iot_endpoint.endpoint_url
}

#########################################
# Event Source Mapping Outputs
#########################################

output "dynamodb_stream_event_source_mapping_uuid" {
  description = "UUID of the DynamoDB stream event source mapping"
  value       = aws_lambda_event_source_mapping.dynamodb_stream.uuid
}

#########################################
# Testing and Validation Outputs
#########################################

output "iot_test_commands" {
  description = "AWS CLI commands for testing IoT data ingestion"
  value = {
    publish_test_message = "aws iot-data publish --topic 'smartcity/sensors/${aws_iot_thing.sample_traffic_sensor.name}/data' --payload '{\"sensor_id\":\"${aws_iot_thing.sample_traffic_sensor.name}\",\"sensor_type\":\"traffic\",\"location\":{\"lat\":40.7589,\"lon\":-73.9851},\"data\":{\"vehicle_count\":15,\"average_speed\":35},\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}'"
    
    check_dynamodb_data = "aws dynamodb scan --table-name ${aws_dynamodb_table.sensor_data.name} --limit 5"
    
    invoke_analytics = "aws lambda invoke --function-name ${aws_lambda_function.analytics_processor.function_name} --payload '{\"type\":\"traffic_summary\",\"time_range\":\"24h\"}' response.json && cat response.json"
  }
}

output "monitoring_urls" {
  description = "AWS Console URLs for monitoring the solution"
  value = {
    dynamodb_table = "https://console.aws.amazon.com/dynamodb/home?region=${data.aws_region.current.name}#table?name=${aws_dynamodb_table.sensor_data.name}"
    
    lambda_functions = "https://console.aws.amazon.com/lambda/home?region=${data.aws_region.current.name}#/functions"
    
    iot_console = "https://console.aws.amazon.com/iot/home?region=${data.aws_region.current.name}#/thingGroupHub"
    
    cloudwatch_dashboards = "https://console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:"
    
    s3_bucket = "https://console.aws.amazon.com/s3/buckets/${aws_s3_bucket.simulation_artifacts.id}/?region=${data.aws_region.current.name}"
  }
}

#########################################
# Cost and Resource Information
#########################################

output "estimated_monthly_costs" {
  description = "Estimated monthly costs for key resources (USD)"
  value = {
    note = "Costs are estimates based on moderate usage patterns"
    dynamodb_table = "Pay-per-request pricing based on read/write units"
    lambda_functions = "Based on number of invocations and execution time"
    s3_storage = "Based on stored data volume and requests"
    iot_core = "Based on message volume and device connections"
    cloudwatch = "Based on log ingestion and metric volume"
  }
}

output "resource_counts" {
  description = "Count of resources created by this deployment"
  value = {
    lambda_functions    = 3
    dynamodb_tables    = 1
    s3_buckets         = 1
    iot_things         = 1
    iot_thing_groups   = 1
    iot_policies       = 1
    iot_topic_rules    = 1
    iam_roles          = 3
    cloudwatch_alarms  = 2
    sns_topics         = 1
  }
}

#########################################
# Configuration Information
#########################################

output "deployment_configuration" {
  description = "Key configuration settings for the deployment"
  value = {
    environment               = var.environment
    log_retention_days       = var.log_retention_days
    artifact_retention_days  = var.artifact_retention_days
    point_in_time_recovery   = var.enable_point_in_time_recovery
    x_ray_tracing           = var.enable_x_ray_tracing
    detailed_monitoring     = var.enable_detailed_monitoring
  }
}

output "sensor_configuration" {
  description = "Sensor and IoT configuration"
  value = {
    supported_sensor_types = var.sensor_types
    city_zones            = var.city_zones
    iot_message_routing   = var.iot_message_routing
  }
}

#########################################
# Next Steps Information
#########################################

output "next_steps" {
  description = "Recommended next steps after deployment"
  value = {
    "1_test_iot_ingestion" = "Use the IoT test commands to verify data ingestion pipeline"
    "2_configure_devices" = "Create and configure additional IoT devices using the thing group and policy"
    "3_setup_monitoring" = "Configure CloudWatch dashboards and SNS subscriptions for alerts"
    "4_deploy_simulation" = "Note: SimSpace Weaver will be discontinued in May 2026. Consider alternative simulation platforms"
    "5_scale_deployment" = "Add more sensor types and city zones as needed"
    "6_security_review" = "Review IAM policies and enable additional security features for production use"
  }
}

#########################################
# Important Notices
#########################################

output "important_notices" {
  description = "Important information about this deployment"
  value = {
    simspace_weaver_deprecation = "AWS SimSpace Weaver will reach end of support on May 20, 2026. Plan for alternative simulation platforms."
    cost_awareness = "This deployment uses pay-per-use services. Monitor costs through AWS Cost Explorer."
    security_considerations = "Review and enhance security settings before production deployment."
    cleanup_instructions = "Use 'terraform destroy' to remove all resources and avoid ongoing charges."
  }
}