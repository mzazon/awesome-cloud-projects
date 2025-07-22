# Outputs for IoT Device Shadows State Management Infrastructure

# ============================================================================
# IoT Core Outputs
# ============================================================================

output "iot_thing_name" {
  description = "Name of the created IoT Thing"
  value       = aws_iot_thing.smart_thermostat.name
}

output "iot_thing_arn" {
  description = "ARN of the created IoT Thing"
  value       = aws_iot_thing.smart_thermostat.arn
}

output "iot_thing_type_name" {
  description = "Name of the IoT Thing Type"
  value       = aws_iot_thing_type.thermostat.name
}

output "device_certificate_arn" {
  description = "ARN of the device certificate"
  value       = aws_iot_certificate.device_cert.arn
}

output "device_certificate_id" {
  description = "ID of the device certificate"
  value       = aws_iot_certificate.device_cert.id
}

output "device_certificate_pem" {
  description = "Certificate PEM (use for device authentication)"
  value       = aws_iot_certificate.device_cert.certificate_pem
  sensitive   = true
}

output "device_private_key" {
  description = "Device private key (use for device authentication)"
  value       = aws_iot_certificate.device_cert.private_key
  sensitive   = true
}

output "device_public_key" {
  description = "Device public key"
  value       = aws_iot_certificate.device_cert.public_key
  sensitive   = true
}

output "iot_policy_name" {
  description = "Name of the IoT policy for device permissions"
  value       = aws_iot_policy.device_policy.name
}

output "iot_policy_arn" {
  description = "ARN of the IoT policy for device permissions"
  value       = aws_iot_policy.device_policy.arn
}

# ============================================================================
# IoT Endpoints
# ============================================================================

output "iot_endpoint_address" {
  description = "IoT Core endpoint address for device connections"
  value       = data.aws_iot_endpoint.iot_endpoint.endpoint_address
}

output "iot_shadow_endpoint" {
  description = "IoT Device Shadow endpoint"
  value       = "https://${data.aws_iot_endpoint.iot_endpoint.endpoint_address}"
}

output "mqtt_endpoint" {
  description = "MQTT endpoint for device connections"
  value       = data.aws_iot_endpoint.iot_endpoint.endpoint_address
}

# ============================================================================
# Lambda Function Outputs
# ============================================================================

output "lambda_function_name" {
  description = "Name of the Lambda function processing shadow updates"
  value       = aws_lambda_function.shadow_processor.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function processing shadow updates"
  value       = aws_lambda_function.shadow_processor.arn
}

output "lambda_function_invoke_arn" {
  description = "Invoke ARN of the Lambda function"
  value       = aws_lambda_function.shadow_processor.invoke_arn
}

output "lambda_log_group_name" {
  description = "CloudWatch Log Group name for Lambda function"
  value       = var.enable_cloudwatch_logs_retention ? aws_cloudwatch_log_group.lambda_logs[0].name : "/aws/lambda/${local.lambda_function}"
}

# ============================================================================
# DynamoDB Outputs
# ============================================================================

output "dynamodb_table_name" {
  description = "Name of the DynamoDB table storing device state history"
  value       = aws_dynamodb_table.device_state_history.name
}

output "dynamodb_table_arn" {
  description = "ARN of the DynamoDB table storing device state history"
  value       = aws_dynamodb_table.device_state_history.arn
}

output "dynamodb_table_id" {
  description = "ID of the DynamoDB table"
  value       = aws_dynamodb_table.device_state_history.id
}

# ============================================================================
# IoT Rule Outputs
# ============================================================================

output "iot_rule_name" {
  description = "Name of the IoT Topic Rule processing shadow updates"
  value       = aws_iot_topic_rule.shadow_update_rule.name
}

output "iot_rule_arn" {
  description = "ARN of the IoT Topic Rule processing shadow updates"
  value       = aws_iot_topic_rule.shadow_update_rule.arn
}

output "iot_rule_sql" {
  description = "SQL query used by the IoT Topic Rule"
  value       = aws_iot_topic_rule.shadow_update_rule.sql
}

# ============================================================================
# Shadow Management Outputs
# ============================================================================

output "shadow_update_topic" {
  description = "MQTT topic for updating device shadow"
  value       = "$aws/things/${aws_iot_thing.smart_thermostat.name}/shadow/update"
}

output "shadow_get_topic" {
  description = "MQTT topic for getting device shadow"
  value       = "$aws/things/${aws_iot_thing.smart_thermostat.name}/shadow/get"
}

output "shadow_delta_topic" {
  description = "MQTT topic for shadow delta messages"
  value       = "$aws/things/${aws_iot_thing.smart_thermostat.name}/shadow/update/delta"
}

output "shadow_accepted_topic" {
  description = "MQTT topic for shadow accepted updates"
  value       = "$aws/things/${aws_iot_thing.smart_thermostat.name}/shadow/update/accepted"
}

output "shadow_rejected_topic" {
  description = "MQTT topic for shadow rejected updates"
  value       = "$aws/things/${aws_iot_thing.smart_thermostat.name}/shadow/update/rejected"
}

# ============================================================================
# AWS CLI Commands for Testing
# ============================================================================

output "cli_update_shadow_command" {
  description = "AWS CLI command to update device shadow"
  value = "aws iot-data update-thing-shadow --thing-name ${aws_iot_thing.smart_thermostat.name} --payload '{\"state\":{\"desired\":{\"target_temperature\":25.0,\"hvac_mode\":\"cool\"}}}' shadow-response.json"
}

output "cli_get_shadow_command" {
  description = "AWS CLI command to get device shadow"
  value = "aws iot-data get-thing-shadow --thing-name ${aws_iot_thing.smart_thermostat.name} shadow-current.json"
}

output "cli_query_history_command" {
  description = "AWS CLI command to query device state history"
  value = "aws dynamodb query --table-name ${aws_dynamodb_table.device_state_history.name} --key-condition-expression 'ThingName = :thingName' --expression-attribute-values '{\":thingName\":{\"S\":\"${aws_iot_thing.smart_thermostat.name}\"}}'"
}

# ============================================================================
# Connection Information
# ============================================================================

output "device_connection_info" {
  description = "Information needed for device connection"
  value = {
    thing_name     = aws_iot_thing.smart_thermostat.name
    endpoint       = data.aws_iot_endpoint.iot_endpoint.endpoint_address
    certificate_id = aws_iot_certificate.device_cert.id
    policy_name    = aws_iot_policy.device_policy.name
  }
}

output "shadow_topics" {
  description = "All shadow-related MQTT topics for the device"
  value = {
    update    = "$aws/things/${aws_iot_thing.smart_thermostat.name}/shadow/update"
    get       = "$aws/things/${aws_iot_thing.smart_thermostat.name}/shadow/get"
    delta     = "$aws/things/${aws_iot_thing.smart_thermostat.name}/shadow/update/delta"
    accepted  = "$aws/things/${aws_iot_thing.smart_thermostat.name}/shadow/update/accepted"
    rejected  = "$aws/things/${aws_iot_thing.smart_thermostat.name}/shadow/update/rejected"
  }
}

# ============================================================================
# Resource Identifiers
# ============================================================================

output "resource_identifiers" {
  description = "Identifiers for all created resources"
  value = {
    random_suffix        = local.random_suffix
    thing_name          = local.thing_name
    policy_name         = local.policy_name
    rule_name           = local.rule_name
    lambda_function     = local.lambda_function
    table_name          = local.table_name
  }
}