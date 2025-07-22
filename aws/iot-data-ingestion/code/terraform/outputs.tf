# outputs.tf - Output values for IoT data ingestion pipeline

# ============================================================================
# IoT Core Outputs
# ============================================================================

output "iot_endpoint" {
  description = "AWS IoT Core endpoint for device connections"
  value       = data.aws_iot_endpoint.iot_endpoint.endpoint_address
}

output "iot_thing_name" {
  description = "Name of the IoT Thing created"
  value       = aws_iot_thing.sensor_device.name
}

output "iot_thing_arn" {
  description = "ARN of the IoT Thing created"
  value       = aws_iot_thing.sensor_device.arn
}

output "iot_policy_name" {
  description = "Name of the IoT policy for device permissions"
  value       = aws_iot_policy.sensor_policy.name
}

output "iot_certificate_arn" {
  description = "ARN of the IoT certificate (if created)"
  value       = var.create_test_certificates ? aws_iot_certificate.device_cert[0].arn : null
}

output "iot_certificate_id" {
  description = "ID of the IoT certificate (if created)"
  value       = var.create_test_certificates ? aws_iot_certificate.device_cert[0].id : null
}

output "iot_certificate_pem" {
  description = "PEM-encoded certificate (if created) - SENSITIVE"
  value       = var.create_test_certificates ? aws_iot_certificate.device_cert[0].certificate_pem : null
  sensitive   = true
}

output "iot_private_key" {
  description = "Private key for the certificate (if created) - SENSITIVE"
  value       = var.create_test_certificates ? aws_iot_certificate.device_cert[0].private_key : null
  sensitive   = true
}

output "iot_public_key" {
  description = "Public key for the certificate (if created) - SENSITIVE"
  value       = var.create_test_certificates ? aws_iot_certificate.device_cert[0].public_key : null
  sensitive   = true
}

output "iot_topic_rule_arn" {
  description = "ARN of the IoT topic rule"
  value       = aws_iot_topic_rule.process_sensor_data.arn
}

output "mqtt_topics" {
  description = "MQTT topics that devices can publish to"
  value       = var.allowed_iot_topics
}

# ============================================================================
# DynamoDB Outputs
# ============================================================================

output "dynamodb_table_name" {
  description = "Name of the DynamoDB table storing sensor data"
  value       = aws_dynamodb_table.sensor_data.name
}

output "dynamodb_table_arn" {
  description = "ARN of the DynamoDB table"
  value       = aws_dynamodb_table.sensor_data.arn
}

output "dynamodb_table_stream_arn" {
  description = "ARN of the DynamoDB table stream (if enabled)"
  value       = aws_dynamodb_table.sensor_data.stream_arn
}

# ============================================================================
# Lambda Function Outputs
# ============================================================================

output "lambda_function_name" {
  description = "Name of the Lambda function processing IoT data"
  value       = aws_lambda_function.iot_processor.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function"
  value       = aws_lambda_function.iot_processor.arn
}

output "lambda_function_invoke_arn" {
  description = "Invoke ARN of the Lambda function"
  value       = aws_lambda_function.iot_processor.invoke_arn
}

output "lambda_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_role.arn
}

output "lambda_log_group_name" {
  description = "Name of the CloudWatch log group for Lambda"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

# ============================================================================
# SNS Outputs
# ============================================================================

output "sns_topic_arn" {
  description = "ARN of the SNS topic for alerts"
  value       = aws_sns_topic.iot_alerts.arn
}

output "sns_topic_name" {
  description = "Name of the SNS topic"
  value       = aws_sns_topic.iot_alerts.name
}

output "sns_subscription_arn" {
  description = "ARN of the SNS email subscription (if created)"
  value       = var.sns_email_endpoint != "" ? aws_sns_topic_subscription.email_alerts[0].arn : null
}

# ============================================================================
# CloudWatch Outputs
# ============================================================================

output "cloudwatch_dashboard_url" {
  description = "URL to the CloudWatch dashboard"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.iot_dashboard.dashboard_name}"
}

output "cloudwatch_dashboard_name" {
  description = "Name of the CloudWatch dashboard"
  value       = aws_cloudwatch_dashboard.iot_dashboard.dashboard_name
}

# ============================================================================
# Security Outputs
# ============================================================================

output "kms_key_ids" {
  description = "Map of KMS key IDs used for encryption"
  value = {
    dynamodb = aws_kms_key.dynamodb_key.id
    sns      = aws_kms_key.sns_key.id
    lambda   = aws_kms_key.lambda_key.id
  }
}

output "kms_key_aliases" {
  description = "Map of KMS key aliases"
  value = {
    dynamodb = aws_kms_alias.dynamodb_key_alias.name
    sns      = aws_kms_alias.sns_key_alias.name
    lambda   = aws_kms_alias.lambda_key_alias.name
  }
}

# ============================================================================
# Testing and Configuration Outputs
# ============================================================================

output "test_commands" {
  description = "Commands to test the IoT pipeline"
  value = {
    publish_test_message = "aws iot-data publish --topic 'topic/sensor/data' --payload '{\"deviceId\":\"${aws_iot_thing.sensor_device.name}\",\"timestamp\":${timestamp()},\"temperature\":25.5,\"humidity\":60.2,\"location\":\"sensor-room-1\"}'"
    query_dynamodb      = "aws dynamodb scan --table-name ${aws_dynamodb_table.sensor_data.name} --max-items 5"
    view_lambda_logs    = "aws logs describe-log-streams --log-group-name ${aws_cloudwatch_log_group.lambda_logs.name}"
  }
}

output "configuration_summary" {
  description = "Summary of key configuration values"
  value = {
    aws_region            = data.aws_region.current.name
    environment           = var.environment
    project_name          = var.project_name
    temperature_threshold = var.temperature_threshold
    lambda_timeout        = var.lambda_timeout
    dynamodb_billing_mode = var.dynamodb_billing_mode
    certificates_created  = var.create_test_certificates
  }
}

output "resource_names" {
  description = "Map of all created resource names for reference"
  value = {
    iot_thing           = aws_iot_thing.sensor_device.name
    iot_policy          = aws_iot_policy.sensor_policy.name
    iot_rule            = aws_iot_topic_rule.process_sensor_data.name
    dynamodb_table      = aws_dynamodb_table.sensor_data.name
    lambda_function     = aws_lambda_function.iot_processor.function_name
    sns_topic           = aws_sns_topic.iot_alerts.name
    cloudwatch_dashboard = aws_cloudwatch_dashboard.iot_dashboard.dashboard_name
  }
}

# ============================================================================
# Connection Information
# ============================================================================

output "connection_info" {
  description = "Information needed to connect IoT devices"
  value = {
    mqtt_endpoint    = data.aws_iot_endpoint.iot_endpoint.endpoint_address
    mqtt_port        = 8883
    mqtt_port_websocket = 443
    ca_certificate_url = "https://www.amazontrust.com/repository/AmazonRootCA1.pem"
    client_id        = aws_iot_thing.sensor_device.name
    topic_prefix     = "topic/sensor/"
  }
}

# Data source for IoT endpoint
data "aws_iot_endpoint" "iot_endpoint" {
  endpoint_type = "iot:Data-ATS"
}