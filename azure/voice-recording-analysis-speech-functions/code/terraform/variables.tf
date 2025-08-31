# Azure Voice Recording Analysis - Variable Definitions
# This file defines all customizable parameters for the infrastructure

variable "location" {
  description = "The Azure region where resources will be deployed"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "West US 2", "West Europe", "North Europe",
      "Southeast Asia", "Japan East", "Australia East"
    ], var.location)
    error_message = "Location must be a supported Azure region for AI services."
  }
}

variable "resource_group_name" {
  description = "Name of the Azure resource group"
  type        = string
  default     = ""
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._-]{1,90}$", var.resource_group_name)) || var.resource_group_name == ""
    error_message = "Resource group name must be 1-90 characters and contain only alphanumeric, periods, underscores, hyphens, and parentheses."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "project_name" {
  description = "Name of the project, used for resource naming"
  type        = string
  default     = "voice-analysis"
  
  validation {
    condition     = can(regex("^[a-z0-9-]{2,20}$", var.project_name))
    error_message = "Project name must be 2-20 lowercase alphanumeric characters or hyphens."
  }
}

variable "speech_service_sku" {
  description = "SKU for the Azure AI Speech service"
  type        = string
  default     = "F0"
  
  validation {
    condition     = contains(["F0", "S0"], var.speech_service_sku)
    error_message = "Speech service SKU must be F0 (free tier) or S0 (standard)."
  }
}

variable "storage_account_tier" {
  description = "Performance tier for the storage account"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be Standard or Premium."
  }
}

variable "storage_replication_type" {
  description = "Replication type for the storage account"
  type        = string
  default     = "LRS"
  
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS"], var.storage_replication_type)
    error_message = "Storage replication type must be LRS, GRS, RAGRS, or ZRS."
  }
}

variable "function_app_service_plan_sku" {
  description = "SKU for the Function App service plan (Y1 for Consumption)"
  type        = string
  default     = "Y1"
  
  validation {
    condition     = contains(["Y1", "EP1", "EP2", "EP3"], var.function_app_service_plan_sku)
    error_message = "Function App SKU must be Y1 (Consumption), EP1, EP2, or EP3 (Premium)."
  }
}

variable "function_app_python_version" {
  description = "Python version for the Function App"
  type        = string
  default     = "3.11"
  
  validation {
    condition     = contains(["3.8", "3.9", "3.10", "3.11"], var.function_app_python_version)
    error_message = "Python version must be 3.8, 3.9, 3.10, or 3.11."
  }
}

variable "speech_language" {
  description = "Default language for speech recognition"
  type        = string
  default     = "en-US"
  
  validation {
    condition     = can(regex("^[a-z]{2}-[A-Z]{2}$", var.speech_language))
    error_message = "Speech language must be in format 'xx-XX' (e.g., 'en-US', 'es-ES')."
  }
}

variable "enable_application_insights" {
  description = "Whether to enable Application Insights for monitoring"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Number of days to retain logs in Application Insights"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_retention_days >= 30 && var.log_retention_days <= 730
    error_message = "Log retention days must be between 30 and 730."
  }
}

variable "tags" {
  description = "A map of tags to assign to resources"
  type        = map(string)
  default = {
    Project     = "Voice Analysis"
    ManagedBy   = "Terraform"
    Environment = "Development"
  }
}

variable "allowed_origins" {
  description = "List of allowed origins for CORS on the Function App"
  type        = list(string)
  default     = ["*"]
}

variable "enable_backup" {
  description = "Whether to enable backup for the Function App"
  type        = bool
  default     = false
}

variable "backup_retention_days" {
  description = "Number of days to retain backups"
  type        = number
  default     = 7
  
  validation {
    condition     = var.backup_retention_days >= 1 && var.backup_retention_days <= 30
    error_message = "Backup retention days must be between 1 and 30."
  }
}