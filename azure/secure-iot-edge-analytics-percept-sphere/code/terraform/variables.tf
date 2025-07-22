# =============================================================================
# Variables for Azure IoT Edge Analytics with Percept and Sphere
# =============================================================================
# This file defines all input variables for the IoT Edge Analytics Terraform 
# configuration, providing customizable parameters for different environments
# and deployment scenarios.

# =============================================================================
# General Configuration
# =============================================================================

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "location" {
  description = "Azure region where resources will be deployed"
  type        = string
  default     = "East US"
}

variable "resource_group_name" {
  description = "Name of the resource group. If empty, a name will be generated"
  type        = string
  default     = ""
}

variable "common_tags" {
  description = "Common tags to be applied to all resources"
  type        = map(string)
  default = {
    Project     = "IoT Edge Analytics"
    Owner       = "Platform Team"
    CostCenter  = "Engineering"
    Terraform   = "true"
  }
}

# =============================================================================
# Log Analytics Workspace Configuration
# =============================================================================

variable "log_analytics_sku" {
  description = "SKU for Log Analytics workspace"
  type        = string
  default     = "PerGB2018"
  validation {
    condition     = contains(["Free", "PerNode", "PerGB2018", "Standalone", "Standard", "Premium"], var.log_analytics_sku)
    error_message = "Log Analytics SKU must be one of: Free, PerNode, PerGB2018, Standalone, Standard, Premium."
  }
}

variable "log_analytics_retention_days" {
  description = "Number of days to retain logs in Log Analytics workspace"
  type        = number
  default     = 30
  validation {
    condition     = var.log_analytics_retention_days >= 7 && var.log_analytics_retention_days <= 730
    error_message = "Log Analytics retention days must be between 7 and 730."
  }
}

# =============================================================================
# Key Vault Configuration
# =============================================================================

variable "key_vault_sku" {
  description = "SKU for Key Vault"
  type        = string
  default     = "standard"
  validation {
    condition     = contains(["standard", "premium"], var.key_vault_sku)
    error_message = "Key Vault SKU must be either 'standard' or 'premium'."
  }
}

variable "key_vault_soft_delete_retention_days" {
  description = "Number of days to retain soft deleted keys in Key Vault"
  type        = number
  default     = 90
  validation {
    condition     = var.key_vault_soft_delete_retention_days >= 7 && var.key_vault_soft_delete_retention_days <= 90
    error_message = "Key Vault soft delete retention days must be between 7 and 90."
  }
}

variable "key_vault_network_acls_default_action" {
  description = "Default action for Key Vault network ACLs"
  type        = string
  default     = "Allow"
  validation {
    condition     = contains(["Allow", "Deny"], var.key_vault_network_acls_default_action)
    error_message = "Key Vault network ACLs default action must be either 'Allow' or 'Deny'."
  }
}

variable "key_vault_allowed_ips" {
  description = "List of IP addresses allowed to access Key Vault"
  type        = list(string)
  default     = []
}

variable "key_vault_allowed_subnets" {
  description = "List of subnet IDs allowed to access Key Vault"
  type        = list(string)
  default     = []
}

# =============================================================================
# Storage Account Configuration
# =============================================================================

variable "storage_account_tier" {
  description = "Storage account tier"
  type        = string
  default     = "Standard"
  validation {
    condition     = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be either 'Standard' or 'Premium'."
  }
}

variable "storage_account_replication_type" {
  description = "Storage account replication type"
  type        = string
  default     = "LRS"
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_account_replication_type)
    error_message = "Storage account replication type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

variable "blob_soft_delete_retention_days" {
  description = "Number of days to retain soft deleted blobs"
  type        = number
  default     = 7
  validation {
    condition     = var.blob_soft_delete_retention_days >= 1 && var.blob_soft_delete_retention_days <= 365
    error_message = "Blob soft delete retention days must be between 1 and 365."
  }
}

