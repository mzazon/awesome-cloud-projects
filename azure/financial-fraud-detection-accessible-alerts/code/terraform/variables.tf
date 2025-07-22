# ==============================================================================
# VARIABLES - Azure Fraud Detection with AI Metrics Advisor and Immersive Reader
# ==============================================================================

# General Configuration
variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = can(regex("^(dev|staging|prod)$", var.environment))
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "location" {
  description = "Azure region where resources will be created"
  type        = string
  default     = "East US"
  
  validation {
    condition = can(regex("^[A-Za-z0-9 ]+$", var.location))
    error_message = "Location must be a valid Azure region name."
  }
}

variable "resource_group_name" {
  description = "Name of the resource group (will be created if not exists)"
  type        = string
  default     = ""
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-_()]{1,90}$", var.resource_group_name)) || var.resource_group_name == ""
    error_message = "Resource group name must be 1-90 characters and contain only letters, numbers, hyphens, underscores, and parentheses."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "fraud-detection"
  
  validation {
    condition     = can(regex("^[a-z0-9-]{2,20}$", var.project_name))
    error_message = "Project name must be 2-20 characters, lowercase letters, numbers, and hyphens only."
  }
}

# Common Tags
variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Environment = "dev"
    Project     = "fraud-detection"
    Purpose     = "intelligent-fraud-detection"
    ManagedBy   = "terraform"
  }
}

# Azure AI Metrics Advisor Configuration
variable "metrics_advisor_name" {
  description = "Name for the Azure AI Metrics Advisor service"
  type        = string
  default     = ""
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{2,64}$", var.metrics_advisor_name)) || var.metrics_advisor_name == ""
    error_message = "Metrics Advisor name must be 2-64 characters, letters, numbers, and hyphens only."
  }
}

variable "metrics_advisor_sku" {
  description = "SKU for Azure AI Metrics Advisor service"
  type        = string
  default     = "F0"
  
  validation {
    condition     = can(regex("^(F0|S0)$", var.metrics_advisor_sku))
    error_message = "Metrics Advisor SKU must be F0 (free) or S0 (standard)."
  }
}

variable "metrics_advisor_custom_subdomain" {
  description = "Custom subdomain for Metrics Advisor (leave empty for auto-generation)"
  type        = string
  default     = ""
  
  validation {
    condition     = can(regex("^[a-z0-9-]{2,63}$", var.metrics_advisor_custom_subdomain)) || var.metrics_advisor_custom_subdomain == ""
    error_message = "Custom subdomain must be 2-63 characters, lowercase letters, numbers, and hyphens only."
  }
}

# Azure AI Immersive Reader Configuration
variable "immersive_reader_name" {
  description = "Name for the Azure AI Immersive Reader service"
  type        = string
  default     = ""
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{2,64}$", var.immersive_reader_name)) || var.immersive_reader_name == ""
    error_message = "Immersive Reader name must be 2-64 characters, letters, numbers, and hyphens only."
  }
}

variable "immersive_reader_sku" {
  description = "SKU for Azure AI Immersive Reader service"
  type        = string
  default     = "F0"
  
  validation {
    condition     = can(regex("^(F0|S0)$", var.immersive_reader_sku))
    error_message = "Immersive Reader SKU must be F0 (free) or S0 (standard)."
  }
}

variable "immersive_reader_custom_subdomain" {
  description = "Custom subdomain for Immersive Reader (leave empty for auto-generation)"
  type        = string
  default     = ""
  
  validation {
    condition     = can(regex("^[a-z0-9-]{2,63}$", var.immersive_reader_custom_subdomain)) || var.immersive_reader_custom_subdomain == ""
    error_message = "Custom subdomain must be 2-63 characters, lowercase letters, numbers, and hyphens only."
  }
}

# Storage Account Configuration
variable "storage_account_name" {
  description = "Name for the storage account (leave empty for auto-generation)"
  type        = string
  default     = ""
  
  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.storage_account_name)) || var.storage_account_name == ""
    error_message = "Storage account name must be 3-24 characters, lowercase letters and numbers only."
  }
}

variable "storage_account_tier" {
  description = "Performance tier for the storage account"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = can(regex("^(Standard|Premium)$", var.storage_account_tier))
    error_message = "Storage account tier must be Standard or Premium."
  }
}

