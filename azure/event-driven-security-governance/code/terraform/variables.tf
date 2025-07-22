# Variables for Azure security governance automation infrastructure

variable "resource_group_name" {
  description = "Name of the resource group for security governance resources"
  type        = string
  default     = "rg-security-governance"
}

variable "location" {
  description = "Azure region for resource deployment"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "Central US", "North Central US", "South Central US", 
      "West Central US", "West US", "West US 2", "West US 3", "Canada Central", 
      "Canada East", "North Europe", "West Europe", "UK South", "UK West", 
      "Southeast Asia", "East Asia", "Australia East", "Australia Southeast"
    ], var.location)
    error_message = "The location must be a valid Azure region."
  }
}

variable "environment" {
  description = "Environment name for resource tagging"
  type        = string
  default     = "demo"
  
  validation {
    condition     = length(var.environment) <= 8
    error_message = "Environment name must be 8 characters or less."
  }
}

variable "owner" {
  description = "Owner tag for resource identification"
  type        = string
  default     = "admin"
}

variable "random_suffix" {
  description = "Random suffix for unique resource naming"
  type        = string
  default     = ""
}

variable "event_grid_topic_name" {
  description = "Name of the Event Grid custom topic"
  type        = string
  default     = "eg-security-governance"
}

variable "function_app_name" {
  description = "Name of the Azure Function App"
  type        = string
  default     = "func-security"
}

variable "storage_account_name" {
  description = "Name of the storage account for Function App"
  type        = string
  default     = "stsecurity"
}

variable "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  type        = string
  default     = "law-security"
}

variable "action_group_name" {
  description = "Name of the Azure Monitor Action Group"
  type        = string
  default     = "ag-security"
}

variable "notification_email" {
  description = "Email address for security alert notifications"
  type        = string
  default     = "security@company.com"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Please provide a valid email address."
  }
}

variable "function_app_plan_sku" {
  description = "SKU for the App Service Plan (Y1 for Consumption, EP1 for Premium)"
  type        = string
  default     = "Y1"
  
  validation {
    condition     = contains(["Y1", "EP1", "EP2", "EP3"], var.function_app_plan_sku)
    error_message = "Function App plan SKU must be Y1 (Consumption) or EP1/EP2/EP3 (Premium)."
  }
}

variable "log_analytics_sku" {
  description = "SKU for Log Analytics workspace"
  type        = string
  default     = "PerGB2018"
  
  validation {
    condition     = contains(["Free", "PerNode", "PerGB2018", "Standalone"], var.log_analytics_sku)
    error_message = "Log Analytics SKU must be Free, PerNode, PerGB2018, or Standalone."
  }
}

variable "storage_account_tier" {
  description = "Performance tier for storage account"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be Standard or Premium."
  }
}

variable "storage_account_replication_type" {
  description = "Replication type for storage account"
  type        = string
  default     = "LRS"
  
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_account_replication_type)
    error_message = "Storage account replication type must be LRS, GRS, RAGRS, ZRS, GZRS, or RAGZRS."
  }
}

variable "enable_application_insights" {
  description = "Enable Application Insights for Function App monitoring"
  type        = bool
  default     = true
}

variable "enable_advanced_threat_protection" {
  description = "Enable Advanced Threat Protection for storage account"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Log retention period in days for Log Analytics workspace"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_retention_days >= 7 && var.log_retention_days <= 730
    error_message = "Log retention days must be between 7 and 730."
  }
}

variable "alert_evaluation_frequency" {
  description = "Alert evaluation frequency in minutes"
  type        = string
  default     = "PT1M"
  
  validation {
    condition     = contains(["PT1M", "PT5M", "PT15M", "PT30M", "PT1H"], var.alert_evaluation_frequency)
    error_message = "Alert evaluation frequency must be PT1M, PT5M, PT15M, PT30M, or PT1H."
  }
}

variable "alert_window_size" {
  description = "Alert window size in minutes"
  type        = string
  default     = "PT5M"
  
  validation {
    condition     = contains(["PT1M", "PT5M", "PT15M", "PT30M", "PT1H", "PT6H", "PT12H", "PT24H"], var.alert_window_size)
    error_message = "Alert window size must be PT1M, PT5M, PT15M, PT30M, PT1H, PT6H, PT12H, or PT24H."
  }
}

variable "security_violation_threshold" {
  description = "Threshold for security violation alerts"
  type        = number
  default     = 5
  
  validation {
    condition     = var.security_violation_threshold > 0
    error_message = "Security violation threshold must be greater than 0."
  }
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default = {
    purpose     = "security-governance"
    compliance  = "required"
    managed-by  = "terraform"
  }
}