variable "container_soft_delete_retention_days" {
  description = "Number of days to retain soft deleted containers"
  type        = number
  default     = 7
  validation {
    condition     = var.container_soft_delete_retention_days >= 1 && var.container_soft_delete_retention_days <= 365
    error_message = "Container soft delete retention days must be between 1 and 365."
  }
}

variable "storage_network_rules_default_action" {
  description = "Default action for storage account network rules"
  type        = string
  default     = "Allow"
  validation {
    condition     = contains(["Allow", "Deny"], var.storage_network_rules_default_action)
    error_message = "Storage network rules default action must be either 'Allow' or 'Deny'."
  }
}

variable "storage_allowed_ips" {
  description = "List of IP addresses allowed to access storage account"
  type        = list(string)
  default     = []
}

variable "storage_allowed_subnets" {
  description = "List of subnet IDs allowed to access storage account"
  type        = list(string)
  default     = []
}

# =============================================================================
# IoT Hub Configuration
# =============================================================================

variable "iothub_sku_name" {
  description = "SKU name for IoT Hub"
  type        = string
  default     = "S1"
  validation {
    condition     = contains(["F1", "S1", "S2", "S3"], var.iothub_sku_name)
    error_message = "IoT Hub SKU name must be one of: F1, S1, S2, S3."
  }
}

variable "iothub_sku_capacity" {
  description = "Number of units for IoT Hub SKU"
  type        = number
  default     = 1
  validation {
    condition     = var.iothub_sku_capacity >= 1 && var.iothub_sku_capacity <= 200
    error_message = "IoT Hub SKU capacity must be between 1 and 200."
  }
}

variable "iothub_event_hub_retention_days" {
  description = "Number of days to retain messages in IoT Hub event hub"
  type        = number
  default     = 1
  validation {
    condition     = var.iothub_event_hub_retention_days >= 1 && var.iothub_event_hub_retention_days <= 7
    error_message = "IoT Hub event hub retention days must be between 1 and 7."
  }
}

variable "iothub_event_hub_partition_count" {
  description = "Number of partitions for IoT Hub event hub"
  type        = number
  default     = 4
  validation {
    condition     = var.iothub_event_hub_partition_count >= 2 && var.iothub_event_hub_partition_count <= 32
    error_message = "IoT Hub event hub partition count must be between 2 and 32."
  }
}

variable "iothub_cloud_to_device_max_delivery_count" {
  description = "Maximum delivery count for cloud-to-device messages"
  type        = number
  default     = 10
  validation {
    condition     = var.iothub_cloud_to_device_max_delivery_count >= 1 && var.iothub_cloud_to_device_max_delivery_count <= 100
    error_message = "Cloud-to-device max delivery count must be between 1 and 100."
  }
}

variable "iothub_cloud_to_device_default_ttl" {
  description = "Default TTL for cloud-to-device messages (ISO 8601 format)"
  type        = string
  default     = "PT1H"
}

variable "iothub_feedback_time_to_live" {
  description = "Time to live for feedback messages (ISO 8601 format)"
  type        = string
  default     = "PT1H"
}

variable "iothub_feedback_max_delivery_count" {
  description = "Maximum delivery count for feedback messages"
  type        = number
  default     = 10
  validation {
    condition     = var.iothub_feedback_max_delivery_count >= 1 && var.iothub_feedback_max_delivery_count <= 100
    error_message = "Feedback max delivery count must be between 1 and 100."
  }
}

variable "iothub_file_upload_default_ttl" {
  description = "Default TTL for file upload SAS URIs (ISO 8601 format)"
  type        = string
  default     = "PT1H"
}

variable "iothub_file_upload_max_delivery_count" {
  description = "Maximum delivery count for file upload notifications"
  type        = number
  default     = 10
  validation {
    condition     = var.iothub_file_upload_max_delivery_count >= 1 && var.iothub_file_upload_max_delivery_count <= 100
    error_message = "File upload max delivery count must be between 1 and 100."
  }
}

