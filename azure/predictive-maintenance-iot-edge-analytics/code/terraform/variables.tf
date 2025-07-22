# Variables for the Edge-Based Predictive Maintenance solution
variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = "rg-predictive-maintenance"
}

variable "location" {
  description = "Azure region where resources will be created"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "North Central US", "South Central US", "West Central US",
      "Canada Central", "Canada East", "Brazil South", "UK South", "UK West",
      "West Europe", "North Europe", "France Central", "Germany West Central",
      "Switzerland North", "Norway East", "Sweden Central", "Italy North",
      "Poland Central", "Australia East", "Australia Southeast", "East Asia",
      "Southeast Asia", "Japan East", "Japan West", "Korea Central", "Korea South",
      "Central India", "South India", "West India", "UAE North", "South Africa North"
    ], var.location)
    error_message = "Location must be a valid Azure region."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, test, prod)"
  type        = string
  default     = "demo"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.environment))
    error_message = "Environment must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "pm"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "iot_hub_sku" {
  description = "SKU for the IoT Hub"
  type        = string
  default     = "S1"
  
  validation {
    condition     = contains(["F1", "S1", "S2", "S3"], var.iot_hub_sku)
    error_message = "IoT Hub SKU must be one of: F1, S1, S2, S3."
  }
}

variable "iot_hub_capacity" {
  description = "Number of units for the IoT Hub"
  type        = number
  default     = 1
  
  validation {
    condition     = var.iot_hub_capacity >= 1 && var.iot_hub_capacity <= 200
    error_message = "IoT Hub capacity must be between 1 and 200."
  }
}

variable "storage_account_tier" {
  description = "Performance tier for storage account"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be either Standard or Premium."
  }
}

variable "storage_account_replication" {
  description = "Replication type for storage account"
  type        = string
  default     = "LRS"
  
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_account_replication)
    error_message = "Storage account replication must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

variable "edge_device_id" {
  description = "ID for the IoT Edge device"
  type        = string
  default     = "edge-device-01"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.edge_device_id))
    error_message = "Edge device ID must contain only letters, numbers, and hyphens."
  }
}

variable "stream_analytics_streaming_units" {
  description = "Number of streaming units for Stream Analytics job"
  type        = number
  default     = 1
  
  validation {
    condition     = var.stream_analytics_streaming_units >= 1 && var.stream_analytics_streaming_units <= 192
    error_message = "Streaming units must be between 1 and 192."
  }
}

variable "log_analytics_sku" {
  description = "SKU for Log Analytics workspace"
  type        = string
  default     = "PerGB2018"
  
  validation {
    condition     = contains(["Free", "Standard", "Premium", "PerNode", "PerGB2018", "Standalone"], var.log_analytics_sku)
    error_message = "Log Analytics SKU must be one of: Free, Standard, Premium, PerNode, PerGB2018, Standalone."
  }
}

variable "log_analytics_retention_days" {
  description = "Number of days to retain logs in Log Analytics workspace"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_analytics_retention_days >= 30 && var.log_analytics_retention_days <= 730
    error_message = "Log Analytics retention must be between 30 and 730 days."
  }
}

variable "temperature_alert_threshold_avg" {
  description = "Average temperature threshold for anomaly detection (Celsius)"
  type        = number
  default     = 75
  
  validation {
    condition     = var.temperature_alert_threshold_avg > 0 && var.temperature_alert_threshold_avg < 200
    error_message = "Temperature threshold must be between 0 and 200 degrees Celsius."
  }
}

variable "temperature_alert_threshold_max" {
  description = "Maximum temperature threshold for anomaly detection (Celsius)"
  type        = number
  default     = 85
  
  validation {
    condition     = var.temperature_alert_threshold_max > 0 && var.temperature_alert_threshold_max < 200
    error_message = "Temperature threshold must be between 0 and 200 degrees Celsius."
  }
}

variable "alert_email" {
  description = "Email address for maintenance alerts"
  type        = string
  default     = "maintenance@example.com"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.alert_email))
    error_message = "Alert email must be a valid email address."
  }
}

variable "alert_phone" {
  description = "Phone number for SMS alerts (format: +1234567890)"
  type        = string
  default     = "+15551234567"
  
  validation {
    condition     = can(regex("^\\+[1-9]\\d{1,14}$", var.alert_phone))
    error_message = "Alert phone must be in E.164 format (e.g., +1234567890)."
  }
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Purpose     = "predictive-maintenance"
    Environment = "demo"
    ManagedBy   = "terraform"
  }
}