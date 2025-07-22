# Output values for the IoT Device Management Infrastructure
# These outputs provide essential information for device connection and testing

# ============================================================================
# IoT Core Resources
# ============================================================================

output "iot_thing_name" {
  description = "Name of the created IoT Thing (device)"
  value       = aws_iot_thing.temperature_sensor.name
}

output "iot_thing_arn" {
  description = "ARN of the created IoT Thing"
  value       = aws_iot_thing.temperature_sensor.arn
}

output "iot_thing_type_name" {
  description = "Name of the IoT Thing Type"
  value       = aws_iot_thing_type.temperature_sensor.name
}

output "iot_thing_type_arn" {
  description = "ARN of the IoT Thing Type"
  value       = aws_iot_thing_type.temperature_sensor.arn
}

# ============================================================================
# Certificate Information
# ============================================================================

output "device_certificate_arn" {
  description = "ARN of the device certificate"
  value       = aws_iot_certificate.device_cert.arn
  sensitive   = true
}

output "device_certificate_id" {
  description = "ID of the device certificate"
  value       = aws_iot_certificate.device_cert.id
  sensitive   = true
}

output "device_certificate_pem" {
  description = "PEM-encoded certificate for device authentication"
  value       = aws_iot_certificate.device_cert.certificate_pem
  sensitive   = true
}

output "device_private_key" {
  description = "Private key for device authentication"
  value       = aws_iot_certificate.device_cert.private_key
  sensitive   = true
}

output "device_public_key" {
  description = "Public key for device authentication"
  value       = aws_iot_certificate.device_cert.public_key
  sensitive   = true
}

# ============================================================================
# IoT Policy
# ============================================================================

output "iot_policy_name" {
  description = "Name of the IoT policy"
  value       = aws_iot_policy.device_policy.name
}

output "iot_policy_arn" {
  description = "ARN of the IoT policy"
  value       = aws_iot_policy.device_policy.arn
}

# ============================================================================
# Lambda Function
# ============================================================================

output "lambda_function_name" {
  description = "Name of the Lambda function processing IoT data"
  value       = aws_lambda_function.iot_data_processor.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function"
  value       = aws_lambda_function.iot_data_processor.arn
}

output "lambda_function_invoke_arn" {
  description = "Invoke ARN of the Lambda function"
  value       = aws_lambda_function.iot_data_processor.invoke_arn
}

# ============================================================================
# IoT Rules Engine
# ============================================================================

output "iot_topic_rule_name" {
  description = "Name of the IoT topic rule"
  value       = aws_iot_topic_rule.sensor_data_rule.name
}

output "iot_topic_rule_arn" {
  description = "ARN of the IoT topic rule"
  value       = aws_iot_topic_rule.sensor_data_rule.arn
}

output "iot_topic_rule_sql" {
  description = "SQL statement used by the IoT topic rule"
  value       = aws_iot_topic_rule.sensor_data_rule.sql
}

# ============================================================================
# AWS IoT Endpoints
# ============================================================================

output "iot_endpoint_address" {
  description = "AWS IoT Core endpoint address for device connections"
  value       = data.aws_iot_endpoint.iot_endpoint.endpoint_address
}

output "iot_endpoint_type" {
  description = "Type of the IoT endpoint"
  value       = data.aws_iot_endpoint.iot_endpoint.endpoint_type
}

# ============================================================================
# CloudWatch Resources
# ============================================================================

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for Lambda"
  value       = var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.lambda_logs[0].name : null
}

output "cloudwatch_dashboard_url" {
  description = "URL to the CloudWatch dashboard"
  value       = "https://console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.iot_dashboard.dashboard_name}"
}

# ============================================================================
# Connection Information
# ============================================================================

output "mqtt_topic_publish" {
  description = "MQTT topic where devices should publish data"
  value       = "sensor/temperature/${aws_iot_thing.temperature_sensor.name}"
}

output "mqtt_topic_pattern" {
  description = "MQTT topic pattern monitored by the IoT rule"
  value       = "sensor/temperature/+"
}

output "device_shadow_url" {
  description = "URL for device shadow operations"
  value       = "https://iot.${var.aws_region}.amazonaws.com/things/${aws_iot_thing.temperature_sensor.name}/shadow"
}

# ============================================================================
# Testing Commands
# ============================================================================

output "test_publish_command" {
  description = "AWS CLI command to test data publishing"
  value = <<-EOT
    aws iot-data publish \
      --topic sensor/temperature/${aws_iot_thing.temperature_sensor.name} \
      --payload '{"temperature": 85.5, "humidity": 65, "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)'", "device": "${aws_iot_thing.temperature_sensor.name}"}'
  EOT
}

output "shadow_get_command" {
  description = "AWS CLI command to get device shadow"
  value = <<-EOT
    aws iot-data get-thing-shadow \
      --thing-name ${aws_iot_thing.temperature_sensor.name} \
      shadow.json && cat shadow.json
  EOT
}

output "lambda_logs_command" {
  description = "AWS CLI command to view Lambda function logs"
  value = <<-EOT
    aws logs describe-log-streams \
      --log-group-name /aws/lambda/${aws_lambda_function.iot_data_processor.function_name} \
      --order-by LastEventTime --descending --max-items 1
  EOT
}

# ============================================================================
# Resource Information Summary
# ============================================================================

output "deployment_summary" {
  description = "Summary of deployed resources"
  value = {
    region                = var.aws_region
    environment          = var.environment
    project_name         = var.project_name
    iot_thing_name       = aws_iot_thing.temperature_sensor.name
    lambda_function_name = aws_lambda_function.iot_data_processor.function_name
    iot_rule_name        = aws_iot_topic_rule.sensor_data_rule.name
    resource_suffix      = random_string.suffix.result
    deployment_time      = timestamp()
  }
}

# ============================================================================
# Data Source for IoT Endpoint
# ============================================================================

data "aws_iot_endpoint" "iot_endpoint" {
  endpoint_type = "iot:Data-ATS"
}