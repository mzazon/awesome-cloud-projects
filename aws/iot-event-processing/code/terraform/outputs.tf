# outputs.tf - Output values for AWS IoT Rules Engine Event Processing

# DynamoDB Table Information
output "dynamodb_table_name" {
  description = "Name of the DynamoDB table for telemetry data"
  value       = aws_dynamodb_table.telemetry_table.name
}

output "dynamodb_table_arn" {
  description = "ARN of the DynamoDB table"
  value       = aws_dynamodb_table.telemetry_table.arn
}

output "dynamodb_table_stream_arn" {
  description = "ARN of the DynamoDB table stream (if enabled)"
  value       = aws_dynamodb_table.telemetry_table.stream_arn
}

# SNS Topic Information
output "sns_topic_name" {
  description = "Name of the SNS topic for alerts"
  value       = aws_sns_topic.alerts_topic.name
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for alerts"
  value       = aws_sns_topic.alerts_topic.arn
}

# Lambda Function Information
output "lambda_function_name" {
  description = "Name of the Lambda function for event processing"
  value       = aws_lambda_function.event_processor.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function"
  value       = aws_lambda_function.event_processor.arn
}

output "lambda_function_invoke_arn" {
  description = "Invoke ARN of the Lambda function"
  value       = aws_lambda_function.event_processor.invoke_arn
}

# IAM Role Information
output "iot_rules_role_name" {
  description = "Name of the IAM role for IoT Rules Engine"
  value       = aws_iam_role.iot_rules_role.name
}

output "iot_rules_role_arn" {
  description = "ARN of the IAM role for IoT Rules Engine"
  value       = aws_iam_role.iot_rules_role.arn
}

output "lambda_execution_role_name" {
  description = "Name of the Lambda execution role"
  value       = aws_iam_role.lambda_execution_role.name
}

output "lambda_execution_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_execution_role.arn
}

# IoT Rules Information
output "temperature_alert_rule_name" {
  description = "Name of the temperature alert rule"
  value       = aws_iot_topic_rule.temperature_alert_rule.name
}

output "temperature_alert_rule_arn" {
  description = "ARN of the temperature alert rule"
  value       = aws_iot_topic_rule.temperature_alert_rule.arn
}

output "motor_status_rule_name" {
  description = "Name of the motor status rule"
  value       = aws_iot_topic_rule.motor_status_rule.name
}

output "motor_status_rule_arn" {
  description = "ARN of the motor status rule"
  value       = aws_iot_topic_rule.motor_status_rule.arn
}

output "security_event_rule_name" {
  description = "Name of the security event rule"
  value       = aws_iot_topic_rule.security_event_rule.name
}

output "security_event_rule_arn" {
  description = "ARN of the security event rule"
  value       = aws_iot_topic_rule.security_event_rule.arn
}

output "data_archival_rule_name" {
  description = "Name of the data archival rule"
  value       = aws_iot_topic_rule.data_archival_rule.name
}

output "data_archival_rule_arn" {
  description = "ARN of the data archival rule"
  value       = aws_iot_topic_rule.data_archival_rule.arn
}

# CloudWatch Log Groups
output "iot_rules_log_group_name" {
  description = "Name of the IoT Rules CloudWatch log group"
  value       = aws_cloudwatch_log_group.iot_rules_logs.name
}

output "lambda_log_group_name" {
  description = "Name of the Lambda CloudWatch log group"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

# IoT Thing Information (if created)
output "iot_thing_name" {
  description = "Name of the IoT thing for testing (if created)"
  value       = var.create_test_thing ? aws_iot_thing.test_sensor[0].name : null
}

output "iot_thing_arn" {
  description = "ARN of the IoT thing for testing (if created)"
  value       = var.create_test_thing ? aws_iot_thing.test_sensor[0].arn : null
}

output "iot_thing_type_name" {
  description = "Name of the IoT thing type (if created)"
  value       = var.create_test_thing ? aws_iot_thing_type.sensor_type[0].name : null
}

output "iot_policy_name" {
  description = "Name of the IoT policy (if created)"
  value       = var.create_test_thing ? aws_iot_policy.device_policy[0].name : null
}

# AWS Account and Region Information
output "aws_account_id" {
  description = "AWS account ID"
  value       = data.aws_caller_identity.current.account_id
}

output "aws_region" {
  description = "AWS region"
  value       = data.aws_region.current.name
}

# Resource Name Prefix
output "resource_name_prefix" {
  description = "Prefix used for resource naming"
  value       = local.name_prefix
}

# Testing Information
output "mqtt_test_topics" {
  description = "MQTT topics for testing the IoT rules"
  value = {
    temperature_topic = "factory/temperature"
    motor_topic      = "factory/motors"
    security_topic   = "factory/security"
    general_topic    = "factory/+"
  }
}

output "sample_payloads" {
  description = "Sample JSON payloads for testing"
  value = {
    temperature_high = jsonencode({
      deviceId    = "temp-sensor-01"
      temperature = 80
      location    = "production-floor"
    })
    motor_error = jsonencode({
      deviceId     = "motor-ctrl-02"
      motorStatus  = "error"
      vibration    = 6.5
      location     = "assembly-line"
    })
    security_intrusion = jsonencode({
      deviceId  = "security-cam-03"
      eventType = "intrusion"
      severity  = "high"
      location  = "entrance-door"
    })
  }
}

# Monitoring and Alerting
output "cloudwatch_dashboard_url" {
  description = "URL to view CloudWatch dashboards"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:"
}

output "iot_core_console_url" {
  description = "URL to IoT Core console"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/iot/home?region=${data.aws_region.current.name}#/rulehub"
}

# Configuration Summary
output "configuration_summary" {
  description = "Summary of the deployed configuration"
  value = {
    temperature_threshold    = var.temperature_threshold
    vibration_threshold     = var.vibration_threshold
    data_archival_enabled   = var.enable_data_archival
    test_thing_created      = var.create_test_thing
    alert_email_configured  = var.alert_email != ""
    log_retention_days      = var.log_retention_days
    environment            = var.environment
  }
}

# Cost Optimization Information
output "cost_optimization_tips" {
  description = "Tips for cost optimization"
  value = {
    dynamodb_billing_mode = "PAY_PER_REQUEST - suitable for variable workloads"
    lambda_pricing       = "Pay per invocation and duration"
    cloudwatch_logs      = "Review log retention periods regularly"
    sns_pricing         = "Pay per message published and delivered"
    iot_rules_pricing   = "Pay per rule execution and message processed"
  }
}

# Security Information
output "security_recommendations" {
  description = "Security best practices implemented"
  value = {
    iam_least_privilege    = "IAM roles follow least privilege principle"
    encryption_at_rest     = "DynamoDB and logs encrypted at rest by default"
    vpc_recommendations    = "Consider VPC endpoints for enhanced security"
    device_authentication = "Use X.509 certificates for device authentication"
    policy_versioning     = "IoT policies support versioning for updates"
  }
}

# Troubleshooting Information
output "troubleshooting_resources" {
  description = "Resources for troubleshooting"
  value = {
    iot_rules_logs      = "/aws/iot/rules log group"
    lambda_logs         = "/aws/lambda/${aws_lambda_function.event_processor.function_name} log group"
    cloudwatch_metrics  = "AWS/IoT and AWS/Lambda namespaces"
    x_ray_tracing      = "Enable X-Ray tracing for Lambda function"
    iot_device_advisor = "Use IoT Device Advisor for device testing"
  }
}