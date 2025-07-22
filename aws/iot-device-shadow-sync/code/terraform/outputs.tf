# IoT Thing Information
output "thing_name" {
  description = "Name of the created IoT Thing"
  value       = aws_iot_thing.demo_device.name
}

output "thing_arn" {
  description = "ARN of the created IoT Thing"
  value       = aws_iot_thing.demo_device.arn
}

output "thing_type_name" {
  description = "Name of the IoT Thing Type"
  value       = aws_iot_thing_type.demo_device.name
}

# Certificate Information
output "certificate_arn" {
  description = "ARN of the device certificate"
  value       = aws_iot_certificate.demo_device.arn
}

output "certificate_id" {
  description = "ID of the device certificate"
  value       = aws_iot_certificate.demo_device.id
}

output "certificate_pem" {
  description = "PEM encoded certificate"
  value       = aws_iot_certificate.demo_device.certificate_pem
  sensitive   = true
}

output "private_key" {
  description = "Private key for the certificate"
  value       = aws_iot_certificate.demo_device.private_key
  sensitive   = true
}

output "public_key" {
  description = "Public key for the certificate"
  value       = aws_iot_certificate.demo_device.public_key
  sensitive   = true
}

# Lambda Functions
output "conflict_resolver_function_name" {
  description = "Name of the conflict resolver Lambda function"
  value       = aws_lambda_function.conflict_resolver.function_name
}

output "conflict_resolver_function_arn" {
  description = "ARN of the conflict resolver Lambda function"
  value       = aws_lambda_function.conflict_resolver.arn
}

output "sync_manager_function_name" {
  description = "Name of the sync manager Lambda function"
  value       = aws_lambda_function.sync_manager.function_name
}

output "sync_manager_function_arn" {
  description = "ARN of the sync manager Lambda function"
  value       = aws_lambda_function.sync_manager.arn
}

# DynamoDB Tables
output "shadow_history_table_name" {
  description = "Name of the shadow history DynamoDB table"
  value       = aws_dynamodb_table.shadow_history.name
}

output "shadow_history_table_arn" {
  description = "ARN of the shadow history DynamoDB table"
  value       = aws_dynamodb_table.shadow_history.arn
}

output "device_config_table_name" {
  description = "Name of the device configuration DynamoDB table"
  value       = aws_dynamodb_table.device_config.name
}

output "device_config_table_arn" {
  description = "ARN of the device configuration DynamoDB table"
  value       = aws_dynamodb_table.device_config.arn
}

output "sync_metrics_table_name" {
  description = "Name of the sync metrics DynamoDB table"
  value       = aws_dynamodb_table.sync_metrics.name
}

output "sync_metrics_table_arn" {
  description = "ARN of the sync metrics DynamoDB table"
  value       = aws_dynamodb_table.sync_metrics.arn
}

# EventBridge Resources
output "event_bus_name" {
  description = "Name of the custom EventBridge bus"
  value       = aws_cloudwatch_event_bus.shadow_sync.name
}

output "event_bus_arn" {
  description = "ARN of the custom EventBridge bus"
  value       = aws_cloudwatch_event_bus.shadow_sync.arn
}

# IoT Rules
output "shadow_delta_rule_name" {
  description = "Name of the shadow delta processing IoT rule"
  value       = aws_iot_topic_rule.shadow_delta_processing.name
}

output "shadow_delta_rule_arn" {
  description = "ARN of the shadow delta processing IoT rule"
  value       = aws_iot_topic_rule.shadow_delta_processing.arn
}

output "shadow_audit_rule_name" {
  description = "Name of the shadow audit logging IoT rule"
  value       = aws_iot_topic_rule.shadow_audit_logging.name
}

output "shadow_audit_rule_arn" {
  description = "ARN of the shadow audit logging IoT rule"
  value       = aws_iot_topic_rule.shadow_audit_logging.arn
}

# CloudWatch Resources
output "shadow_audit_log_group" {
  description = "Name of the shadow audit CloudWatch log group"
  value       = aws_cloudwatch_log_group.shadow_audit.name
}

output "conflict_resolver_log_group" {
  description = "Name of the conflict resolver CloudWatch log group"
  value       = aws_cloudwatch_log_group.conflict_resolver.name
}

output "sync_manager_log_group" {
  description = "Name of the sync manager CloudWatch log group"
  value       = aws_cloudwatch_log_group.sync_manager.name
}

