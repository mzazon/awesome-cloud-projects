# Variables definition for Azure smart manufacturing digital twins solution
# This file defines all input variables for customizing the deployment

# Basic deployment configuration
variable "location" {
  description = "Azure region where resources will be deployed"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "North Central US", "South Central US", "West Central US",
      "Canada Central", "Canada East", "Brazil South",
      "North Europe", "West Europe", "UK South", "UK West",
      "France Central", "Germany West Central", "Norway East",
      "Switzerland North", "Sweden Central",
      "Japan East", "Japan West", "Korea Central", "Korea South",
      "Australia East", "Australia Southeast", "Southeast Asia", "East Asia"
    ], var.location)
    error_message = "Location must be a valid Azure region."
  }
}

variable "environment" {
  description = "Environment name for resource tagging and naming"
  type        = string
  default     = "dev"
  
  validation {
    condition     = can(regex("^[a-z0-9]+$", var.environment))
    error_message = "Environment must contain only lowercase letters and numbers."
  }
}

variable "project_name" {
  description = "Project name used for resource naming and tagging"
  type        = string
  default     = "smart-manufacturing"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

# Resource naming configuration
variable "resource_prefix" {
  description = "Prefix for all resource names to ensure uniqueness"
  type        = string
  default     = ""
  
  validation {
    condition     = can(regex("^[a-z0-9]*$", var.resource_prefix))
    error_message = "Resource prefix must contain only lowercase letters and numbers."
  }
}

variable "use_random_suffix" {
  description = "Whether to append a random suffix to resource names for uniqueness"
  type        = bool
  default     = true
}

# IoT Hub configuration
variable "iot_hub_sku" {
  description = "IoT Hub SKU and capacity configuration"
  type = object({
    name     = string
    capacity = number
  })
  default = {
    name     = "S1"
    capacity = 1
  }
  
  validation {
    condition = contains(["B1", "B2", "B3", "S1", "S2", "S3"], var.iot_hub_sku.name)
    error_message = "IoT Hub SKU must be one of: B1, B2, B3, S1, S2, S3."
  }
  
  validation {
    condition     = var.iot_hub_sku.capacity >= 1 && var.iot_hub_sku.capacity <= 200
    error_message = "IoT Hub capacity must be between 1 and 200."
  }
}

variable "iot_hub_partition_count" {
  description = "Number of partitions for IoT Hub message processing"
  type        = number
  default     = 4
  
  validation {
    condition     = var.iot_hub_partition_count >= 2 && var.iot_hub_partition_count <= 32
    error_message = "IoT Hub partition count must be between 2 and 32."
  }
}

variable "iot_hub_retention_days" {
  description = "Message retention time in days for IoT Hub"
  type        = number
  default     = 1
  
  validation {
    condition     = var.iot_hub_retention_days >= 1 && var.iot_hub_retention_days <= 7
    error_message = "IoT Hub retention days must be between 1 and 7."
  }
}

# Digital Twins configuration
variable "digital_twins_identity_type" {
  description = "Type of managed identity for Digital Twins instance"
  type        = string
  default     = "SystemAssigned"
  
  validation {
    condition     = contains(["SystemAssigned", "UserAssigned"], var.digital_twins_identity_type)
    error_message = "Digital Twins identity type must be SystemAssigned or UserAssigned."
  }
}

# Storage Account configuration
variable "storage_account_tier" {
  description = "Storage account performance tier"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be Standard or Premium."
  }
}

variable "storage_account_replication" {
  description = "Storage account replication strategy"
  type        = string
  default     = "LRS"
  
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_account_replication)
    error_message = "Storage replication must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

variable "enable_hierarchical_namespace" {
  description = "Enable hierarchical namespace for Data Lake Storage Gen2 capabilities"
  type        = bool
  default     = true
}

# Time Series Insights configuration
variable "tsi_sku" {
  description = "Time Series Insights SKU configuration"
  type = object({
    name     = string
    capacity = number
  })
  default = {
    name     = "L1"
    capacity = 1
  }
  
  validation {
    condition = contains(["L1"], var.tsi_sku.name)
    error_message = "TSI SKU must be L1 for Gen2 environments."
  }
  
  validation {
    condition     = var.tsi_sku.capacity >= 1 && var.tsi_sku.capacity <= 10
    error_message = "TSI capacity must be between 1 and 10."
  }
}

variable "tsi_warm_store_retention" {
  description = "Warm store data retention period in ISO 8601 format (e.g., P7D for 7 days)"
  type        = string
  default     = "P7D"
  
  validation {
    condition     = can(regex("^P[0-9]+D$", var.tsi_warm_store_retention))
    error_message = "TSI warm store retention must be in ISO 8601 format (e.g., P7D)."
  }
}

variable "tsi_time_series_id_properties" {
  description = "Properties that uniquely identify time series data in TSI"
  type        = list(string)
  default     = ["deviceId"]
  
  validation {
    condition     = length(var.tsi_time_series_id_properties) > 0
    error_message = "At least one time series ID property must be specified."
  }
}

# Machine Learning Workspace configuration
variable "ml_workspace_sku" {
  description = "Machine Learning workspace SKU"
  type        = string
  default     = "Basic"
  
  validation {
    condition     = contains(["Basic", "Enterprise"], var.ml_workspace_sku)
    error_message = "ML workspace SKU must be Basic or Enterprise."
  }
}

variable "ml_workspace_public_network_access" {
  description = "Enable public network access for ML workspace"
  type        = string
  default     = "Enabled"
  
  validation {
    condition     = contains(["Enabled", "Disabled"], var.ml_workspace_public_network_access)
    error_message = "ML workspace public network access must be Enabled or Disabled."
  }
}

# Security and access configuration
variable "enable_rbac_assignments" {
  description = "Enable role-based access control assignments for current user"
  type        = bool
  default     = true
}

variable "additional_rbac_principals" {
  description = "Additional principal IDs to grant access to Digital Twins and other resources"
  type        = list(string)
  default     = []
}

# IoT device simulation configuration
variable "create_sample_devices" {
  description = "Create sample IoT device registrations for testing"
  type        = bool
  default     = true
}

variable "sample_devices" {
  description = "Configuration for sample IoT devices"
  type = list(object({
    device_id = string
    device_type = string
  }))
  default = [
    {
      device_id   = "robotic-arm-001"
      device_type = "robotic-assembly"
    },
    {
      device_id   = "conveyor-belt-001"
      device_type = "conveyor-transport"
    },
    {
      device_id   = "quality-scanner-001"
      device_type = "quality-control"
    }
  ]
}

# Event routing configuration
variable "enable_event_routing" {
  description = "Enable event routing from IoT Hub to other services"
  type        = bool
  default     = true
}

# Monitoring and diagnostics
variable "enable_diagnostics" {
  description = "Enable diagnostic settings for all resources"
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

# Tagging configuration
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# Cost optimization
variable "auto_delete_resources" {
  description = "Enable automatic deletion of resources after specified time (for development environments)"
  type        = bool
  default     = false
}

variable "auto_delete_hours" {
  description = "Hours after which resources will be automatically deleted (requires auto_delete_resources = true)"
  type        = number
  default     = 24
  
  validation {
    condition     = var.auto_delete_hours >= 1 && var.auto_delete_hours <= 168
    error_message = "Auto delete hours must be between 1 and 168 (7 days)."
  }
}