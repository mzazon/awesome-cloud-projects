# Input variables for Azure Batch and Compute Fleet configuration

variable "location" {
  description = "The Azure region where all resources will be created"
  type        = string
  default     = "eastus"
  
  validation {
    condition = can(regex("^[a-z0-9]+$", var.location))
    error_message = "Location must be a valid Azure region name in lowercase."
  }
}

variable "resource_group_name" {
  description = "Name of the resource group to create"
  type        = string
  default     = null
  
  validation {
    condition = var.resource_group_name == null || can(regex("^[a-zA-Z0-9-_]+$", var.resource_group_name))
    error_message = "Resource group name must contain only alphanumeric characters, hyphens, and underscores."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "demo"
  
  validation {
    condition = contains(["dev", "staging", "prod", "demo"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod, demo."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "batch-fleet"
  
  validation {
    condition = can(regex("^[a-zA-Z0-9-]+$", var.project_name))
    error_message = "Project name must contain only alphanumeric characters and hyphens."
  }
}

variable "storage_account_tier" {
  description = "Storage account performance tier"
  type        = string
  default     = "Standard"
  
  validation {
    condition = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be either Standard or Premium."
  }
}

variable "storage_account_replication_type" {
  description = "Storage account replication type"
  type        = string
  default     = "LRS"
  
  validation {
    condition = contains(["LRS", "GRS", "RAGRS", "ZRS"], var.storage_account_replication_type)
    error_message = "Storage account replication type must be LRS, GRS, RAGRS, or ZRS."
  }
}

variable "batch_pool_vm_size" {
  description = "VM size for batch pool nodes"
  type        = string
  default     = "Standard_D2s_v3"
  
  validation {
    condition = can(regex("^Standard_[A-Z0-9]+[a-z]*_v[0-9]+$", var.batch_pool_vm_size))
    error_message = "VM size must be a valid Azure VM size (e.g., Standard_D2s_v3)."
  }
}

variable "batch_pool_target_dedicated_nodes" {
  description = "Target number of dedicated nodes in the batch pool"
  type        = number
  default     = 0
  
  validation {
    condition = var.batch_pool_target_dedicated_nodes >= 0 && var.batch_pool_target_dedicated_nodes <= 100
    error_message = "Target dedicated nodes must be between 0 and 100."
  }
}

variable "batch_pool_target_low_priority_nodes" {
  description = "Target number of low priority nodes in the batch pool"
  type        = number
  default     = 10
  
  validation {
    condition = var.batch_pool_target_low_priority_nodes >= 0 && var.batch_pool_target_low_priority_nodes <= 100
    error_message = "Target low priority nodes must be between 0 and 100."
  }
}

variable "batch_pool_max_nodes" {
  description = "Maximum number of nodes for auto-scaling"
  type        = number
  default     = 20
  
  validation {
    condition = var.batch_pool_max_nodes >= 1 && var.batch_pool_max_nodes <= 1000
    error_message = "Maximum nodes must be between 1 and 1000."
  }
}

variable "compute_fleet_spot_capacity_percentage" {
  description = "Percentage of compute fleet capacity to allocate to spot instances"
  type        = number
  default     = 80
  
  validation {
    condition = var.compute_fleet_spot_capacity_percentage >= 0 && var.compute_fleet_spot_capacity_percentage <= 100
    error_message = "Spot capacity percentage must be between 0 and 100."
  }
}

variable "compute_fleet_max_price_per_vm" {
  description = "Maximum price per VM for spot instances (in USD)"
  type        = number
  default     = 0.05
  
  validation {
    condition = var.compute_fleet_max_price_per_vm > 0 && var.compute_fleet_max_price_per_vm <= 10
    error_message = "Maximum price per VM must be between 0 and 10 USD."
  }
}

variable "admin_username" {
  description = "Administrator username for batch pool VMs"
  type        = string
  default     = "batchadmin"
  
  validation {
    condition = can(regex("^[a-zA-Z][a-zA-Z0-9]{2,15}$", var.admin_username))
    error_message = "Admin username must be 3-16 characters, start with a letter, and contain only letters and numbers."
  }
}

variable "admin_password" {
  description = "Administrator password for batch pool VMs"
  type        = string
  default     = "BatchP@ssw0rd123!"
  sensitive   = true
  
  validation {
    condition = length(var.admin_password) >= 12
    error_message = "Admin password must be at least 12 characters long."
  }
}

variable "log_analytics_retention_days" {
  description = "Number of days to retain logs in Log Analytics workspace"
  type        = number
  default     = 30
  
  validation {
    condition = var.log_analytics_retention_days >= 7 && var.log_analytics_retention_days <= 730
    error_message = "Log retention days must be between 7 and 730."
  }
}

variable "cost_budget_amount" {
  description = "Monthly budget amount for cost management (in USD)"
  type        = number
  default     = 100
  
  validation {
    condition = var.cost_budget_amount > 0
    error_message = "Budget amount must be greater than 0."
  }
}

variable "cost_alert_threshold" {
  description = "Percentage threshold for cost alerts"
  type        = number
  default     = 80
  
  validation {
    condition = var.cost_alert_threshold > 0 && var.cost_alert_threshold <= 100
    error_message = "Cost alert threshold must be between 0 and 100."
  }
}

variable "notification_email" {
  description = "Email address for cost and performance notifications"
  type        = string
  default     = "admin@example.com"
  
  validation {
    condition = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address."
  }
}

variable "tags" {
  description = "Tags to be applied to all resources"
  type        = map(string)
  default = {
    Environment = "demo"
    Project     = "batch-fleet"
    Purpose     = "batch-processing"
    ManagedBy   = "terraform"
  }
}