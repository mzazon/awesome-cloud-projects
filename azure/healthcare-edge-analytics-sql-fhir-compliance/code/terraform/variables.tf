# Variables for Azure Edge-Based Healthcare Analytics Infrastructure

variable "location" {
  description = "The Azure region where resources will be created"
  type        = string
  default     = "East US"
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "South Central US", "North Central US",
      "West Europe", "North Europe", "UK South", "UK West",
      "Southeast Asia", "East Asia", "Australia East", "Australia Southeast"
    ], var.location)
    error_message = "Location must be a valid Azure region that supports Health Data Services."
  }
}

variable "resource_group_name" {
  description = "The name of the resource group where all resources will be created"
  type        = string
  default     = ""
  validation {
    condition     = length(var.resource_group_name) <= 90
    error_message = "Resource group name must be 90 characters or less."
  }
}

variable "project_name" {
  description = "Name of the project used for resource naming"
  type        = string
  default     = "healthcare-edge"
  validation {
    condition     = can(regex("^[a-z0-9-]{3,24}$", var.project_name))
    error_message = "Project name must be 3-24 characters, lowercase letters, numbers, and hyphens only."
  }
}

variable "environment" {
  description = "Environment name (dev, test, prod)"
  type        = string
  default     = "demo"
  validation {
    condition     = contains(["dev", "test", "staging", "prod", "demo"], var.environment)
    error_message = "Environment must be one of: dev, test, staging, prod, demo."
  }
}

variable "iot_hub_sku" {
  description = "The SKU tier for IoT Hub"
  type        = string
  default     = "S1"
  validation {
    condition     = contains(["F1", "B1", "B2", "B3", "S1", "S2", "S3"], var.iot_hub_sku)
    error_message = "IoT Hub SKU must be one of: F1, B1, B2, B3, S1, S2, S3."
  }
}

variable "iot_hub_partition_count" {
  description = "Number of partitions for IoT Hub"
  type        = number
  default     = 2
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

variable "edge_device_id" {
  description = "The ID for the IoT Edge device"
  type        = string
  default     = "medical-edge-device-01"
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{1,128}$", var.edge_device_id))
    error_message = "Edge device ID must be 1-128 characters, alphanumeric and hyphens only."
  }
}

variable "sql_edge_password" {
  description = "Password for SQL Edge SA account"
  type        = string
  default     = "Strong!Passw0rd123"
  sensitive   = true
  validation {
    condition     = length(var.sql_edge_password) >= 8 && can(regex("[A-Z]", var.sql_edge_password)) && can(regex("[a-z]", var.sql_edge_password)) && can(regex("[0-9]", var.sql_edge_password)) && can(regex("[^a-zA-Z0-9]", var.sql_edge_password))
    error_message = "SQL Edge password must be at least 8 characters with uppercase, lowercase, number, and special character."
  }
}

variable "function_app_sku" {
  description = "The SKU for the Function App Service Plan"
  type        = string
  default     = "Y1"
  validation {
    condition     = contains(["Y1", "EP1", "EP2", "EP3", "P1v2", "P2v2", "P3v2"], var.function_app_sku)
    error_message = "Function App SKU must be one of: Y1, EP1, EP2, EP3, P1v2, P2v2, P3v2."
  }
}

variable "log_analytics_sku" {
  description = "The SKU for Log Analytics Workspace"
  type        = string
  default     = "PerGB2018"
  validation {
    condition     = contains(["Free", "Standalone", "PerNode", "PerGB2018"], var.log_analytics_sku)
    error_message = "Log Analytics SKU must be one of: Free, Standalone, PerNode, PerGB2018."
  }
}

variable "log_analytics_retention_days" {
  description = "Log retention time in days for Log Analytics"
  type        = number
  default     = 30
  validation {
    condition     = var.log_analytics_retention_days >= 30 && var.log_analytics_retention_days <= 730
    error_message = "Log Analytics retention days must be between 30 and 730."
  }
}

variable "enable_diagnostic_logs" {
  description = "Enable diagnostic logging for Azure services"
  type        = bool
  default     = true
}

variable "tags" {
  description = "A map of tags to assign to all resources"
  type        = map(string)
  default = {
    Environment = "Demo"
    Purpose     = "Healthcare Edge Analytics"
    Project     = "Azure SQL Edge Health Data Services"
  }
}