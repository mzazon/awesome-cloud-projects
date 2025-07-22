# Outputs for IoT Security implementation
# These outputs provide essential information for managing and monitoring the IoT security infrastructure

# ===============================================================================
# IoT Core Information
# ===============================================================================

output "iot_endpoint" {
  description = "AWS IoT Core endpoint for device connections"
  value       = data.aws_iot_endpoint.current.endpoint_address
}

output "thing_type_name" {
  description = "Name of the created IoT Thing Type"
  value       = aws_iot_thing_type.industrial_sensor.name
}

output "thing_group_name" {
  description = "Name of the IoT Thing Group"
  value       = aws_iot_thing_group.industrial_sensors.name
}

output "thing_group_arn" {
  description = "ARN of the IoT Thing Group"
  value       = aws_iot_thing_group.industrial_sensors.arn
}

# ===============================================================================
# Device Information
# ===============================================================================

output "device_names" {
  description = "List of created IoT device names"
  value       = aws_iot_thing.devices[*].name
}

output "device_certificate_arns" {
  description = "List of device certificate ARNs"
  value       = aws_iot_certificate.device_certificates[*].arn
  sensitive   = true
}

output "device_certificate_ids" {
  description = "List of device certificate IDs"
  value       = aws_iot_certificate.device_certificates[*].id
}

output "device_certificates_pem" {
  description = "Device certificates in PEM format (for device configuration)"
  value       = aws_iot_certificate.device_certificates[*].certificate_pem
  sensitive   = true
}

output "device_private_keys" {
  description = "Device private keys (store securely)"
  value       = tls_private_key.device_keys[*].private_key_pem
  sensitive   = true
}

output "device_public_keys" {
  description = "Device public keys"
  value       = tls_private_key.device_keys[*].public_key_pem
}

# ===============================================================================
# Security Policies
# ===============================================================================

output "restrictive_sensor_policy_name" {
  description = "Name of the restrictive sensor IoT policy"
  value       = aws_iot_policy.restrictive_sensor_policy.name
}

output "restrictive_sensor_policy_arn" {
  description = "ARN of the restrictive sensor IoT policy"
  value       = aws_iot_policy.restrictive_sensor_policy.arn
}

output "time_based_policy_name" {
  description = "Name of the time-based access policy (if enabled)"
  value       = var.enable_time_based_access ? aws_iot_policy.time_based_access_policy[0].name : null
}

output "location_based_policy_name" {
  description = "Name of the location-based access policy (if enabled)"
  value       = var.enable_location_based_access ? aws_iot_policy.location_based_access_policy[0].name : null
}

output "quarantine_policy_name" {
  description = "Name of the device quarantine policy"
  value       = aws_iot_policy.device_quarantine_policy.name
}

# ===============================================================================
# Device Defender Information
# ===============================================================================

output "security_profile_name" {
  description = "Name of the Device Defender security profile (if enabled)"
  value       = var.enable_device_defender ? aws_iot_security_profile.industrial_sensor_security[0].name : null
}

output "security_profile_arn" {
  description = "ARN of the Device Defender security profile (if enabled)"
  value       = var.enable_device_defender ? aws_iot_security_profile.industrial_sensor_security[0].arn : null
}

# ===============================================================================
# Monitoring and Alerting
# ===============================================================================

output "cloudwatch_dashboard_url" {
  description = "URL to the CloudWatch dashboard for IoT security metrics"
  value = var.enable_cloudwatch_monitoring ? "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.iot_security_dashboard[0].dashboard_name}" : null
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for security alerts"
  value       = var.enable_cloudwatch_monitoring ? aws_sns_topic.iot_security_alerts[0].arn : null
}

output "security_events_log_group" {
  description = "CloudWatch log group for IoT security events"
  value       = var.enable_cloudwatch_monitoring ? aws_cloudwatch_log_group.iot_security_events[0].name : null
}

output "security_events_table_name" {
  description = "DynamoDB table name for storing security events"
  value       = var.enable_cloudwatch_monitoring ? aws_dynamodb_table.iot_security_events[0].name : null
}

# ===============================================================================
# Lambda Functions
# ===============================================================================

