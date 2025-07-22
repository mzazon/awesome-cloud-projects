# ==============================================================================
# CORE INFRASTRUCTURE OUTPUTS
# ==============================================================================

output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "aws_account_id" {
  description = "AWS account ID"
  value       = data.aws_caller_identity.current.account_id
}

output "resource_prefix" {
  description = "Prefix used for resource naming"
  value       = var.resource_prefix
}

output "random_suffix" {
  description = "Random suffix used for unique resource names"
  value       = local.random_suffix
}

# ==============================================================================
# S3 BUCKET OUTPUTS
# ==============================================================================

output "s3_bucket_name" {
  description = "Name of the S3 bucket storing firmware files"
  value       = aws_s3_bucket.firmware_bucket.bucket
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket storing firmware files"
  value       = aws_s3_bucket.firmware_bucket.arn
}

output "s3_bucket_domain_name" {
  description = "Domain name of the S3 bucket"
  value       = aws_s3_bucket.firmware_bucket.bucket_domain_name
}

output "firmware_file_url" {
  description = "URL of the firmware file in S3"
  value       = "https://${aws_s3_bucket.firmware_bucket.bucket_domain_name}/firmware/firmware-${var.firmware_version}.bin"
}

output "firmware_file_key" {
  description = "S3 key of the firmware file"
  value       = aws_s3_object.firmware_file.key
}

output "job_document_url" {
  description = "URL of the job document in S3"
  value       = "https://${aws_s3_bucket.firmware_bucket.bucket_domain_name}/job-documents/firmware-update-${var.firmware_version}.json"
}

# ==============================================================================
# IOT POLICY OUTPUTS
# ==============================================================================

output "iot_policy_name" {
  description = "Name of the IoT policy for device fleet"
  value       = aws_iot_policy.device_policy.name
}

output "iot_policy_arn" {
  description = "ARN of the IoT policy for device fleet"
  value       = aws_iot_policy.device_policy.arn
}

output "iot_policy_document" {
  description = "JSON document of the IoT policy"
  value       = aws_iot_policy.device_policy.policy
  sensitive   = true
}

# ==============================================================================
# IOT THING GROUP OUTPUTS
# ==============================================================================

output "thing_group_name" {
  description = "Name of the IoT Thing Group"
  value       = aws_iot_thing_group.device_fleet.name
}

output "thing_group_arn" {
  description = "ARN of the IoT Thing Group"
  value       = aws_iot_thing_group.device_fleet.arn
}

output "thing_group_id" {
  description = "ID of the IoT Thing Group"
  value       = aws_iot_thing_group.device_fleet.id
}

output "thing_group_attributes" {
  description = "Attributes of the IoT Thing Group"
  value       = aws_iot_thing_group.device_fleet.properties[0].attribute_payload[0].attributes
}

# ==============================================================================
# IOT DEVICES (THINGS) OUTPUTS
# ==============================================================================

output "device_names" {
  description = "Names of all registered IoT devices"
  value       = aws_iot_thing.devices[*].name
}

output "device_arns" {
  description = "ARNs of all registered IoT devices"
  value       = aws_iot_thing.devices[*].arn
}

output "device_count" {
  description = "Number of devices registered in the fleet"
  value       = var.device_count
}

output "device_attributes" {
  description = "Attributes of all registered devices"
  value = {
    for idx, device in aws_iot_thing.devices : device.name => device.attributes
  }
}

# ==============================================================================
# IOT CERTIFICATES OUTPUTS
# ==============================================================================

output "certificate_arns" {
  description = "ARNs of device certificates"
  value       = aws_iot_certificate.device_certificates[*].arn
}

output "certificate_ids" {
  description = "IDs of device certificates"
  value       = aws_iot_certificate.device_certificates[*].id
}

output "certificate_pems" {
  description = "PEM certificates for devices (sensitive)"
  value       = aws_iot_certificate.device_certificates[*].certificate_pem
  sensitive   = true
}

output "certificate_private_keys" {
  description = "Private keys for device certificates (sensitive)"
  value       = aws_iot_certificate.device_certificates[*].private_key
  sensitive   = true
}

output "certificate_public_keys" {
  description = "Public keys for device certificates"
  value       = aws_iot_certificate.device_certificates[*].public_key
}

# ==============================================================================
# IOT JOB OUTPUTS
# ==============================================================================

output "job_id" {
  description = "ID of the firmware update job"
  value       = aws_iot_job.firmware_update.job_id
}

output "job_arn" {
  description = "ARN of the firmware update job"
  value       = aws_iot_job.firmware_update.arn
}