variable "storage_account_replication_type" {
  description = "Replication type for the storage account"
  type        = string
  default     = "LRS"
  
  validation {
    condition     = can(regex("^(LRS|GRS|RAGRS|ZRS|GZRS|RAGZRS)$", var.storage_account_replication_type))
    error_message = "Storage replication type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

variable "storage_containers" {
  description = "List of storage containers to create"
  type        = list(string)
  default     = ["transaction-data", "fraud-alerts", "processed-data"]
  
  validation {
    condition     = alltrue([for container in var.storage_containers : can(regex("^[a-z0-9-]{3,63}$", container))])
    error_message = "Container names must be 3-63 characters, lowercase letters, numbers, and hyphens only."
  }
}

# Logic App Configuration
variable "logic_app_name" {
  description = "Name for the Logic App workflow"
  type        = string
  default     = ""
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{2,80}$", var.logic_app_name)) || var.logic_app_name == ""
    error_message = "Logic App name must be 2-80 characters, letters, numbers, and hyphens only."
  }
}

variable "logic_app_state" {
  description = "State of the Logic App workflow"
  type        = string
  default     = "Enabled"
  
  validation {
    condition     = can(regex("^(Enabled|Disabled)$", var.logic_app_state))
    error_message = "Logic App state must be Enabled or Disabled."
  }
}

# Log Analytics Workspace Configuration
variable "log_analytics_workspace_name" {
  description = "Name for the Log Analytics workspace"
  type        = string
  default     = ""
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{4,63}$", var.log_analytics_workspace_name)) || var.log_analytics_workspace_name == ""
    error_message = "Log Analytics workspace name must be 4-63 characters, letters, numbers, and hyphens only."
  }
}

variable "log_analytics_sku" {
  description = "SKU for the Log Analytics workspace"
  type        = string
  default     = "PerGB2018"
  
  validation {
    condition     = can(regex("^(Free|Standalone|PerNode|PerGB2018)$", var.log_analytics_sku))
    error_message = "Log Analytics SKU must be one of: Free, Standalone, PerNode, PerGB2018."
  }
}

variable "log_analytics_retention_days" {
  description = "Number of days to retain logs in Log Analytics workspace"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_analytics_retention_days >= 30 && var.log_analytics_retention_days <= 730
    error_message = "Log Analytics retention days must be between 30 and 730."
  }
}

# Monitoring and Alerting Configuration
variable "enable_monitoring" {
  description = "Enable monitoring and alerting for the fraud detection system"
  type        = bool
  default     = true
}

variable "alert_email_addresses" {
  description = "List of email addresses to receive fraud detection alerts"
  type        = list(string)
  default     = []
  
  validation {
    condition     = alltrue([for email in var.alert_email_addresses : can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", email))])
    error_message = "All email addresses must be valid email format."
  }
}

variable "alert_severity" {
  description = "Severity level for fraud detection alerts"
  type        = number
  default     = 2
  
  validation {
    condition     = var.alert_severity >= 0 && var.alert_severity <= 4
    error_message = "Alert severity must be between 0 (critical) and 4 (verbose)."
  }
}

# Security Configuration
variable "enable_private_endpoints" {
  description = "Enable private endpoints for enhanced security"
  type        = bool
  default     = false
}

variable "allowed_ip_ranges" {
  description = "List of IP ranges allowed to access the services"
  type        = list(string)
  default     = []
  
  validation {
    condition     = alltrue([for ip in var.allowed_ip_ranges : can(cidrhost(ip, 0))])
    error_message = "All IP ranges must be valid CIDR notation."
  }
}

variable "enable_public_network_access" {
  description = "Allow public network access to cognitive services"
  type        = bool
  default     = true
}

# Advanced Configuration
variable "enable_diagnostic_logs" {
  description = "Enable diagnostic logs for all resources"
  type        = bool
  default     = true
}

variable "fraud_detection_threshold" {
  description = "Confidence threshold for fraud detection alerts (0.0-1.0)"
  type        = number
  default     = 0.75
  
  validation {
    condition     = var.fraud_detection_threshold >= 0.0 && var.fraud_detection_threshold <= 1.0
    error_message = "Fraud detection threshold must be between 0.0 and 1.0."
  }
}

variable "processing_frequency" {
  description = "Frequency for processing fraud detection data (in minutes)"
  type        = number
  default     = 5
  
  validation {
    condition     = var.processing_frequency >= 1 && var.processing_frequency <= 60
    error_message = "Processing frequency must be between 1 and 60 minutes."
  }
}

variable "enable_immersive_reader_features" {
  description = "Enable advanced Immersive Reader features (translation, read-aloud)"
  type        = bool
  default     = true
}

variable "supported_languages" {
  description = "List of supported languages for fraud alerts"
  type        = list(string)
  default     = ["en", "es", "fr", "de", "it", "pt", "ja", "ko", "zh-CN"]
  
  validation {
    condition     = alltrue([for lang in var.supported_languages : can(regex("^[a-z]{2}(-[A-Z]{2})?$", lang))])
    error_message = "All language codes must be valid ISO 639-1 format (e.g., en, es, zh-CN)."
  }
}