output "security_processor_function_name" {
  description = "Name of the security event processor Lambda function"
  value       = var.enable_cloudwatch_monitoring ? aws_lambda_function.security_processor[0].function_name : null
}

output "certificate_rotation_function_name" {
  description = "Name of the certificate rotation Lambda function"
  value       = aws_lambda_function.certificate_rotation.function_name
}

# ===============================================================================
# Testing and Validation Information
# ===============================================================================

output "iot_test_commands" {
  description = "Example AWS CLI commands for testing IoT connectivity"
  value = {
    list_things = "aws iot list-things --thing-type-name ${aws_iot_thing_type.industrial_sensor.name}"
    describe_thing = "aws iot describe-thing --thing-name ${aws_iot_thing.devices[0].name}"
    list_certificates = "aws iot list-certificates --page-size 10"
    get_iot_endpoint = "aws iot describe-endpoint --endpoint-type iot:Data-ATS"
  }
}

output "mqtt_test_topics" {
  description = "MQTT topics for testing device communication"
  value = {
    telemetry = "sensors/{device-name}/telemetry"
    status    = "sensors/{device-name}/status"
    commands  = "sensors/{device-name}/commands"
    config    = "sensors/{device-name}/config"
  }
}

# ===============================================================================
# Certificate Management
# ===============================================================================

output "amazon_root_ca_url" {
  description = "URL to download Amazon Root CA certificate for device configuration"
  value       = "https://www.amazontrust.com/repository/AmazonRootCA1.pem"
}

output "certificate_rotation_schedule" {
  description = "EventBridge rule for certificate rotation monitoring"
  value       = aws_cloudwatch_event_rule.certificate_rotation_schedule.name
}

# ===============================================================================
# Compliance and Configuration
# ===============================================================================

output "config_recorder_name" {
  description = "Name of the AWS Config recorder for compliance monitoring"
  value       = var.enable_automated_compliance ? aws_config_configuration_recorder.iot_compliance[0].name : null
}

output "config_bucket_name" {
  description = "S3 bucket name for AWS Config storage"
  value       = var.enable_automated_compliance ? aws_s3_bucket.config_bucket[0].bucket : null
}

# ===============================================================================
# Security Best Practices Information
# ===============================================================================

output "security_recommendations" {
  description = "Security recommendations for production deployment"
  value = {
    certificate_storage = "Store device certificates and private keys in hardware security modules (HSMs) or secure elements"
    certificate_rotation = "Implement automated certificate rotation before expiration"
    network_security = "Use VPC endpoints for enhanced network security"
    monitoring = "Enable comprehensive logging and monitoring for all IoT activities"
    compliance = "Regular security assessments and penetration testing"
    policy_management = "Implement policy versioning and rollback capabilities"
  }
}

output "device_onboarding_steps" {
  description = "Steps for onboarding new devices securely"
  value = [
    "1. Generate unique certificate and private key for the device",
    "2. Provision device with certificate, private key, and Amazon Root CA",
    "3. Configure device with IoT endpoint and appropriate MQTT topics",
    "4. Test device connectivity and verify security policies",
    "5. Add device to appropriate Thing Group for monitoring",
    "6. Validate Device Defender security profile coverage"
  ]
}

# ===============================================================================
# Environment Information
# ===============================================================================

output "deployment_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "account_id" {
  description = "AWS account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

output "resource_naming_prefix" {
  description = "Naming prefix used for all resources"
  value       = local.name_prefix
}

output "unique_suffix" {
  description = "Unique suffix used for resource naming"
  value       = local.unique_suffix
}

# ===============================================================================
# Cost Optimization Information
# ===============================================================================

output "cost_optimization_tips" {
  description = "Tips for optimizing costs in production"
  value = {
    dynamodb = "Consider using DynamoDB On-Demand pricing for variable workloads"
    cloudwatch = "Adjust log retention periods based on compliance requirements"
    lambda = "Optimize Lambda memory allocation for cost efficiency"
    iot_messages = "Monitor message volumes and consider message batching"
    device_defender = "Review security profile frequency for cost optimization"
  }
}

# Data source for IoT endpoint
data "aws_iot_endpoint" "current" {
  endpoint_type = "iot:Data-ATS"
}