# Input variables for the Azure Cost Optimization infrastructure
# These variables allow customization of the deployment

variable "resource_group_name" {
  description = "Name of the resource group for cost optimization resources"
  type        = string
  default     = null
  
  validation {
    condition     = var.resource_group_name == null || can(regex("^[a-zA-Z0-9-_()]+$", var.resource_group_name))
    error_message = "Resource group name must contain only alphanumeric characters, hyphens, underscores, and parentheses."
  }
}

variable "location" {
  description = "Azure region for resource deployment"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "North Central US", "South Central US", "West Central US",
      "Canada Central", "Canada East", "Brazil South", "North Europe", "West Europe",
      "UK South", "UK West", "France Central", "Germany West Central",
      "Switzerland North", "Norway East", "Sweden Central", "Poland Central",
      "Italy North", "Australia East", "Australia Southeast", "Australia Central",
      "Japan East", "Japan West", "Korea Central", "Korea South",
      "Southeast Asia", "East Asia", "India Central", "India South", "India West"
    ], var.location)
    error_message = "Location must be a valid Azure region."
  }
}

variable "environment" {
  description = "Environment tag for resources (dev, staging, production)"
  type        = string
  default     = "production"
  
  validation {
    condition     = contains(["dev", "staging", "production"], var.environment)
    error_message = "Environment must be one of: dev, staging, production."
  }
}

variable "project_name" {
  description = "Project name used for resource naming and tagging"
  type        = string
  default     = "costopt"
  
  validation {
    condition     = can(regex("^[a-z0-9]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters and numbers."
  }
}

variable "log_analytics_retention_days" {
  description = "Number of days to retain data in Log Analytics workspace"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_analytics_retention_days >= 30 && var.log_analytics_retention_days <= 730
    error_message = "Log Analytics retention must be between 30 and 730 days."
  }
}

variable "budget_amount" {
  description = "Monthly budget amount in USD for cost alerts"
  type        = number
  default     = 5000
  
  validation {
    condition     = var.budget_amount > 0
    error_message = "Budget amount must be greater than 0."
  }
}

variable "cost_alert_threshold" {
  description = "Percentage of budget that triggers cost alerts (1-100)"
  type        = number
  default     = 80
  
  validation {
    condition     = var.cost_alert_threshold > 0 && var.cost_alert_threshold <= 100
    error_message = "Cost alert threshold must be between 1 and 100."
  }
}

variable "alert_email_addresses" {
  description = "List of email addresses to receive cost alerts"
  type        = list(string)
  default     = ["admin@example.com"]
  
  validation {
    condition = alltrue([
      for email in var.alert_email_addresses : can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", email))
    ])
    error_message = "All email addresses must be valid."
  }
}

variable "automation_account_sku" {
  description = "SKU for the Azure Automation Account"
  type        = string
  default     = "Basic"
  
  validation {
    condition     = contains(["Basic", "Standard"], var.automation_account_sku)
    error_message = "Automation Account SKU must be either Basic or Standard."
  }
}

variable "enable_cost_anomaly_detection" {
  description = "Enable cost anomaly detection alerts"
  type        = bool
  default     = true
}

variable "enable_vm_optimization" {
  description = "Enable VM optimization runbooks"
  type        = bool
  default     = true
}

variable "enable_storage_optimization" {
  description = "Enable storage optimization runbooks"
  type        = bool
  default     = true
}

variable "optimization_schedule" {
  description = "Cron schedule for automated optimization (UTC timezone)"
  type        = string
  default     = "0 2 * * *"  # Daily at 2 AM UTC
  
  validation {
    condition     = can(regex("^[0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+$", var.optimization_schedule))
    error_message = "Optimization schedule must be a valid cron expression."
  }
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}