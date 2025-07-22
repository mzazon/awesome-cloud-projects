# Variables for Azure health monitoring infrastructure

variable "location" {
  description = "The Azure region where resources will be deployed"
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
      "Japan West", "Korea Central", "Central India", "South India", "West India"
    ], var.location)
    error_message = "Location must be a valid Azure region."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "health-monitoring"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "resource_group_name" {
  description = "Name of the resource group (will be auto-generated if not provided)"
  type        = string
  default     = ""
}

variable "service_bus_sku" {
  description = "Service Bus namespace SKU"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.service_bus_sku)
    error_message = "Service Bus SKU must be Basic, Standard, or Premium."
  }
}

variable "service_bus_capacity" {
  description = "Service Bus namespace capacity (only for Premium SKU)"
  type        = number
  default     = 1
  
  validation {
    condition     = var.service_bus_capacity >= 1 && var.service_bus_capacity <= 16
    error_message = "Service Bus capacity must be between 1 and 16."
  }
}

variable "health_queue_max_size" {
  description = "Maximum size of the health events queue in MB"
  type        = number
  default     = 2048
  
  validation {
    condition     = contains([1024, 2048, 3072, 4096, 5120], var.health_queue_max_size)
    error_message = "Queue max size must be one of: 1024, 2048, 3072, 4096, 5120 MB."
  }
}

variable "remediation_topic_max_size" {
  description = "Maximum size of the remediation topic in MB"
  type        = number
  default     = 2048
  
  validation {
    condition     = contains([1024, 2048, 3072, 4096, 5120], var.remediation_topic_max_size)
    error_message = "Topic max size must be one of: 1024, 2048, 3072, 4096, 5120 MB."
  }
}

variable "log_analytics_sku" {
  description = "SKU for Log Analytics workspace"
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
    condition     = var.log_analytics_retention_days >= 30 && var.log_analytics_retention_days <= 730
    error_message = "Log retention must be between 30 and 730 days."
  }
}

variable "create_demo_vm" {
  description = "Whether to create a demo VM for testing health monitoring"
  type        = bool
  default     = true
}

variable "vm_admin_username" {
  description = "Admin username for the demo VM"
  type        = string
  default     = "azureuser"
  
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9]{2,19}$", var.vm_admin_username))
    error_message = "VM admin username must be 3-20 characters, start with a letter, and contain only letters and numbers."
  }
}

variable "vm_size" {
  description = "Size of the demo VM"
  type        = string
  default     = "Standard_B1s"
}

variable "enable_duplicate_detection" {
  description = "Enable duplicate detection for Service Bus queue and topic"
  type        = bool
  default     = true
}

variable "duplicate_detection_history_time_window" {
  description = "Time window for duplicate detection in minutes"
  type        = string
  default     = "PT10M"
  
  validation {
    condition     = can(regex("^PT[0-9]+M$", var.duplicate_detection_history_time_window))
    error_message = "Duplicate detection time window must be in ISO 8601 duration format (e.g., PT10M for 10 minutes)."
  }
}

variable "max_delivery_count" {
  description = "Maximum delivery count for Service Bus subscriptions"
  type        = number
  default     = 3
  
  validation {
    condition     = var.max_delivery_count >= 1 && var.max_delivery_count <= 10
    error_message = "Max delivery count must be between 1 and 10."
  }
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Purpose     = "health-monitoring"
    Environment = "demo"
    Terraform   = "true"
  }
}