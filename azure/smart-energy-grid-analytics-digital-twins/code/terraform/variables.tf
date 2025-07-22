# Variables for Azure Energy Grid Analytics Infrastructure

variable "resource_group_name" {
  description = "Name of the resource group for energy grid analytics resources"
  type        = string
  default     = "rg-energy-grid-analytics"
}

variable "location" {
  description = "Azure region for resource deployment"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "North Central US", "South Central US", "West Central US",
      "Canada Central", "Canada East", "Brazil South", "UK South", "UK West",
      "West Europe", "North Europe", "France Central", "Germany West Central",
      "Switzerland North", "Norway East", "Sweden Central", "Australia East",
      "Australia Southeast", "East Asia", "Southeast Asia", "Japan East",
      "Japan West", "Korea Central", "South India", "Central India"
    ], var.location)
    error_message = "Location must be a valid Azure region."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "demo"
  
  validation {
    condition     = contains(["dev", "staging", "prod", "demo"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod, demo."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "smart-grid"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    environment = "demo"
    purpose     = "energy-analytics"
    project     = "smart-grid"
  }
}

# Digital Twins Configuration
variable "digital_twins_instance_name" {
  description = "Name for the Azure Digital Twins instance"
  type        = string
  default     = ""
  
  validation {
    condition     = var.digital_twins_instance_name == "" || can(regex("^[a-zA-Z0-9-]{3,63}$", var.digital_twins_instance_name))
    error_message = "Digital Twins instance name must be 3-63 characters long and contain only letters, numbers, and hyphens."
  }
}

# Time Series Insights Configuration
variable "time_series_insights_sku" {
  description = "SKU for Time Series Insights environment"
  type        = string
  default     = "S1"
  
  validation {
    condition     = contains(["S1", "S2"], var.time_series_insights_sku)
    error_message = "Time Series Insights SKU must be S1 or S2."
  }
}

variable "time_series_insights_capacity" {
  description = "Capacity for Time Series Insights environment"
  type        = number
  default     = 1
  
  validation {
    condition     = var.time_series_insights_capacity >= 1 && var.time_series_insights_capacity <= 10
    error_message = "Time Series Insights capacity must be between 1 and 10."
  }
}

variable "time_series_data_retention_days" {
  description = "Data retention period for Time Series Insights warm store in days"
  type        = number
  default     = 7
  
  validation {
    condition     = var.time_series_data_retention_days >= 1 && var.time_series_data_retention_days <= 400
    error_message = "Data retention must be between 1 and 400 days."
  }
}

# IoT Hub Configuration
variable "iot_hub_sku" {
  description = "SKU for IoT Hub"
  type        = string
  default     = "S1"
  
  validation {
    condition     = contains(["F1", "S1", "S2", "S3"], var.iot_hub_sku)
    error_message = "IoT Hub SKU must be F1, S1, S2, or S3."
  }
}

variable "iot_hub_capacity" {
  description = "Capacity for IoT Hub"
  type        = number
  default     = 1
  
  validation {
    condition     = var.iot_hub_capacity >= 1 && var.iot_hub_capacity <= 200
    error_message = "IoT Hub capacity must be between 1 and 200."
  }
}

variable "iot_hub_partition_count" {
  description = "Number of partitions for IoT Hub"
  type        = number
  default     = 4
  
  validation {
    condition     = var.iot_hub_partition_count >= 2 && var.iot_hub_partition_count <= 128
    error_message = "IoT Hub partition count must be between 2 and 128."
  }
}

# Cognitive Services Configuration
variable "cognitive_services_sku" {
  description = "SKU for Cognitive Services"
  type        = string
  default     = "S0"
  
  validation {
    condition     = contains(["F0", "S0", "S1", "S2", "S3", "S4"], var.cognitive_services_sku)
    error_message = "Cognitive Services SKU must be F0, S0, S1, S2, S3, or S4."
  }
}

# Storage Account Configuration
variable "storage_account_tier" {
  description = "Storage account tier"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be Standard or Premium."
  }
}

