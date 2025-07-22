# Core Resource Configuration
variable "resource_group_name" {
  description = "Name of the resource group for AI governance infrastructure"
  type        = string
  default     = "rg-ai-governance"
}

variable "location" {
  description = "Azure region for resource deployment"
  type        = string
  default     = "East US"
  
  validation {
    condition = can(regex("^[A-Za-z0-9 ]+$", var.location))
    error_message = "Location must be a valid Azure region name."
  }
}

variable "environment" {
  description = "Environment name for resource tagging"
  type        = string
  default     = "production"
  
  validation {
    condition = contains(["development", "staging", "production"], var.environment)
    error_message = "Environment must be one of: development, staging, production."
  }
}

# Naming and Tagging Configuration
variable "name_prefix" {
  description = "Prefix for resource naming convention"
  type        = string
  default     = "ai-governance"
  
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.name_prefix))
    error_message = "Name prefix must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default = {
    Purpose     = "AI Governance"
    Environment = "Production"
    Owner       = "Security Team"
    Project     = "AI Agent Management"
  }
}

# Log Analytics Configuration
variable "log_analytics_sku" {
  description = "SKU for Log Analytics workspace"
  type        = string
  default     = "PerGB2018"
  
  validation {
    condition = contains(["Free", "PerNode", "PerGB2018", "Standalone"], var.log_analytics_sku)
    error_message = "Log Analytics SKU must be one of: Free, PerNode, PerGB2018, Standalone."
  }
}

variable "log_retention_days" {
  description = "Number of days to retain logs in Log Analytics workspace"
  type        = number
  default     = 30
  
  validation {
    condition = var.log_retention_days >= 30 && var.log_retention_days <= 730
    error_message = "Log retention days must be between 30 and 730."
  }
}

# Key Vault Configuration
variable "key_vault_sku" {
  description = "SKU for Key Vault"
  type        = string
  default     = "standard"
  
  validation {
    condition = contains(["standard", "premium"], var.key_vault_sku)
    error_message = "Key Vault SKU must be either 'standard' or 'premium'."
  }
}

variable "key_vault_soft_delete_retention_days" {
  description = "Number of days to retain soft-deleted Key Vault items"
  type        = number
  default     = 90
  
  validation {
    condition = var.key_vault_soft_delete_retention_days >= 7 && var.key_vault_soft_delete_retention_days <= 90
    error_message = "Key Vault soft delete retention days must be between 7 and 90."
  }
}

variable "key_vault_purge_protection_enabled" {
  description = "Enable purge protection for Key Vault"
  type        = bool
  default     = true
}

# Logic Apps Configuration
variable "logic_app_lifecycle_schedule" {
  description = "Recurrence schedule for agent lifecycle management Logic App"
  type = object({
    frequency = string
    interval  = number
  })
  default = {
    frequency = "Hour"
    interval  = 1
  }
  
  validation {
    condition = contains(["Minute", "Hour", "Day", "Week", "Month"], var.logic_app_lifecycle_schedule.frequency)
    error_message = "Logic App frequency must be one of: Minute, Hour, Day, Week, Month."
  }
}

variable "logic_app_compliance_monitoring_enabled" {
  description = "Enable compliance monitoring Logic App"
  type        = bool
  default     = true
}

variable "logic_app_access_control_enabled" {
  description = "Enable access control Logic App"
  type        = bool
  default     = true
}

variable "logic_app_audit_schedule" {
  description = "Schedule for daily audit reporting Logic App"
  type = object({
    frequency  = string
    interval   = number
    start_time = string
  })
  default = {
    frequency  = "Day"
    interval   = 1
    start_time = "09:00:00"
  }
}

variable "logic_app_monitoring_interval" {
  description = "Interval in minutes for performance monitoring Logic App"
  type        = number
  default     = 15
  
  validation {
    condition = var.logic_app_monitoring_interval >= 5 && var.logic_app_monitoring_interval <= 60
    error_message = "Monitoring interval must be between 5 and 60 minutes."
  }
}

# Security Configuration
variable "allowed_ip_ranges" {
  description = "IP ranges allowed to access Key Vault"
  type        = list(string)
  default     = []
}

variable "enable_private_endpoints" {
  description = "Enable private endpoints for services"
  type        = bool
  default     = false
}

# Agent ID Configuration
variable "entra_agent_id_preview_enabled" {
  description = "Enable Azure Entra Agent ID preview features"
  type        = bool
  default     = true
}

# Storage Account Configuration
variable "storage_account_tier" {
  description = "Performance tier for storage account"
  type        = string
  default     = "Standard"
  
  validation {
    condition = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be either 'Standard' or 'Premium'."
  }
}

variable "storage_account_replication_type" {
  description = "Replication type for storage account"
  type        = string
  default     = "LRS"
  
  validation {
    condition = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_account_replication_type)
    error_message = "Storage account replication type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

# Monitoring and Alerting Configuration
variable "enable_application_insights" {
  description = "Enable Application Insights for Logic Apps monitoring"
  type        = bool
  default     = true
}

variable "alert_email_addresses" {
  description = "Email addresses for governance alerts"
  type        = list(string)
  default     = []
}

variable "alert_severity_level" {
  description = "Severity level for governance alerts"
  type        = number
  default     = 2
  
  validation {
    condition = var.alert_severity_level >= 0 && var.alert_severity_level <= 4
    error_message = "Alert severity level must be between 0 and 4."
  }
}

# Cost Management Configuration
variable "enable_cost_alerts" {
  description = "Enable cost management alerts"
  type        = bool
  default     = true
}

variable "monthly_budget_amount" {
  description = "Monthly budget amount for cost alerts (in USD)"
  type        = number
  default     = 500
  
  validation {
    condition = var.monthly_budget_amount > 0
    error_message = "Monthly budget amount must be greater than 0."
  }
}