variable "iothub_telemetry_batch_frequency" {
  description = "Batch frequency in seconds for telemetry endpoint"
  type        = number
  default     = 100
  validation {
    condition     = var.iothub_telemetry_batch_frequency >= 60 && var.iothub_telemetry_batch_frequency <= 300
    error_message = "Telemetry batch frequency must be between 60 and 300 seconds."
  }
}

variable "iothub_telemetry_max_chunk_size" {
  description = "Maximum chunk size in bytes for telemetry endpoint"
  type        = number
  default     = 104857600 # 100 MB
  validation {
    condition     = var.iothub_telemetry_max_chunk_size >= 10485760 && var.iothub_telemetry_max_chunk_size <= 524288000
    error_message = "Telemetry max chunk size must be between 10MB and 500MB."
  }
}

# =============================================================================
# Stream Analytics Configuration
# =============================================================================

variable "stream_analytics_compatibility_level" {
  description = "Compatibility level for Stream Analytics job"
  type        = string
  default     = "1.2"
  validation {
    condition     = contains(["1.0", "1.1", "1.2"], var.stream_analytics_compatibility_level)
    error_message = "Stream Analytics compatibility level must be one of: 1.0, 1.1, 1.2."
  }
}

variable "stream_analytics_data_locale" {
  description = "Data locale for Stream Analytics job"
  type        = string
  default     = "en-US"
}

variable "stream_analytics_events_late_arrival_max_delay" {
  description = "Maximum delay in seconds for late arrival events"
  type        = number
  default     = 5
  validation {
    condition     = var.stream_analytics_events_late_arrival_max_delay >= 0 && var.stream_analytics_events_late_arrival_max_delay <= 1800
    error_message = "Events late arrival max delay must be between 0 and 1800 seconds."
  }
}

variable "stream_analytics_events_out_of_order_max_delay" {
  description = "Maximum delay in seconds for out-of-order events"
  type        = number
  default     = 0
  validation {
    condition     = var.stream_analytics_events_out_of_order_max_delay >= 0 && var.stream_analytics_events_out_of_order_max_delay <= 599
    error_message = "Events out of order max delay must be between 0 and 599 seconds."
  }
}

variable "stream_analytics_events_out_of_order_policy" {
  description = "Policy for handling out-of-order events"
  type        = string
  default     = "Adjust"
  validation {
    condition     = contains(["Adjust", "Drop"], var.stream_analytics_events_out_of_order_policy)
    error_message = "Events out of order policy must be either 'Adjust' or 'Drop'."
  }
}

variable "stream_analytics_output_error_policy" {
  description = "Policy for handling output errors"
  type        = string
  default     = "Stop"
  validation {
    condition     = contains(["Stop", "Drop"], var.stream_analytics_output_error_policy)
    error_message = "Output error policy must be either 'Stop' or 'Drop'."
  }
}

variable "stream_analytics_streaming_units" {
  description = "Number of streaming units for Stream Analytics job"
  type        = number
  default     = 1
  validation {
    condition     = var.stream_analytics_streaming_units >= 1 && var.stream_analytics_streaming_units <= 120
    error_message = "Streaming units must be between 1 and 120."
  }
}

# =============================================================================
# Device Configuration
# =============================================================================

variable "percept_device_id" {
  description = "Device ID for Azure Percept device"
  type        = string
  default     = "percept-device-01"
}

variable "sphere_device_id" {
  description = "Device ID for Azure Sphere device"
  type        = string
  default     = "sphere-device-01"
}

# =============================================================================
# Threshold Configuration for Anomaly Detection
# =============================================================================

variable "temperature_threshold_high" {
  description = "High temperature threshold for alerts"
  type        = number
  default     = 80.0
}

variable "temperature_threshold_low" {
  description = "Low temperature threshold for alerts"
  type        = number
  default     = 10.0
}

