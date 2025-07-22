# Input variables for the IoT Edge-to-Cloud Security Updates infrastructure
# These variables allow customization of the deployment

variable "location" {
  description = "The Azure region where all resources will be deployed"
  type        = string
  default     = "East US"

  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "South Central US", "North Central US", "West Central US",
      "Canada Central", "Canada East", "Brazil South",
      "North Europe", "West Europe", "UK South", "UK West",
      "France Central", "Germany West Central", "Norway East",
      "Switzerland North", "Sweden Central",
      "Asia Pacific", "Southeast Asia", "East Asia",
      "Australia East", "Australia Southeast", "Central India",
      "South India", "West India", "Japan East", "Japan West",
      "Korea Central", "South Africa North"
    ], var.location)
    error_message = "The location must be a valid Azure region."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "demo"

  validation {
    condition     = length(var.environment) <= 10 && can(regex("^[a-z0-9]+$", var.environment))
    error_message = "Environment must be lowercase alphanumeric and max 10 characters."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming and tagging"
  type        = string
  default     = "iot-updates"

  validation {
    condition     = length(var.project_name) <= 15 && can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must be lowercase alphanumeric with dashes and max 15 characters."
  }
}

variable "resource_group_name" {
  description = "Name of the resource group (leave empty to auto-generate)"
  type        = string
  default     = ""
}

variable "iot_hub_sku" {
  description = "SKU tier for the IoT Hub (F1, S1, S2, S3)"
  type        = string
  default     = "S1"

  validation {
    condition     = contains(["F1", "S1", "S2", "S3"], var.iot_hub_sku)
    error_message = "IoT Hub SKU must be one of: F1, S1, S2, S3."
  }
}

variable "iot_hub_capacity" {
  description = "Number of IoT Hub units (capacity)"
  type        = number
  default     = 1

  validation {
    condition     = var.iot_hub_capacity >= 1 && var.iot_hub_capacity <= 200
    error_message = "IoT Hub capacity must be between 1 and 200."
  }
}

variable "storage_account_tier" {
  description = "Storage account performance tier (Standard or Premium)"
  type        = string
  default     = "Standard"

  validation {
    condition     = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be either Standard or Premium."
  }
}

variable "storage_account_replication_type" {
  description = "Storage account replication type (LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS)"
  type        = string
  default     = "LRS"

  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_account_replication_type)
    error_message = "Storage replication type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

variable "vm_size" {
  description = "Size of the test virtual machine"
  type        = string
  default     = "Standard_B2s"

  validation {
    condition     = can(regex("^Standard_[A-Z][0-9]+[a-z]*$", var.vm_size))
    error_message = "VM size must be a valid Azure VM size (e.g., Standard_B2s)."
  }
}

variable "vm_admin_username" {
  description = "Administrator username for the test VM"
  type        = string
  default     = "azureuser"

  validation {
    condition     = length(var.vm_admin_username) >= 1 && length(var.vm_admin_username) <= 20
    error_message = "VM admin username must be between 1 and 20 characters."
  }
}

variable "enable_test_vm" {
  description = "Whether to create a test VM for Update Manager demonstration"
  type        = bool
  default     = true
}

variable "enable_monitoring_alerts" {
  description = "Whether to enable monitoring and alerting for update operations"
  type        = bool
  default     = true
}

variable "log_analytics_sku" {
  description = "SKU for Log Analytics workspace (Free, Standalone, PerNode, PerGB2018)"
  type        = string
  default     = "PerGB2018"

  validation {
    condition     = contains(["Free", "Standalone", "PerNode", "PerGB2018"], var.log_analytics_sku)
    error_message = "Log Analytics SKU must be one of: Free, Standalone, PerNode, PerGB2018."
  }
}

variable "log_analytics_retention_days" {
  description = "Number of days to retain logs in Log Analytics workspace"
  type        = number
  default     = 30

  validation {
    condition     = var.log_analytics_retention_days >= 7 && var.log_analytics_retention_days <= 730
    error_message = "Log Analytics retention must be between 7 and 730 days."
  }
}

variable "device_update_location" {
  description = "Location for Device Update resources (may differ from main location due to availability)"
  type        = string
  default     = ""
}

variable "enable_device_simulation" {
  description = "Whether to create simulated IoT devices for testing"
  type        = bool
  default     = true
}

variable "simulated_device_count" {
  description = "Number of simulated IoT devices to create"
  type        = number
  default     = 1

  validation {
    condition     = var.simulated_device_count >= 0 && var.simulated_device_count <= 10
    error_message = "Simulated device count must be between 0 and 10."
  }
}

variable "tags" {
  description = "A map of tags to assign to all resources"
  type        = map(string)
  default = {
    Purpose     = "IoT Edge-to-Cloud Security Updates"
    Environment = "Demo"
    ManagedBy   = "Terraform"
  }
}

variable "enable_private_endpoints" {
  description = "Whether to enable private endpoints for enhanced security"
  type        = bool
  default     = false
}

variable "virtual_network_address_space" {
  description = "Address space for the virtual network (CIDR notation)"
  type        = list(string)
  default     = ["10.0.0.0/16"]

  validation {
    condition     = length(var.virtual_network_address_space) > 0
    error_message = "At least one address space must be specified for the virtual network."
  }
}

variable "subnet_address_prefix" {
  description = "Address prefix for the subnet (CIDR notation)"
  type        = string
  default     = "10.0.1.0/24"

  validation {
    condition     = can(cidrhost(var.subnet_address_prefix, 0))
    error_message = "Subnet address prefix must be a valid CIDR notation."
  }
}