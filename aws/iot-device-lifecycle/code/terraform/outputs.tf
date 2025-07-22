# =====================================
# Core Infrastructure Outputs
# =====================================

output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "aws_account_id" {
  description = "AWS account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_string.suffix.result
}

# =====================================
# Fleet Management Outputs
# =====================================

output "fleet_name" {
  description = "Name of the IoT fleet"
  value       = local.fleet_name
}

output "thing_type_name" {
  description = "Name of the IoT thing type"
  value       = aws_iot_thing_type.sensor_type.name
}

output "thing_type_arn" {
  description = "ARN of the IoT thing type"
  value       = aws_iot_thing_type.sensor_type.arn
}

output "thing_group_name" {
  description = "Name of the static thing group"
  value       = aws_iot_thing_group.sensor_group.name
}

output "thing_group_arn" {
  description = "ARN of the static thing group"
  value       = aws_iot_thing_group.sensor_group.arn
}

output "dynamic_groups" {
  description = "Information about dynamic thing groups"
  value = {
    outdated_firmware = {
      name         = aws_iot_thing_group.outdated_firmware_group.name
      arn          = aws_iot_thing_group.outdated_firmware_group.arn
      query_string = "attributes.firmwareVersion:${var.initial_firmware_version}"
    }
    building_a = {
      name         = aws_iot_thing_group.building_a_group.name
      arn          = aws_iot_thing_group.building_a_group.arn
      query_string = "attributes.location:Building-A"
    }
  }
}

# =====================================
# Device Information Outputs
# =====================================

output "device_names" {
  description = "Names of provisioned IoT devices"
  value       = aws_iot_thing.devices[*].name
}

output "device_arns" {
  description = "ARNs of provisioned IoT devices"
  value       = aws_iot_thing.devices[*].arn
}

output "device_info" {
  description = "Detailed information about each device"
  value = {
    for i, device in aws_iot_thing.devices : device.name => {
      name         = device.name
      arn          = device.arn
      thing_type   = device.thing_type
      location     = var.device_locations[i]
      firmware     = var.initial_firmware_version
      manufacturer = var.device_manufacturer
    }
  }
}

# =====================================
# Security and Authentication Outputs
# =====================================

output "policy_name" {
  description = "Name of the IoT policy"
  value       = aws_iot_policy.device_policy.name
}

output "policy_arn" {
  description = "ARN of the IoT policy"
  value       = aws_iot_policy.device_policy.arn
}

output "certificate_arns" {
  description = "ARNs of device certificates"
  value       = aws_iot_certificate.device_certificates[*].arn
  sensitive   = true
}

output "certificate_ids" {
  description = "IDs of device certificates"
  value       = aws_iot_certificate.device_certificates[*].id
  sensitive   = true
}

output "device_certificate_mapping" {
  description = "Mapping of device names to certificate ARNs"
  value = {
    for i, device in aws_iot_thing.devices : device.name => aws_iot_certificate.device_certificates[i].arn
  }
  sensitive = true
}

# =====================================
# Logging and Monitoring Outputs
# =====================================

output "log_group_name" {
  description = "CloudWatch log group name for IoT logs"
  value       = aws_cloudwatch_log_group.iot_logs.name
}

output "log_group_arn" {
  description = "ARN of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.iot_logs.arn
}

output "logging_role_arn" {
  description = "ARN of the IAM role used for IoT logging"
  value       = aws_iam_role.iot_logging_role.arn
}

output "connectivity_alarm_name" {
  description = "Name of the device connectivity CloudWatch alarm"
  value       = aws_cloudwatch_metric_alarm.low_device_connectivity.alarm_name
}

# =====================================
# Fleet Metrics Outputs
# =====================================

output "fleet_metrics" {
  description = "Information about fleet metrics"
  value = {
    connected_devices = {
      name        = aws_iot_fleet_metric.connected_devices.metric_name
      arn         = aws_iot_fleet_metric.connected_devices.arn
      description = aws_iot_fleet_metric.connected_devices.description
    }
    firmware_versions = {
      name        = aws_iot_fleet_metric.firmware_versions.metric_name
      arn         = aws_iot_fleet_metric.firmware_versions.arn
      description = aws_iot_fleet_metric.firmware_versions.description
    }
  }
}

