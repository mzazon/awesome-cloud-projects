# AWS Configuration
variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

# Project Configuration
variable "project_name" {
  description = "Name of the project (used for resource naming)"
  type        = string
  default     = "iot-device-management"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

# Fleet Configuration
variable "fleet_name_prefix" {
  description = "Prefix for fleet name (random suffix will be added)"
  type        = string
  default     = "fleet"
}

variable "thing_type_name_prefix" {
  description = "Prefix for thing type name (random suffix will be added)"
  type        = string
  default     = "sensor-type"
}

variable "thing_group_name_prefix" {
  description = "Prefix for thing group name (random suffix will be added)"
  type        = string
  default     = "sensor-group"
}

variable "policy_name_prefix" {
  description = "Prefix for IoT policy name (random suffix will be added)"
  type        = string
  default     = "device-policy"
}

# Device Configuration
variable "device_names" {
  description = "List of device names to create"
  type        = list(string)
  default     = ["temp-sensor-01", "temp-sensor-02", "temp-sensor-03", "temp-sensor-04"]
}

variable "device_locations" {
  description = "List of device locations (must match device_names length)"
  type        = list(string)
  default     = ["Building-A", "Building-B", "Building-C", "Building-D"]
}

variable "device_manufacturer" {
  description = "Device manufacturer name"
  type        = string
  default     = "AcmeSensors"
}

variable "initial_firmware_version" {
  description = "Initial firmware version for devices"
  type        = string
  default     = "1.0.0"
}

variable "updated_firmware_version" {
  description = "Updated firmware version for OTA updates"
  type        = string
  default     = "1.1.0"
}

# Fleet Indexing Configuration
variable "enable_fleet_indexing" {
  description = "Enable fleet indexing for device management"
  type        = bool
  default     = true
}

variable "thing_indexing_mode" {
  description = "Thing indexing mode (OFF, REGISTRY, REGISTRY_AND_SHADOW)"
  type        = string
  default     = "REGISTRY_AND_SHADOW"
  
  validation {
    condition     = contains(["OFF", "REGISTRY", "REGISTRY_AND_SHADOW"], var.thing_indexing_mode)
    error_message = "Thing indexing mode must be one of: OFF, REGISTRY, REGISTRY_AND_SHADOW."
  }
}

variable "thing_connectivity_indexing_mode" {
  description = "Thing connectivity indexing mode (OFF, STATUS)"
  type        = string
  default     = "STATUS"
  
  validation {
    condition     = contains(["OFF", "STATUS"], var.thing_connectivity_indexing_mode)
    error_message = "Thing connectivity indexing mode must be one of: OFF, STATUS."
  }
}

variable "thing_group_indexing_mode" {
  description = "Thing group indexing mode (OFF, ON)"
  type        = string
  default     = "ON"
  
  validation {
    condition     = contains(["OFF", "ON"], var.thing_group_indexing_mode)
    error_message = "Thing group indexing mode must be one of: OFF, ON."
  }
}

# Logging Configuration
variable "log_level" {
  description = "Log level for IoT logging (DEBUG, INFO, ERROR, WARN, DISABLED)"
  type        = string
  default     = "INFO"
  
  validation {
    condition     = contains(["DEBUG", "INFO", "ERROR", "WARN", "DISABLED"], var.log_level)
    error_message = "Log level must be one of: DEBUG, INFO, ERROR, WARN, DISABLED."
  }
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 30
  
  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.log_retention_days)
    error_message = "Log retention days must be one of the valid CloudWatch retention periods."
  }
}

# Job Configuration
variable "job_max_concurrent_executions" {
  description = "Maximum concurrent job executions"
  type        = number
  default     = 5
  
  validation {
    condition     = var.job_max_concurrent_executions >= 1 && var.job_max_concurrent_executions <= 1000
    error_message = "Job max concurrent executions must be between 1 and 1000."
  }
}

variable "job_timeout_minutes" {
  description = "Job timeout in minutes"
  type        = number
  default     = 30
  
  validation {
    condition     = var.job_timeout_minutes >= 1 && var.job_timeout_minutes <= 10080
    error_message = "Job timeout must be between 1 and 10080 minutes (1 week)."
  }
}

variable "firmware_download_url" {
  description = "URL for firmware download (example URL)"
  type        = string
  default     = "https://example-firmware-bucket.s3.amazonaws.com/firmware-v1.1.0.bin"
}

variable "firmware_checksum" {
  description = "Firmware checksum for validation"
  type        = string
  default     = "abc123def456"
}

# Fleet Metrics Configuration
variable "fleet_metric_period" {
  description = "Fleet metric period in seconds"
  type        = number
  default     = 300
  
  validation {
    condition     = var.fleet_metric_period >= 60
    error_message = "Fleet metric period must be at least 60 seconds."
  }
}

# Device Shadow Configuration
variable "shadow_sync_enabled" {
  description = "Enable device shadow synchronization"
  type        = bool
  default     = true
}

variable "default_reporting_interval" {
  description = "Default reporting interval for devices (seconds)"
  type        = number
  default     = 60
}

variable "default_alert_threshold" {
  description = "Default alert threshold for temperature sensors"
  type        = number
  default     = 30.0
}

# Security Configuration
variable "certificate_auto_rotate" {
  description = "Enable automatic certificate rotation"
  type        = bool
  default     = false
}

variable "enforce_ssl" {
  description = "Enforce SSL/TLS for device connections"
  type        = bool
  default     = true
}

# Tagging
variable "default_tags" {
  description = "Default tags to apply to all resources"
  type        = map(string)
  default = {
    Project     = "IoT Device Management"
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}

variable "additional_tags" {
  description = "Additional tags to apply to specific resources"
  type        = map(string)
  default     = {}
}