output "dashboard_name" {
  description = "Name of the CloudWatch dashboard"
  value       = aws_cloudwatch_dashboard.shadow_monitoring.dashboard_name
}

output "dashboard_url" {
  description = "URL to access the CloudWatch dashboard"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.shadow_monitoring.dashboard_name}"
}

# IAM Resources
output "lambda_execution_role_name" {
  description = "Name of the Lambda execution IAM role"
  value       = aws_iam_role.lambda_execution.name
}

output "lambda_execution_role_arn" {
  description = "ARN of the Lambda execution IAM role"
  value       = aws_iam_role.lambda_execution.arn
}

output "iot_policy_name" {
  description = "Name of the IoT device policy"
  value       = aws_iot_policy.demo_device.name
}

# IoT Endpoints
output "iot_endpoint" {
  description = "IoT data endpoint for the current region"
  value       = data.aws_iot_endpoint.current.endpoint_address
}

# Data source for IoT endpoint
data "aws_iot_endpoint" "current" {
  endpoint_type = "iot:Data-ATS"
}

# EventBridge Rules
output "health_check_rule_name" {
  description = "Name of the health check EventBridge rule"
  value       = aws_cloudwatch_event_rule.shadow_health_check.name
}

output "health_check_rule_arn" {
  description = "ARN of the health check EventBridge rule"
  value       = aws_cloudwatch_event_rule.shadow_health_check.arn
}

output "conflict_notification_rule_name" {
  description = "Name of the conflict notification EventBridge rule"
  value       = aws_cloudwatch_event_rule.shadow_conflict_notifications.name
}

output "conflict_notification_rule_arn" {
  description = "ARN of the conflict notification EventBridge rule"
  value       = aws_cloudwatch_event_rule.shadow_conflict_notifications.arn
}

# Shadow Names
output "shadow_names" {
  description = "List of named shadows configured for the demo device"
  value       = var.shadow_names
}

# Connection Information
output "mqtt_connection_info" {
  description = "Information for connecting to AWS IoT Core via MQTT"
  value = {
    endpoint    = data.aws_iot_endpoint.current.endpoint_address
    port        = 8883
    thing_name  = aws_iot_thing.demo_device.name
    client_id   = aws_iot_thing.demo_device.name
    certificate = "Use certificate_pem output (sensitive)"
    private_key = "Use private_key output (sensitive)"
    ca_cert     = "Download from https://www.amazontrust.com/repository/AmazonRootCA1.pem"
  }
}

# Resource Summary
output "resource_summary" {
  description = "Summary of created resources"
  value = {
    iot_thing               = aws_iot_thing.demo_device.name
    lambda_functions        = [aws_lambda_function.conflict_resolver.function_name, aws_lambda_function.sync_manager.function_name]
    dynamodb_tables         = [aws_dynamodb_table.shadow_history.name, aws_dynamodb_table.device_config.name, aws_dynamodb_table.sync_metrics.name]
    iot_rules              = [aws_iot_topic_rule.shadow_delta_processing.name, aws_iot_topic_rule.shadow_audit_logging.name]
    eventbridge_rules      = [aws_cloudwatch_event_rule.shadow_health_check.name, aws_cloudwatch_event_rule.shadow_conflict_notifications.name]
    cloudwatch_log_groups  = [aws_cloudwatch_log_group.shadow_audit.name, aws_cloudwatch_log_group.conflict_resolver.name, aws_cloudwatch_log_group.sync_manager.name]
    dashboard              = aws_cloudwatch_dashboard.shadow_monitoring.dashboard_name
  }
}

# Testing Commands
output "testing_commands" {
  description = "Commands for testing the shadow synchronization system"
  value = {
    check_thing = "aws iot describe-thing --thing-name ${aws_iot_thing.demo_device.name}"
    invoke_sync_check = "aws lambda invoke --function-name ${aws_lambda_function.sync_manager.function_name} --payload '{\"operation\":\"sync_check\",\"thingName\":\"${aws_iot_thing.demo_device.name}\",\"shadowNames\":[\"configuration\",\"telemetry\",\"maintenance\"]}' response.json"
    view_dashboard = "echo 'Dashboard URL: https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.shadow_monitoring.dashboard_name}'"
    view_logs = "aws logs filter-log-events --log-group-name ${aws_cloudwatch_log_group.conflict_resolver.name} --start-time $(date -d '1 hour ago' +%s)000"
  }
}