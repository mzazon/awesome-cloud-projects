# Variables for Azure Cost Governance with Resource Graph and Power BI
# This file defines all input variables for the cost governance solution

variable "location" {
  description = "The Azure region where resources will be created"
  type        = string
  default     = "East US"
  
  validation {
    condition = can(regex("^[A-Za-z0-9 ]+$", var.location))
    error_message = "Location must be a valid Azure region name."
  }
}

variable "cost_threshold_monthly" {
  description = "Monthly cost threshold in USD for budget alerts"
  type        = string
  default     = "10000"
  
  validation {
    condition = can(tonumber(var.cost_threshold_monthly)) && tonumber(var.cost_threshold_monthly) > 0
    error_message = "Monthly cost threshold must be a positive number."
  }
}

variable "cost_threshold_daily" {
  description = "Daily cost threshold in USD for automated monitoring"
  type        = string
  default     = "500"
  
  validation {
    condition = can(tonumber(var.cost_threshold_daily)) && tonumber(var.cost_threshold_daily) > 0
    error_message = "Daily cost threshold must be a positive number."
  }
}

variable "alert_email_address" {
  description = "Email address for cost alert notifications"
  type        = string
  
  validation {
    condition = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.alert_email_address))
    error_message = "Alert email address must be a valid email format."
  }
}

variable "webhook_url" {
  description = "Webhook URL for external notification systems (e.g., Slack, Microsoft Teams)"
  type        = string
  default     = "https://hooks.slack.com/services/YOUR/WEBHOOK/URL"
  
  validation {
    condition = can(regex("^https?://", var.webhook_url))
    error_message = "Webhook URL must be a valid HTTP/HTTPS URL."
  }
}

variable "budget_start_date" {
  description = "Start date for the consumption budget in YYYY-MM-DD format"
  type        = string
  default     = "2025-01-01"
  
  validation {
    condition = can(regex("^\\d{4}-\\d{2}-\\d{2}$", var.budget_start_date))
    error_message = "Budget start date must be in YYYY-MM-DD format."
  }
}

variable "budget_end_date" {
  description = "End date for the consumption budget in YYYY-MM-DD format"
  type        = string
  default     = "2025-12-31"
  
  validation {
    condition = can(regex("^\\d{4}-\\d{2}-\\d{2}$", var.budget_end_date))
    error_message = "Budget end date must be in YYYY-MM-DD format."
  }
}

variable "logic_app_frequency" {
  description = "Frequency for Logic App recurrence trigger"
  type        = string
  default     = "Hour"
  
  validation {
    condition = contains(["Minute", "Hour", "Day", "Week", "Month"], var.logic_app_frequency)
    error_message = "Logic App frequency must be one of: Minute, Hour, Day, Week, Month."
  }
}

variable "logic_app_interval" {
  description = "Interval for Logic App recurrence trigger (works with frequency)"
  type        = number
  default     = 6
  
  validation {
    condition = var.logic_app_interval > 0 && var.logic_app_interval <= 100
    error_message = "Logic App interval must be between 1 and 100."
  }
}

variable "storage_account_tier" {
  description = "Storage account tier for cost governance data"
  type        = string
  default     = "Standard"
  
  validation {
    condition = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be either Standard or Premium."
  }
}

variable "storage_replication_type" {
  description = "Storage account replication type"
  type        = string
  default     = "LRS"
  
  validation {
    condition = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_replication_type)
    error_message = "Storage replication type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

variable "key_vault_sku" {
  description = "Key Vault SKU for secure configuration storage"
  type        = string
  default     = "standard"
  
  validation {
    condition = contains(["standard", "premium"], var.key_vault_sku)
    error_message = "Key Vault SKU must be either standard or premium."
  }
}

variable "enable_advanced_threat_protection" {
  description = "Enable advanced threat protection for storage account"
  type        = bool
  default     = true
}

variable "enable_key_vault_soft_delete" {
  description = "Enable soft delete for Key Vault"
  type        = bool
  default     = true
}

variable "soft_delete_retention_days" {
  description = "Number of days to retain soft deleted Key Vault items"
  type        = number
  default     = 7
  
  validation {
    condition = var.soft_delete_retention_days >= 7 && var.soft_delete_retention_days <= 90
    error_message = "Soft delete retention days must be between 7 and 90."
  }
}

variable "minimum_tls_version" {
  description = "Minimum TLS version for storage account"
  type        = string
  default     = "TLS1_2"
  
  validation {
    condition = contains(["TLS1_0", "TLS1_1", "TLS1_2"], var.minimum_tls_version)
    error_message = "Minimum TLS version must be one of: TLS1_0, TLS1_1, TLS1_2."
  }
}

variable "resource_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default = {
    Purpose     = "cost-governance"
    Environment = "production"
    ManagedBy   = "terraform"
  }
}

variable "enable_https_traffic_only" {
  description = "Enable HTTPS traffic only for storage account"
  type        = bool
  default     = true
}

variable "budget_notification_threshold_actual" {
  description = "Threshold percentage for actual spend budget notification"
  type        = number
  default     = 80.0
  
  validation {
    condition = var.budget_notification_threshold_actual > 0 && var.budget_notification_threshold_actual <= 100
    error_message = "Budget notification threshold for actual spend must be between 0 and 100."
  }
}

variable "budget_notification_threshold_forecasted" {
  description = "Threshold percentage for forecasted spend budget notification"
  type        = number
  default     = 100.0
  
  validation {
    condition = var.budget_notification_threshold_forecasted > 0 && var.budget_notification_threshold_forecasted <= 200
    error_message = "Budget notification threshold for forecasted spend must be between 0 and 200."
  }
}

variable "action_group_short_name" {
  description = "Short name for the action group (max 12 characters)"
  type        = string
  default     = "CostAlerts"
  
  validation {
    condition = length(var.action_group_short_name) <= 12
    error_message = "Action group short name must be 12 characters or less."
  }
}

variable "enable_rbac_authorization" {
  description = "Enable RBAC authorization for Key Vault"
  type        = bool
  default     = true
}

variable "purge_protection_enabled" {
  description = "Enable purge protection for Key Vault"
  type        = bool
  default     = false
}

variable "network_access_default_action" {
  description = "Default action for network access rules"
  type        = string
  default     = "Allow"
  
  validation {
    condition = contains(["Allow", "Deny"], var.network_access_default_action)
    error_message = "Network access default action must be either Allow or Deny."
  }
}

variable "create_sample_queries" {
  description = "Create sample Resource Graph queries for cost analysis"
  type        = bool
  default     = true
}

variable "powerbi_workspace_name" {
  description = "Name of the Power BI workspace for cost governance dashboards"
  type        = string
  default     = "Cost Governance Analytics"
}

variable "enable_diagnostic_logs" {
  description = "Enable diagnostic logging for cost governance resources"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Number of days to retain diagnostic logs"
  type        = number
  default     = 30
  
  validation {
    condition = var.log_retention_days >= 1 && var.log_retention_days <= 365
    error_message = "Log retention days must be between 1 and 365."
  }
}