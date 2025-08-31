# Input Variables for Simple Uptime Checker Infrastructure
# This file defines all configurable parameters for the uptime monitoring solution

variable "location" {
  description = "The Azure region where all resources will be deployed"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "North Central US", "South Central US", "West Central US",
      "Canada Central", "Canada East", "Brazil South", "UK South", "UK West",
      "West Europe", "North Europe", "France Central", "Germany West Central",
      "Switzerland North", "Norway East", "Sweden Central",
      "Australia East", "Australia Southeast", "Japan East", "Japan West",
      "Korea Central", "Southeast Asia", "East Asia", "Central India", "South India"
    ], var.location)
    error_message = "Location must be a valid Azure region."
  }
}

variable "resource_group_name" {
  description = "Name of the Azure Resource Group to contain all resources"
  type        = string
  default     = ""
  
  validation {
    condition     = var.resource_group_name == "" || can(regex("^[a-zA-Z0-9._\\-]+$", var.resource_group_name))
    error_message = "Resource group name can only contain alphanumeric characters, periods, underscores, and hyphens."
  }
}

variable "environment" {
  description = "Environment tag for resource organization (dev, staging, prod)"
  type        = string
  default     = "demo"
  
  validation {
    condition     = contains(["dev", "staging", "prod", "demo", "test"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod, demo, test."
  }
}

variable "project_name" {
  description = "Project name used for resource naming and tagging"
  type        = string
  default     = "uptime-checker"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "websites_to_monitor" {
  description = "List of website URLs to monitor for uptime"
  type        = list(string)
  default = [
    "https://www.microsoft.com",
    "https://azure.microsoft.com",
    "https://github.com"
  ]
  
  validation {
    condition     = length(var.websites_to_monitor) > 0 && length(var.websites_to_monitor) <= 20
    error_message = "Must specify between 1 and 20 websites to monitor."
  }
}

variable "monitoring_frequency" {
  description = "CRON expression for monitoring frequency (default: every 5 minutes)"
  type        = string
  default     = "0 */5 * * * *"
  
  validation {
    condition     = can(regex("^[0-9*,/-]+ [0-9*,/-]+ [0-9*,/-]+ [0-9*,/-]+ [0-9*,/-]+ [0-9*,/-]+$", var.monitoring_frequency))
    error_message = "Monitoring frequency must be a valid CRON expression (6 parts)."
  }
}

variable "function_timeout" {
  description = "Function execution timeout in minutes"
  type        = number
  default     = 5
  
  validation {
    condition     = var.function_timeout >= 1 && var.function_timeout <= 10
    error_message = "Function timeout must be between 1 and 10 minutes."
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
  description = "Storage account replication type for redundancy"
  type        = string
  default     = "LRS"
  
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_account_replication_type)
    error_message = "Storage replication type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

variable "app_insights_retention_days" {
  description = "Number of days to retain Application Insights data"
  type        = number
  default     = 90
  
  validation {
    condition     = contains([30, 60, 90, 120, 180, 270, 365, 550, 730], var.app_insights_retention_days)
    error_message = "Retention days must be one of: 30, 60, 90, 120, 180, 270, 365, 550, 730."
  }
}

variable "enable_alerting" {
  description = "Enable Application Insights alerting for downtime detection"
  type        = bool
  default     = true
}

variable "alert_severity" {
  description = "Severity level for downtime alerts (0=Critical, 1=Error, 2=Warning, 3=Informational)"
  type        = number
  default     = 2
  
  validation {
    condition     = var.alert_severity >= 0 && var.alert_severity <= 4
    error_message = "Alert severity must be between 0 (Critical) and 4 (Verbose)."
  }
}

variable "alert_frequency_minutes" {
  description = "How often to evaluate alert conditions (in minutes)"
  type        = number
  default     = 5
  
  validation {
    condition     = contains([1, 5, 10, 15, 30, 60], var.alert_frequency_minutes)
    error_message = "Alert frequency must be one of: 1, 5, 10, 15, 30, 60 minutes."
  }
}

variable "alert_window_minutes" {
  description = "Time window for alert evaluation (in minutes)"
  type        = number
  default     = 10
  
  validation {
    condition     = var.alert_window_minutes >= var.alert_frequency_minutes && var.alert_window_minutes <= 2880
    error_message = "Alert window must be at least as long as alert frequency and no more than 2880 minutes (48 hours)."
  }
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
  
  validation {
    condition     = length(var.tags) <= 15
    error_message = "Cannot specify more than 15 additional tags."
  }
}