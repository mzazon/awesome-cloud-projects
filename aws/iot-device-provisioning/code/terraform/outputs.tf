# Outputs for IoT Device Provisioning and Certificate Management
# This file defines the outputs that will be displayed after deployment

# ============================================================================
# Core Infrastructure Outputs
# ============================================================================

output "aws_region" {
  description = "AWS region where resources were deployed"
  value       = data.aws_region.current.name
}

output "aws_account_id" {
  description = "AWS account ID where resources were deployed"
  value       = data.aws_caller_identity.current.account_id
}

output "resource_suffix" {
  description = "Random suffix used for resource names"
  value       = local.resource_suffix
}

# ============================================================================
# DynamoDB Outputs
# ============================================================================

output "device_registry_table_name" {
  description = "Name of the DynamoDB table for device registry"
  value       = aws_dynamodb_table.device_registry.name
}

output "device_registry_table_arn" {
  description = "ARN of the DynamoDB table for device registry"
  value       = aws_dynamodb_table.device_registry.arn
}

# ============================================================================
# Lambda Function Outputs
# ============================================================================

output "provisioning_hook_function_name" {
  description = "Name of the Lambda function for pre-provisioning hook"
  value       = aws_lambda_function.provisioning_hook.function_name
}

output "provisioning_hook_function_arn" {
  description = "ARN of the Lambda function for pre-provisioning hook"
  value       = aws_lambda_function.provisioning_hook.arn
}

output "lambda_execution_role_arn" {
  description = "ARN of the IAM role for Lambda execution"
  value       = aws_iam_role.lambda_execution_role.arn
}

# ============================================================================
# IoT Provisioning Template Outputs
# ============================================================================

output "provisioning_template_name" {
  description = "Name of the IoT provisioning template"
  value       = aws_iot_provisioning_template.device_provisioning.name
}

output "provisioning_template_arn" {
  description = "ARN of the IoT provisioning template"
  value       = aws_iot_provisioning_template.device_provisioning.arn
}

output "iot_provisioning_role_arn" {
  description = "ARN of the IAM role for IoT provisioning"
  value       = aws_iam_role.iot_provisioning_role.arn
}

# ============================================================================
# Thing Group Outputs
# ============================================================================

output "parent_thing_group_name" {
  description = "Name of the parent thing group for all provisioned devices"
  value       = aws_iot_thing_group.provisioned_devices.name
}

output "parent_thing_group_arn" {
  description = "ARN of the parent thing group for all provisioned devices"
  value       = aws_iot_thing_group.provisioned_devices.arn
}

output "device_type_thing_groups" {
  description = "Map of device types to their thing group names"
  value = {
    for device_type, thing_group in aws_iot_thing_group.device_type_groups : device_type => thing_group.name
  }
}

# ============================================================================
# IoT Policy Outputs
# ============================================================================

output "temperature_sensor_policy_name" {
  description = "Name of the IoT policy for temperature sensors"
  value       = aws_iot_policy.temperature_sensor_policy.name
}

output "temperature_sensor_policy_arn" {
  description = "ARN of the IoT policy for temperature sensors"
  value       = aws_iot_policy.temperature_sensor_policy.arn
}

output "gateway_policy_name" {
  description = "Name of the IoT policy for gateway devices"
  value       = aws_iot_policy.gateway_policy.name
}

output "gateway_policy_arn" {
  description = "ARN of the IoT policy for gateway devices"
  value       = aws_iot_policy.gateway_policy.arn
}

output "claim_certificate_policy_name" {
  description = "Name of the IoT policy for claim certificates"
  value       = aws_iot_policy.claim_certificate_policy.name
}

output "claim_certificate_policy_arn" {
  description = "ARN of the IoT policy for claim certificates"
  value       = aws_iot_policy.claim_certificate_policy.arn
}

# ============================================================================
# Claim Certificate Outputs
# ============================================================================

output "claim_certificate_id" {
  description = "ID of the claim certificate for device manufacturing"
  value       = aws_iot_certificate.claim_certificate.id
}

output "claim_certificate_arn" {
  description = "ARN of the claim certificate for device manufacturing"
  value       = aws_iot_certificate.claim_certificate.arn
}

output "claim_certificate_pem" {
  description = "PEM format of the claim certificate"
  value       = aws_iot_certificate.claim_certificate.certificate_pem
  sensitive   = true
}

