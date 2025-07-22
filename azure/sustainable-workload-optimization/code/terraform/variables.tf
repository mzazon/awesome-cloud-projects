# Variables for Azure sustainable workload optimization infrastructure

variable "resource_group_name" {
  description = "Name of the resource group for carbon optimization resources"
  type        = string
  default     = "rg-carbon-optimization"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]+$", var.resource_group_name))
    error_message = "Resource group name must contain only alphanumeric characters, hyphens, and underscores."
  }
}

variable "location" {
  description = "Azure region for deploying resources"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "South Central US", "North Central US", "West Central US",
      "Canada Central", "Canada East", "Brazil South", "North Europe", "West Europe",
      "France Central", "Germany West Central", "Norway East", "Switzerland North",
      "UK South", "UK West", "Australia East", "Australia Southeast", "East Asia",
      "Southeast Asia", "Japan East", "Japan West", "Korea Central", "South India",
      "Central India", "West India", "South Africa North", "UAE North"
    ], var.location)
    error_message = "The location must be a valid Azure region."
  }
}

variable "environment" {
  description = "Environment designation for resource tagging"
  type        = string
  default     = "production"
  
  validation {
    condition     = contains(["development", "testing", "staging", "production"], var.environment)
    error_message = "Environment must be one of: development, testing, staging, production."
  }
}

variable "project_name" {
  description = "Name of the project for resource tagging and naming"
  type        = string
  default     = "carbon-optimization"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.project_name))
    error_message = "Project name must contain only alphanumeric characters and hyphens."
  }
}

variable "log_analytics_workspace_sku" {
  description = "SKU for the Log Analytics workspace"
  type        = string
  default     = "PerGB2018"
  
  validation {
    condition     = contains(["Free", "PerNode", "Premium", "Standard", "Standalone", "Unlimited", "CapacityReservation", "PerGB2018"], var.log_analytics_workspace_sku)
    error_message = "Log Analytics workspace SKU must be a valid pricing tier."
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

variable "automation_account_sku" {
  description = "SKU for the Azure Automation account"
  type        = string
  default     = "Basic"
  
  validation {
    condition     = contains(["Free", "Basic"], var.automation_account_sku)
    error_message = "Automation account SKU must be either Free or Basic."
  }
}

variable "monitoring_schedule_frequency" {
  description = "Frequency for the carbon monitoring schedule"
  type        = string
  default     = "Day"
  
  validation {
    condition     = contains(["OneTime", "Day", "Hour", "Week", "Month"], var.monitoring_schedule_frequency)
    error_message = "Schedule frequency must be one of: OneTime, Day, Hour, Week, Month."
  }
}

variable "monitoring_schedule_interval" {
  description = "Interval for the carbon monitoring schedule"
  type        = number
  default     = 1
  
  validation {
    condition     = var.monitoring_schedule_interval >= 1 && var.monitoring_schedule_interval <= 100
    error_message = "Schedule interval must be between 1 and 100."
  }
}

variable "carbon_optimization_threshold" {
  description = "Threshold for carbon optimization alerts (in kg CO2)"
  type        = number
  default     = 100
  
  validation {
    condition     = var.carbon_optimization_threshold > 0
    error_message = "Carbon optimization threshold must be greater than 0."
  }
}

variable "admin_email" {
  description = "Email address for carbon optimization alerts"
  type        = string
  default     = "admin@company.com"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.admin_email))
    error_message = "Admin email must be a valid email address."
  }
}

variable "slack_webhook_url" {
  description = "Slack webhook URL for carbon optimization notifications (optional)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "enable_workbook" {
  description = "Enable deployment of Azure Monitor Workbook for carbon optimization dashboard"
  type        = bool
  default     = true
}

variable "enable_automation" {
  description = "Enable automated remediation capabilities"
  type        = bool
  default     = true
}

variable "enable_alerts" {
  description = "Enable carbon optimization alerts"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "resource_suffix" {
  description = "Suffix to append to resource names for uniqueness"
  type        = string
  default     = ""
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9]*$", var.resource_suffix))
    error_message = "Resource suffix must contain only alphanumeric characters."
  }
}

variable "enable_rbac" {
  description = "Enable role-based access control for carbon optimization"
  type        = bool
  default     = true
}

variable "backup_retention_days" {
  description = "Number of days to retain automation account backups"
  type        = number
  default     = 35
  
  validation {
    condition     = var.backup_retention_days >= 7 && var.backup_retention_days <= 99
    error_message = "Backup retention must be between 7 and 99 days."
  }
}