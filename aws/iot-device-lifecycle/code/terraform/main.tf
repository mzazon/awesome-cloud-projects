# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Get current AWS account ID and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Local values for consistent naming
locals {
  fleet_name       = "${var.fleet_name_prefix}-${random_string.suffix.result}"
  thing_type_name  = "${var.thing_type_name_prefix}-${random_string.suffix.result}"
  thing_group_name = "${var.thing_group_name_prefix}-${random_string.suffix.result}"
  policy_name      = "${var.policy_name_prefix}-${random_string.suffix.result}"
  
  # Dynamic group names
  outdated_firmware_group = "outdated-firmware-${random_string.suffix.result}"
  building_a_group        = "building-a-sensors-${random_string.suffix.result}"
  
  # CloudWatch log group name
  log_group_name = "/aws/iot/device-management-${random_string.suffix.result}"
  
  # Fleet metric names
  connected_devices_metric = "ConnectedDevices-${random_string.suffix.result}"
  firmware_versions_metric = "FirmwareVersions-${random_string.suffix.result}"
  
  # Job names
  firmware_update_job = "firmware-update-${random_string.suffix.result}"
  
  # Common tags
  common_tags = merge(var.default_tags, var.additional_tags, {
    FleetName = local.fleet_name
  })
}

# =====================================
# Fleet Indexing Configuration
# =====================================

# Enable fleet indexing for device management
resource "aws_iot_indexing_configuration" "fleet_indexing" {
  count = var.enable_fleet_indexing ? 1 : 0
  
  thing_indexing_configuration {
    thing_indexing_mode                   = var.thing_indexing_mode
    thing_connectivity_indexing_mode      = var.thing_connectivity_indexing_mode
    device_defender_indexing_mode         = "OFF"
    named_shadow_indexing_mode           = "OFF"
    managed_field {
      name = "connectivity.connected"
      type = "Boolean"
    }
    managed_field {
      name = "connectivity.timestamp"
      type = "Number"
    }
  }
  
  thing_group_indexing_configuration {
    thing_group_indexing_mode = var.thing_group_indexing_mode
  }
}

# =====================================
# Thing Type Definition
# =====================================

# Create IoT Thing Type for device templates
resource "aws_iot_thing_type" "sensor_type" {
  name = local.thing_type_name
  
  properties {
    thing_type_description = "Temperature sensor device type"
    searchable_attributes  = ["location", "firmwareVersion", "manufacturer"]
  }
  
  tags = local.common_tags
}

# =====================================
# Thing Group Configuration
# =====================================

# Create static thing group for device organization
resource "aws_iot_thing_group" "sensor_group" {
  name = local.thing_group_name
  
  properties {
    thing_group_description = "Production temperature sensors"
    attribute_payload {
      attributes = {
        Environment = "Production"
        Location    = "Factory1"
      }
    }
  }
  
  tags = local.common_tags
}

# Create dynamic thing group for devices with old firmware
resource "aws_iot_thing_group" "outdated_firmware_group" {
  name = local.outdated_firmware_group
  
  properties {
    thing_group_description = "Devices requiring firmware updates"
  }
  
  dynamic_thing_group_properties {
    thing_group_description = "Devices requiring firmware updates"
    index_name             = "AWS_Things"
    query_string          = "attributes.firmwareVersion:${var.initial_firmware_version}"
    query_version         = "2017-09-30"
  }
  
  tags = local.common_tags
  
  depends_on = [aws_iot_indexing_configuration.fleet_indexing]
}

# Create dynamic thing group for Building A devices
resource "aws_iot_thing_group" "building_a_group" {
  name = local.building_a_group
  
  properties {
    thing_group_description = "All sensors in Building A"
  }
  
  dynamic_thing_group_properties {
    thing_group_description = "All sensors in Building A"
    index_name             = "AWS_Things"
    query_string          = "attributes.location:Building-A"
    query_version         = "2017-09-30"
  }
  
  tags = local.common_tags
  
  depends_on = [aws_iot_indexing_configuration.fleet_indexing]
}

# =====================================
# IoT Policy Definition
# =====================================