output "job_document" {
  description = "Job document for firmware update"
  value       = local.job_document
}

output "job_targets" {
  description = "Targets for the firmware update job"
  value       = aws_iot_job.firmware_update.targets
}

# ==============================================================================
# CLOUDWATCH LOGS OUTPUTS
# ==============================================================================

output "cloudwatch_log_group_name" {
  description = "Name of CloudWatch Log Group for IoT operations"
  value       = var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.iot_logs[0].name : null
}

output "cloudwatch_log_group_arn" {
  description = "ARN of CloudWatch Log Group for IoT operations"
  value       = var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.iot_logs[0].arn : null
}

# ==============================================================================
# FIRMWARE AND CONFIGURATION OUTPUTS
# ==============================================================================

output "firmware_version" {
  description = "Version of the firmware deployed"
  value       = var.firmware_version
}

output "initial_firmware_version" {
  description = "Initial firmware version for devices"
  value       = var.initial_firmware_version
}

output "device_type" {
  description = "Type of IoT devices in the fleet"
  value       = var.device_type
}

# ==============================================================================
# OPERATIONAL OUTPUTS
# ==============================================================================

output "iot_core_endpoint" {
  description = "AWS IoT Core endpoint for device connections"
  value       = "https://${data.aws_caller_identity.current.account_id}.iot.${data.aws_region.current.name}.amazonaws.com"
}

output "job_rollout_configuration" {
  description = "Job rollout configuration settings"
  value = {
    maximum_per_minute        = var.job_rollout_max_per_minute
    abort_threshold_percentage = var.job_abort_threshold_percentage
    timeout_minutes           = var.job_timeout_minutes
  }
}

output "fleet_management_commands" {
  description = "Useful AWS CLI commands for fleet management"
  value = {
    describe_job = "aws iot describe-job --job-id ${aws_iot_job.firmware_update.job_id}"
    list_job_executions = "aws iot list-job-executions-for-job --job-id ${aws_iot_job.firmware_update.job_id}"
    describe_thing_group = "aws iot describe-thing-group --thing-group-name ${aws_iot_thing_group.device_fleet.name}"
    list_things_in_group = "aws iot list-things-in-thing-group --thing-group-name ${aws_iot_thing_group.device_fleet.name}"
  }
}

# ==============================================================================
# TESTING AND VALIDATION OUTPUTS
# ==============================================================================

output "validation_commands" {
  description = "Commands for validating the IoT fleet deployment"
  value = {
    check_s3_bucket = "aws s3 ls s3://${aws_s3_bucket.firmware_bucket.bucket}/"
    check_devices = "aws iot list-things-in-thing-group --thing-group-name ${aws_iot_thing_group.device_fleet.name}"
    check_job_status = "aws iot describe-job --job-id ${aws_iot_job.firmware_update.job_id}"
    check_certificates = "aws iot list-certificates"
    check_policies = "aws iot list-policies"
  }
}

# ==============================================================================
# SECURITY OUTPUTS
# ==============================================================================

output "security_recommendations" {
  description = "Security recommendations for production deployment"
  value = {
    certificate_rotation = "Implement regular certificate rotation using AWS IoT Device Management"
    policy_review = "Regularly review and update IoT policies to follow least privilege principles"
    encryption_at_rest = "Ensure S3 bucket encryption is enabled for firmware storage"
    cloudwatch_monitoring = "Enable CloudWatch monitoring for security events and anomalies"
    device_defender = "Consider enabling AWS IoT Device Defender for continuous security monitoring"
  }
}

# ==============================================================================
# CA CERTIFICATE OUTPUTS (OPTIONAL)
# ==============================================================================

output "ca_certificate_id" {
  description = "ID of the CA certificate for auto-registration (if enabled)"
  value       = var.enable_certificate_auto_registration ? aws_iot_ca_certificate.device_ca[0].id : null
}

output "ca_certificate_arn" {
  description = "ARN of the CA certificate for auto-registration (if enabled)"
  value       = var.enable_certificate_auto_registration ? aws_iot_ca_certificate.device_ca[0].arn : null
}

# ==============================================================================
# COST OPTIMIZATION OUTPUTS
# ==============================================================================

output "cost_optimization_tips" {
  description = "Tips for optimizing costs in production"
  value = {
    s3_lifecycle = "Configure S3 lifecycle policies to transition old firmware versions to cheaper storage classes"
    log_retention = "Adjust CloudWatch log retention based on compliance requirements"
    device_optimization = "Monitor device connection patterns to optimize for cost-effective communication"
    job_scheduling = "Schedule firmware updates during off-peak hours to reduce costs"
  }
}