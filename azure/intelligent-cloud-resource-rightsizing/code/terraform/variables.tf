# Input Variables for Azure Resource Rightsizing Automation
# This file defines all the configurable parameters for the infrastructure deployment

variable "location" {
  description = "Azure region for resource deployment"
  type        = string
  default     = "East US"
  
  validation {
    condition = can(regex("^[A-Za-z]", var.location))
    error_message = "Location must be a valid Azure region name."
  }
}

variable "resource_group_name" {
  description = "Name of the Azure resource group"
  type        = string
  default     = null
  
  validation {
    condition = var.resource_group_name == null || can(regex("^[a-zA-Z0-9._-]+$", var.resource_group_name))
    error_message = "Resource group name must contain only alphanumeric characters, periods, underscores, and hyphens."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "rightsizing"
  
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "function_app_sku" {
  description = "SKU for the Function App hosting plan"
  type        = string
  default     = "Y1"
  
  validation {
    condition = contains(["Y1", "EP1", "EP2", "EP3"], var.function_app_sku)
    error_message = "Function App SKU must be one of: Y1 (Consumption), EP1, EP2, EP3 (Elastic Premium)."
  }
}

variable "storage_account_tier" {
  description = "Storage account tier for Function App storage"
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
    error_message = "Storage replication type must be one of: LRS, GRS, RAGRS, ZRS."
  }
}

variable "log_analytics_sku" {
  description = "SKU for Log Analytics workspace"
  type        = string
  default     = "PerGB2018"
  
  validation {
    condition = contains(["Free", "PerNode", "PerGB2018", "Standard", "Premium"], var.log_analytics_sku)
    error_message = "Log Analytics SKU must be one of: Free, PerNode, PerGB2018, Standard, Premium."
  }
}

variable "log_retention_days" {
  description = "Number of days to retain log data"
  type        = number
  default     = 30
  
  validation {
    condition = var.log_retention_days >= 7 && var.log_retention_days <= 730
    error_message = "Log retention days must be between 7 and 730."
  }
}

variable "cost_budget_amount" {
  description = "Monthly budget amount for cost alerts (in USD)"
  type        = number
  default     = 100
  
  validation {
    condition = var.cost_budget_amount > 0
    error_message = "Budget amount must be greater than 0."
  }
}

variable "cost_alert_threshold" {
  description = "Percentage threshold for cost alerts (0-100)"
  type        = number
  default     = 80
  
  validation {
    condition = var.cost_alert_threshold > 0 && var.cost_alert_threshold <= 100
    error_message = "Cost alert threshold must be between 0 and 100."
  }
}

variable "notification_email" {
  description = "Email address for notifications and alerts"
  type        = string
  default     = "admin@company.com"
  
  validation {
    condition = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address."
  }
}

variable "rightsizing_schedule" {
  description = "Cron expression for rightsizing analysis schedule"
  type        = string
  default     = "0 0 2 * * *"  # Daily at 2 AM
  
  validation {
    condition = can(regex("^[0-9*,-/ ]+$", var.rightsizing_schedule))
    error_message = "Rightsizing schedule must be a valid cron expression."
  }
}

variable "cpu_threshold_low" {
  description = "CPU utilization threshold for downsizing recommendation (percentage)"
  type        = number
  default     = 20
  
  validation {
    condition = var.cpu_threshold_low > 0 && var.cpu_threshold_low < 100
    error_message = "CPU threshold low must be between 0 and 100."
  }
}

variable "cpu_threshold_high" {
  description = "CPU utilization threshold for upsizing recommendation (percentage)"
  type        = number
  default     = 80
  
  validation {
    condition = var.cpu_threshold_high > 0 && var.cpu_threshold_high < 100
    error_message = "CPU threshold high must be between 0 and 100."
  }
}

variable "analysis_period_days" {
  description = "Number of days to analyze for rightsizing recommendations"
  type        = number
  default     = 7
  
  validation {
    condition = var.analysis_period_days >= 1 && var.analysis_period_days <= 30
    error_message = "Analysis period must be between 1 and 30 days."
  }
}

variable "enable_auto_scaling" {
  description = "Enable automatic scaling actions (requires proper permissions)"
  type        = bool
  default     = false
}

variable "enable_cost_alerts" {
  description = "Enable cost management alerts and budgets"
  type        = bool
  default     = true
}

variable "enable_test_resources" {
  description = "Deploy test resources for validation purposes"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default = {
    Purpose     = "rightsizing-automation"
    Environment = "demo"
    Project     = "cost-optimization"
    ManagedBy   = "terraform"
  }
}

# Data source for current client configuration
data "azurerm_client_config" "current" {}