variable "vibration_threshold_high" {
  description = "High vibration threshold for alerts"
  type        = number
  default     = 2.0
}

variable "pressure_threshold_high" {
  description = "High pressure threshold for alerts"
  type        = number
  default     = 1050.0
}

variable "pressure_threshold_low" {
  description = "Low pressure threshold for alerts"
  type        = number
  default     = 950.0
}

# =============================================================================
# Monitoring and Alerting Configuration
# =============================================================================

variable "minimum_connected_devices_threshold" {
  description = "Minimum number of connected devices before triggering an alert"
  type        = number
  default     = 1
  validation {
    condition     = var.minimum_connected_devices_threshold >= 0
    error_message = "Minimum connected devices threshold must be greater than or equal to 0."
  }
}

variable "throttling_threshold" {
  description = "Throttling threshold for IoT Hub messages"
  type        = number
  default     = 10
  validation {
    condition     = var.throttling_threshold >= 0
    error_message = "Throttling threshold must be greater than or equal to 0."
  }
}

variable "alert_email_receivers" {
  description = "List of email receivers for alerts"
  type = list(object({
    name          = string
    email_address = string
  }))
  default = [
    {
      name          = "AdminEmail"
      email_address = "admin@company.com"
    }
  ]
}

variable "alert_sms_receivers" {
  description = "List of SMS receivers for alerts"
  type = list(object({
    name         = string
    country_code = string
    phone_number = string
  }))
  default = []
}

variable "alert_webhook_receivers" {
  description = "List of webhook receivers for alerts"
  type = list(object({
    name                    = string
    service_uri             = string
    use_common_alert_schema = bool
  }))
  default = []
}

# =============================================================================
# Security Configuration
# =============================================================================

variable "enable_private_endpoints" {
  description = "Enable private endpoints for supported services"
  type        = bool
  default     = false
}

variable "enable_advanced_threat_protection" {
  description = "Enable advanced threat protection for storage account"
  type        = bool
  default     = false
}

variable "enable_firewall_bypass" {
  description = "Enable firewall bypass for Azure services"
  type        = bool
  default     = true
}

# =============================================================================
# Cost Management Configuration
# =============================================================================

variable "enable_cost_alerts" {
  description = "Enable cost alerts for resources"
  type        = bool
  default     = true
}

variable "monthly_budget_amount" {
  description = "Monthly budget amount for cost alerts (USD)"
  type        = number
  default     = 500
  validation {
    condition     = var.monthly_budget_amount > 0
    error_message = "Monthly budget amount must be greater than 0."
  }
}

variable "budget_alert_threshold" {
  description = "Budget alert threshold percentage"
  type        = number
  default     = 80
  validation {
    condition     = var.budget_alert_threshold > 0 && var.budget_alert_threshold <= 100
    error_message = "Budget alert threshold must be between 0 and 100."
  }
}

# =============================================================================
# Backup and Disaster Recovery Configuration
# =============================================================================

variable "enable_backup" {
  description = "Enable backup for supported services"
  type        = bool
  default     = true
}

variable "backup_retention_days" {
  description = "Number of days to retain backups"
  type        = number
  default     = 30
  validation {
    condition     = var.backup_retention_days >= 1 && var.backup_retention_days <= 365
    error_message = "Backup retention days must be between 1 and 365."
  }
}

variable "enable_geo_redundancy" {
  description = "Enable geo-redundancy for critical services"
  type        = bool
  default     = false
}

# =============================================================================
# Development and Testing Configuration
# =============================================================================

variable "enable_diagnostic_logs" {
  description = "Enable diagnostic logs for all services"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Number of days to retain diagnostic logs"
  type        = number
  default     = 30
  validation {
    condition     = var.log_retention_days >= 1 && var.log_retention_days <= 365
    error_message = "Log retention days must be between 1 and 365."
  }
}

variable "enable_debug_logging" {
  description = "Enable debug logging for development environments"
  type        = bool
  default     = false
}