output "claim_certificate_private_key" {
  description = "Private key of the claim certificate"
  value       = aws_iot_certificate.claim_certificate.private_key
  sensitive   = true
}

output "claim_certificate_public_key" {
  description = "Public key of the claim certificate"
  value       = aws_iot_certificate.claim_certificate.public_key
  sensitive   = true
}

# ============================================================================
# Monitoring Outputs
# ============================================================================

output "provisioning_logs_group_name" {
  description = "Name of the CloudWatch log group for provisioning monitoring"
  value       = var.enable_monitoring ? aws_cloudwatch_log_group.provisioning_logs[0].name : null
}

output "provisioning_logs_group_arn" {
  description = "ARN of the CloudWatch log group for provisioning monitoring"
  value       = var.enable_monitoring ? aws_cloudwatch_log_group.provisioning_logs[0].arn : null
}

output "provisioning_alerts_topic_arn" {
  description = "ARN of the SNS topic for provisioning alerts"
  value       = var.enable_monitoring && var.sns_endpoint != "" ? aws_sns_topic.provisioning_alerts[0].arn : null
}

output "provisioning_failures_alarm_name" {
  description = "Name of the CloudWatch alarm for provisioning failures"
  value       = var.enable_monitoring ? aws_cloudwatch_metric_alarm.provisioning_failures[0].alarm_name : null
}

# ============================================================================
# Audit Logging Outputs
# ============================================================================

output "audit_rule_name" {
  description = "Name of the IoT topic rule for audit logging"
  value       = var.enable_audit_logging ? aws_iot_topic_rule.provisioning_audit_rule[0].name : null
}

output "audit_rule_arn" {
  description = "ARN of the IoT topic rule for audit logging"
  value       = var.enable_audit_logging ? aws_iot_topic_rule.provisioning_audit_rule[0].arn : null
}

# ============================================================================
# Useful Commands and Information
# ============================================================================

output "iot_endpoint" {
  description = "AWS IoT Core endpoint for device connections"
  value       = "https://${data.aws_iot_endpoint.current.endpoint_address}"
}

output "device_provisioning_endpoint" {
  description = "AWS IoT Device Provisioning endpoint"
  value       = "https://${data.aws_iot_endpoint.current.endpoint_address}"
}

output "mqtt_endpoint" {
  description = "MQTT endpoint for device connections"
  value       = data.aws_iot_endpoint.current.endpoint_address
}

output "deployment_instructions" {
  description = "Instructions for using the deployed infrastructure"
  value = <<-EOT
    
    ## Deployment Complete!
    
    Your IoT Device Provisioning and Certificate Management infrastructure has been deployed successfully.
    
    ### Key Resources Created:
    - Provisioning Template: ${aws_iot_provisioning_template.device_provisioning.name}
    - Device Registry Table: ${aws_dynamodb_table.device_registry.name}
    - Pre-Provisioning Hook: ${aws_lambda_function.provisioning_hook.function_name}
    - Claim Certificate: ${aws_iot_certificate.claim_certificate.id}
    
    ### Next Steps:
    1. Download the claim certificate files for device manufacturing
    2. Test device provisioning using the claim certificate
    3. Verify devices are properly registered in the DynamoDB table
    4. Monitor provisioning events in CloudWatch logs
    
    ### Important Security Notes:
    - Store claim certificate private key securely
    - Monitor provisioning failures and alerts
    - Regularly rotate claim certificates
    - Review device registry for unauthorized devices
    
    ### Useful CLI Commands:
    - Test provisioning hook: aws lambda invoke --function-name ${aws_lambda_function.provisioning_hook.function_name} --payload '{"parameters":{"SerialNumber":"TEST123","DeviceType":"temperature-sensor","Manufacturer":"Test"}}' output.json
    - List provisioned devices: aws dynamodb scan --table-name ${aws_dynamodb_table.device_registry.name}
    - Check provisioning template: aws iot describe-provisioning-template --template-name ${aws_iot_provisioning_template.device_provisioning.name}
    
  EOT
}

# ============================================================================
# Data Sources for Outputs
# ============================================================================

# Get IoT endpoint for device connections
data "aws_iot_endpoint" "current" {
  endpoint_type = "iot:Data-ATS"
}