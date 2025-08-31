# Input Variables for Budget Alert Notifications Infrastructure
# This file defines all configurable parameters for the deployment

# Environment and Location Configuration
variable "environment" {
  description = "Environment name for resource naming and tagging"
  type        = string
  default     = "demo"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.environment))
    error_message = "Environment must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "location" {
  description = "Azure region where resources will be deployed"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "North Central US", "South Central US", "West Central US",
      "Canada Central", "Canada East", "Brazil South", "UK South", "UK West",
      "West Europe", "North Europe", "France Central", "Germany West Central",
      "Switzerland North", "Norway East", "Sweden Central", "Poland Central",
      "Italy North", "Spain Central", "Australia East", "Australia Southeast",
      "East Asia", "Southeast Asia", "Japan East", "Japan West",
      "Korea Central", "Korea South", "India Central", "India South",
      "UAE North", "South Africa North"
    ], var.location)
    error_message = "Location must be a valid Azure region."
  }
}

# Resource Naming Configuration
variable "project_name" {
  description = "Project name used for resource naming and tagging"
  type        = string
  default     = "budget-alerts"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "name_suffix" {
  description = "Optional suffix for resource names to ensure uniqueness"
  type        = string
  default     = ""
  
  validation {
    condition     = can(regex("^[a-z0-9]*$", var.name_suffix))
    error_message = "Name suffix must contain only lowercase letters and numbers."
  }
}

# Budget Configuration
variable "budget_amount" {
  description = "Monthly budget amount in USD"
  type        = number
  default     = 100
  
  validation {
    condition     = var.budget_amount > 0 && var.budget_amount <= 100000
    error_message = "Budget amount must be between 1 and 100,000 USD."
  }
}

variable "budget_start_date" {
  description = "Budget start date in YYYY-MM-DD format"
  type        = string
  default     = "2025-01-01"
  
  validation {
    condition     = can(regex("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", var.budget_start_date))
    error_message = "Budget start date must be in YYYY-MM-DD format."
  }
}

variable "budget_end_date" {
  description = "Budget end date in YYYY-MM-DD format"
  type        = string
  default     = "2025-12-31"
  
  validation {
    condition     = can(regex("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", var.budget_end_date))
    error_message = "Budget end date must be in YYYY-MM-DD format."
  }
}

# Alert Threshold Configuration
variable "alert_thresholds" {
  description = "Budget alert thresholds configuration"
  type = map(object({
    enabled   = bool
    threshold = number
    operator  = string
  }))
  default = {
    "actual-80" = {
      enabled   = true
      threshold = 80
      operator  = "GreaterThan"
    }
    "forecasted-100" = {
      enabled   = true
      threshold = 100
      operator  = "GreaterThan"
    }
  }
  
  validation {
    condition = alltrue([
      for k, v in var.alert_thresholds : v.threshold >= 0 && v.threshold <= 1000
    ])
    error_message = "All alert thresholds must be between 0 and 1000."
  }
  
  validation {
    condition = alltrue([
      for k, v in var.alert_thresholds : contains(["GreaterThan", "GreaterThanOrEqual"], v.operator)
    ])
    error_message = "Alert operators must be either 'GreaterThan' or 'GreaterThanOrEqual'."
  }
}

# Email Configuration
variable "notification_emails" {
  description = "List of email addresses to receive budget notifications"
  type        = list(string)
  default     = []
  
  validation {
    condition = alltrue([
      for email in var.notification_emails : can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", email))
    ])
    error_message = "All notification emails must be valid email addresses."
  }
}

# Storage Account Configuration
variable "storage_account_tier" {
  description = "Storage account performance tier"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be either 'Standard' or 'Premium'."
  }
}

variable "storage_replication_type" {
  description = "Storage account replication type"
  type        = string
  default     = "LRS"
  
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_replication_type)
    error_message = "Storage replication type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

# Logic App Configuration
variable "logic_app_sku_name" {
  description = "Logic App service plan SKU name"
  type        = string
  default     = "WS1"
  
  validation {
    condition     = contains(["WS1", "WS2", "WS3"], var.logic_app_sku_name)
    error_message = "Logic App SKU must be one of: WS1, WS2, WS3."
  }
}

# Tagging Configuration
variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default = {
    Environment = "demo"
    Project     = "budget-monitoring"
    ManagedBy   = "terraform"
    Purpose     = "cost-management"
  }
}

variable "additional_tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}

# Monitoring and Diagnostics Configuration
variable "enable_diagnostic_settings" {
  description = "Enable diagnostic settings for resources"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Number of days to retain diagnostic logs"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_retention_days >= 1 && var.log_retention_days <= 730
    error_message = "Log retention days must be between 1 and 730."
  }
}

# Security Configuration
variable "enable_https_only" {
  description = "Enforce HTTPS-only access for storage account"
  type        = bool
  default     = true
}

variable "min_tls_version" {
  description = "Minimum TLS version for storage account"
  type        = string
  default     = "TLS1_2"
  
  validation {
    condition     = contains(["TLS1_0", "TLS1_1", "TLS1_2"], var.min_tls_version)
    error_message = "Minimum TLS version must be one of: TLS1_0, TLS1_1, TLS1_2."
  }
}