# Create IoT Policy for device permissions
resource "aws_iot_policy" "device_policy" {
  name = local.policy_name
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "iot:Connect",
          "iot:Publish",
          "iot:Subscribe",
          "iot:Receive"
        ]
        Resource = [
          "arn:aws:iot:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:client/$${iot:Connection.Thing.ThingName}",
          "arn:aws:iot:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:topic/device/$${iot:Connection.Thing.ThingName}/*",
          "arn:aws:iot:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:topicfilter/device/$${iot:Connection.Thing.ThingName}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "iot:GetThingShadow",
          "iot:UpdateThingShadow",
          "iot:DeleteThingShadow"
        ]
        Resource = [
          "arn:aws:iot:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:thing/$${iot:Connection.Thing.ThingName}"
        ]
      }
    ]
  })
  
  tags = local.common_tags
}

# =====================================
# Device Provisioning
# =====================================

# Create IoT Things (devices)
resource "aws_iot_thing" "devices" {
  count = length(var.device_names)
  
  name      = var.device_names[count.index]
  thing_type = aws_iot_thing_type.sensor_type.name
  
  attributes = {
    location        = var.device_locations[count.index]
    firmwareVersion = var.initial_firmware_version
    manufacturer    = var.device_manufacturer
  }
  
  tags = merge(local.common_tags, {
    DeviceLocation = var.device_locations[count.index]
  })
}

# Add things to static group
resource "aws_iot_thing_group_membership" "device_group_membership" {
  count = length(var.device_names)
  
  thing_name       = aws_iot_thing.devices[count.index].name
  thing_group_name = aws_iot_thing_group.sensor_group.name
  
  override_dynamic_groups = false
}

# =====================================
# Device Certificates and Security
# =====================================

# Create certificates for each device
resource "aws_iot_certificate" "device_certificates" {
  count = length(var.device_names)
  
  active = true
  
  tags = merge(local.common_tags, {
    DeviceName = var.device_names[count.index]
  })
}

# Attach policy to certificates
resource "aws_iot_policy_attachment" "device_policy_attachment" {
  count = length(var.device_names)
  
  policy = aws_iot_policy.device_policy.name
  target = aws_iot_certificate.device_certificates[count.index].arn
}

# Attach certificates to things
resource "aws_iot_thing_principal_attachment" "device_certificate_attachment" {
  count = length(var.device_names)
  
  thing     = aws_iot_thing.devices[count.index].name
  principal = aws_iot_certificate.device_certificates[count.index].arn
}

# =====================================
# Logging Configuration
# =====================================

# Create CloudWatch log group for IoT logs
resource "aws_cloudwatch_log_group" "iot_logs" {
  name              = local.log_group_name
  retention_in_days = var.log_retention_days
  
  tags = local.common_tags
}

# Set logging level for the thing group
resource "aws_iot_logging_options" "thing_group_logging" {
  default_log_level = var.log_level
  
  disable_all_logs = false
  
  role_arn = aws_iam_role.iot_logging_role.arn
}

# IAM role for IoT logging
resource "aws_iam_role" "iot_logging_role" {
  name = "iot-logging-role-${random_string.suffix.result}"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "iot.amazonaws.com"
        }
      }
    ]
  })
  
  tags = local.common_tags
}

# IAM policy for IoT logging
resource "aws_iam_role_policy" "iot_logging_policy" {
  name = "iot-logging-policy-${random_string.suffix.result}"
  role = aws_iam_role.iot_logging_role.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = [
          aws_cloudwatch_log_group.iot_logs.arn,
          "${aws_cloudwatch_log_group.iot_logs.arn}:*"
        ]
      }
    ]
  })
}

# =====================================
# OTA Jobs Configuration
# =====================================

# Create firmware update job
resource "aws_iot_job" "firmware_update" {
  job_id = local.firmware_update_job
  
  targets = [aws_iot_thing_group.sensor_group.arn]
  
  description = "Firmware update to version ${var.updated_firmware_version}"
  
  document = jsonencode({
    operation        = "firmwareUpdate"
    firmwareVersion  = var.updated_firmware_version
    downloadUrl      = var.firmware_download_url
    checksum         = var.firmware_checksum
    rebootRequired   = true
    timeout          = 300
  })
  
  target_selection = "CONTINUOUS"
  
  job_config {
    job_execution_config {
      max_concurrent_executions = var.job_max_concurrent_executions
    }
    
    timeout_config {
      in_progress_timeout_in_minutes = var.job_timeout_minutes
    }
  }
  
  tags = local.common_tags
}

# =====================================
# Fleet Metrics Configuration
# =====================================