variable "storage_account_replication_type" {
  description = "Storage account replication type"
  type        = string
  default     = "LRS"
  
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_account_replication_type)
    error_message = "Storage account replication type must be LRS, GRS, RAGRS, ZRS, GZRS, or RAGZRS."
  }
}

# Function App Configuration
variable "function_app_os_type" {
  description = "Operating system type for Function App"
  type        = string
  default     = "linux"
  
  validation {
    condition     = contains(["linux", "windows"], var.function_app_os_type)
    error_message = "Function App OS type must be linux or windows."
  }
}

variable "function_app_runtime" {
  description = "Runtime for Function App"
  type        = string
  default     = "node"
  
  validation {
    condition     = contains(["node", "python", "dotnet", "java"], var.function_app_runtime)
    error_message = "Function App runtime must be node, python, dotnet, or java."
  }
}

variable "function_app_runtime_version" {
  description = "Runtime version for Function App"
  type        = string
  default     = "18"
}

# Log Analytics Configuration
variable "log_analytics_retention_days" {
  description = "Retention period for Log Analytics workspace in days"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_analytics_retention_days >= 30 && var.log_analytics_retention_days <= 730
    error_message = "Log Analytics retention must be between 30 and 730 days."
  }
}

variable "log_analytics_sku" {
  description = "SKU for Log Analytics workspace"
  type        = string
  default     = "PerGB2018"
  
  validation {
    condition     = contains(["Free", "Standard", "Premium", "PerNode", "PerGB2018", "Standalone"], var.log_analytics_sku)
    error_message = "Log Analytics SKU must be Free, Standard, Premium, PerNode, PerGB2018, or Standalone."
  }
}

# Energy Data Manager Configuration
variable "energy_data_manager_partition_count" {
  description = "Number of partitions for Energy Data Manager"
  type        = number
  default     = 1
  
  validation {
    condition     = var.energy_data_manager_partition_count >= 1 && var.energy_data_manager_partition_count <= 10
    error_message = "Energy Data Manager partition count must be between 1 and 10."
  }
}

variable "energy_data_manager_sku" {
  description = "SKU for Energy Data Manager"
  type        = string
  default     = "S1"
  
  validation {
    condition     = contains(["S1", "S2", "S3"], var.energy_data_manager_sku)
    error_message = "Energy Data Manager SKU must be S1, S2, or S3."
  }
}

# DTDL Models Configuration
variable "create_sample_dtdl_models" {
  description = "Whether to create sample DTDL models for energy grid components"
  type        = bool
  default     = true
}

variable "create_sample_digital_twins" {
  description = "Whether to create sample digital twin instances"
  type        = bool
  default     = true
}

# Monitoring and Alerting Configuration
variable "enable_diagnostic_settings" {
  description = "Whether to enable diagnostic settings for monitoring"
  type        = bool
  default     = true
}

variable "enable_application_insights" {
  description = "Whether to enable Application Insights for monitoring"
  type        = bool
  default     = true
}

# Security Configuration
variable "enable_private_endpoints" {
  description = "Whether to enable private endpoints for enhanced security"
  type        = bool
  default     = false
}

variable "allowed_ip_ranges" {
  description = "List of IP ranges allowed to access resources"
  type        = list(string)
  default     = []
}

# Cost Management
variable "auto_shutdown_enabled" {
  description = "Whether to enable auto-shutdown for cost optimization"
  type        = bool
  default     = true
}

variable "auto_shutdown_time" {
  description = "Time for auto-shutdown in 24-hour format (HH:MM)"
  type        = string
  default     = "19:00"
  
  validation {
    condition     = can(regex("^([0-1]?[0-9]|2[0-3]):[0-5][0-9]$", var.auto_shutdown_time))
    error_message = "Auto-shutdown time must be in HH:MM format (24-hour)."
  }
}

variable "auto_shutdown_timezone" {
  description = "Timezone for auto-shutdown"
  type        = string
  default     = "UTC"
}