# =====================================
# Job Management Outputs
# =====================================

output "firmware_update_job_id" {
  description = "ID of the firmware update job"
  value       = aws_iot_job.firmware_update.job_id
}

output "firmware_update_job_arn" {
  description = "ARN of the firmware update job"
  value       = aws_iot_job.firmware_update.arn
}

output "firmware_update_job_info" {
  description = "Detailed information about the firmware update job"
  value = {
    job_id           = aws_iot_job.firmware_update.job_id
    arn              = aws_iot_job.firmware_update.arn
    description      = aws_iot_job.firmware_update.description
    target_selection = aws_iot_job.firmware_update.target_selection
    firmware_version = var.updated_firmware_version
  }
}

# =====================================
# Device Shadow Outputs
# =====================================

output "device_shadow_enabled" {
  description = "Whether device shadow synchronization is enabled"
  value       = var.shadow_sync_enabled
}

output "device_shadow_example" {
  description = "Information about the example device shadow"
  value = var.shadow_sync_enabled ? {
    thing_name = aws_iot_thing_shadow.device_shadow_example[0].thing_name
    created    = true
  } : {
    thing_name = null
    created    = false
  }
}

# =====================================
# IoT Endpoints Outputs
# =====================================

output "endpoints" {
  description = "IoT endpoints for device connections"
  value = {
    data_endpoint = {
      address = data.aws_iot_endpoint.data.endpoint_address
      type    = "iot:Data-ATS"
    }
    device_management_endpoint = {
      address = data.aws_iot_endpoint.device_management.endpoint_address
      type    = "iot:Jobs"
    }
  }
}

# =====================================
# Configuration Summary Outputs
# =====================================

output "fleet_configuration" {
  description = "Summary of fleet configuration"
  value = {
    fleet_name           = local.fleet_name
    device_count         = length(var.device_names)
    firmware_version     = var.initial_firmware_version
    indexing_enabled     = var.enable_fleet_indexing
    logging_level        = var.log_level
    shadow_sync_enabled  = var.shadow_sync_enabled
  }
}

output "indexing_configuration" {
  description = "Fleet indexing configuration details"
  value = var.enable_fleet_indexing ? {
    thing_indexing_mode              = var.thing_indexing_mode
    thing_connectivity_indexing_mode = var.thing_connectivity_indexing_mode
    thing_group_indexing_mode        = var.thing_group_indexing_mode
    enabled                          = true
  } : {
    enabled = false
  }
}

# =====================================
# Next Steps and Usage Instructions
# =====================================

output "next_steps" {
  description = "Next steps and usage instructions"
  value = {
    view_devices = "aws iot list-things-in-thing-group --thing-group-name ${aws_iot_thing_group.sensor_group.name}"
    search_devices = "aws iot search-index --index-name AWS_Things --query-string \"attributes.location:Building-A\""
    check_job_status = "aws iot describe-job --job-id ${aws_iot_job.firmware_update.job_id}"
    view_logs = "aws logs describe-log-streams --log-group-name ${aws_cloudwatch_log_group.iot_logs.name}"
  }
}

output "management_console_links" {
  description = "AWS Management Console links for IoT resources"
  value = {
    iot_core = "https://${data.aws_region.current.name}.console.aws.amazon.com/iot/home?region=${data.aws_region.current.name}#/thinghub"
    thing_group = "https://${data.aws_region.current.name}.console.aws.amazon.com/iot/home?region=${data.aws_region.current.name}#/thinggroup/${aws_iot_thing_group.sensor_group.name}"
    jobs = "https://${data.aws_region.current.name}.console.aws.amazon.com/iot/home?region=${data.aws_region.current.name}#/jobhub"
    fleet_metrics = "https://${data.aws_region.current.name}.console.aws.amazon.com/iot/home?region=${data.aws_region.current.name}#/fleet-metrics"
    cloudwatch_logs = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#logsV2:log-groups/log-group/${replace(aws_cloudwatch_log_group.iot_logs.name, "/", "$252F")}"
  }
}