# Fleet metric for device connectivity
resource "aws_iot_fleet_metric" "connected_devices" {
  metric_name = local.connected_devices_metric
  
  query_string = "connectivity.connected:true"
  
  aggregation_type {
    name   = "Statistics"
    values = ["count"]
  }
  
  period = var.fleet_metric_period
  
  aggregation_field = "connectivity.connected"
  description       = "Count of connected devices in fleet"
  
  tags = local.common_tags
  
  depends_on = [aws_iot_indexing_configuration.fleet_indexing]
}

# Fleet metric for firmware versions
resource "aws_iot_fleet_metric" "firmware_versions" {
  metric_name = local.firmware_versions_metric
  
  query_string = "attributes.firmwareVersion:*"
  
  aggregation_type {
    name   = "Statistics"
    values = ["count"]
  }
  
  period = var.fleet_metric_period
  
  aggregation_field = "attributes.firmwareVersion"
  description       = "Distribution of firmware versions"
  
  tags = local.common_tags
  
  depends_on = [aws_iot_indexing_configuration.fleet_indexing]
}

# =====================================
# Device Shadow Configuration
# =====================================

# Update device shadow for demonstration (first device only)
resource "aws_iot_thing_shadow" "device_shadow_example" {
  count = var.shadow_sync_enabled ? 1 : 0
  
  thing_name = aws_iot_thing.devices[0].name
  
  payload = jsonencode({
    state = {
      reported = {
        temperature     = 22.5
        humidity        = 45.2
        batteryLevel    = 85
        lastSeen        = "2024-01-15T10:30:00Z"
        firmwareVersion = var.initial_firmware_version
      }
      desired = {
        reportingInterval = var.default_reporting_interval
        alertThreshold    = var.default_alert_threshold
      }
    }
  })
  
  depends_on = [aws_iot_thing_principal_attachment.device_certificate_attachment]
}

# =====================================
# CloudWatch Alarms for Monitoring
# =====================================

# CloudWatch alarm for device connectivity
resource "aws_cloudwatch_metric_alarm" "low_device_connectivity" {
  alarm_name          = "iot-low-device-connectivity-${random_string.suffix.result}"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = local.connected_devices_metric
  namespace           = "AWS/IoT"
  period              = "300"
  statistic           = "Average"
  threshold           = length(var.device_names) * 0.8 # Alert if less than 80% of devices are connected
  alarm_description   = "This metric monitors IoT device connectivity"
  alarm_actions       = [] # Add SNS topic ARN for notifications
  
  tags = local.common_tags
  
  depends_on = [aws_iot_fleet_metric.connected_devices]
}

# =====================================
# Output Values for Reference
# =====================================

# Create outputs for easy reference
output "fleet_name" {
  description = "Name of the IoT fleet"
  value       = local.fleet_name
}

output "thing_type_name" {
  description = "Name of the IoT thing type"
  value       = aws_iot_thing_type.sensor_type.name
}

output "thing_group_name" {
  description = "Name of the static thing group"
  value       = aws_iot_thing_group.sensor_group.name
}

output "dynamic_groups" {
  description = "Names of dynamic thing groups"
  value = {
    outdated_firmware = aws_iot_thing_group.outdated_firmware_group.name
    building_a        = aws_iot_thing_group.building_a_group.name
  }
}

output "device_names" {
  description = "Names of provisioned IoT devices"
  value       = aws_iot_thing.devices[*].name
}

output "policy_name" {
  description = "Name of the IoT policy"
  value       = aws_iot_policy.device_policy.name
}

output "certificate_arns" {
  description = "ARNs of device certificates"
  value       = aws_iot_certificate.device_certificates[*].arn
  sensitive   = true
}

output "log_group_name" {
  description = "CloudWatch log group name for IoT logs"
  value       = aws_cloudwatch_log_group.iot_logs.name
}

output "firmware_update_job_id" {
  description = "ID of the firmware update job"
  value       = aws_iot_job.firmware_update.job_id
}

output "fleet_metrics" {
  description = "Names of fleet metrics"
  value = {
    connected_devices = aws_iot_fleet_metric.connected_devices.metric_name
    firmware_versions = aws_iot_fleet_metric.firmware_versions.metric_name
  }
}

output "endpoints" {
  description = "IoT endpoints for device connections"
  value = {
    data_endpoint = data.aws_iot_endpoint.data.endpoint_address
    device_management_endpoint = data.aws_iot_endpoint.device_management.endpoint_address
  }
}

# Get IoT endpoints
data "aws_iot_endpoint" "data" {
  endpoint_type = "iot:Data-ATS"
}

data "aws_iot_endpoint" "device_management" {
  endpoint_type = "iot:Jobs"
}