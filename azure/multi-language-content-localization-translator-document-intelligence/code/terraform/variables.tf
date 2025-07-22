# Input variables for Azure multi-language content localization workflow
# These variables allow customization of the deployment

variable "location" {
  description = "The Azure region where resources will be created"
  type        = string
  default     = "East US"
  
  validation {
    condition = can(regex("^[A-Za-z0-9 ]+$", var.location))
    error_message = "Location must be a valid Azure region name."
  }
}

variable "resource_group_name" {
  description = "Name of the resource group to create"
  type        = string
  default     = "rg-localization-workflow"
  
  validation {
    condition     = length(var.resource_group_name) >= 3 && length(var.resource_group_name) <= 90
    error_message = "Resource group name must be between 3 and 90 characters long."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "demo"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.environment))
    error_message = "Environment must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "localization"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "translator_sku" {
  description = "SKU for Azure Translator service"
  type        = string
  default     = "S1"
  
  validation {
    condition     = contains(["F0", "S1", "S2", "S3", "S4"], var.translator_sku)
    error_message = "Translator SKU must be one of: F0, S1, S2, S3, S4."
  }
}

variable "document_intelligence_sku" {
  description = "SKU for Azure Document Intelligence service"
  type        = string
  default     = "S0"
  
  validation {
    condition     = contains(["F0", "S0"], var.document_intelligence_sku)
    error_message = "Document Intelligence SKU must be one of: F0, S0."
  }
}

variable "storage_account_tier" {
  description = "Performance tier for storage account"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be either Standard or Premium."
  }
}

variable "storage_replication_type" {
  description = "Replication type for storage account"
  type        = string
  default     = "LRS"
  
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_replication_type)
    error_message = "Storage replication type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

variable "target_languages" {
  description = "List of target languages for translation (ISO 639-1 codes)"
  type        = list(string)
  default     = ["es", "fr", "de", "it", "pt"]
  
  validation {
    condition     = length(var.target_languages) > 0 && length(var.target_languages) <= 100
    error_message = "Target languages list must contain between 1 and 100 language codes."
  }
}

variable "logic_app_trigger_interval" {
  description = "Trigger interval for Logic App in minutes"
  type        = number
  default     = 5
  
  validation {
    condition     = var.logic_app_trigger_interval >= 1 && var.logic_app_trigger_interval <= 1440
    error_message = "Logic App trigger interval must be between 1 and 1440 minutes."
  }
}

variable "enable_monitoring" {
  description = "Enable Application Insights monitoring for the Logic App"
  type        = bool
  default     = true
}

variable "enable_diagnostic_logs" {
  description = "Enable diagnostic logs for all services"
  type        = bool
  default     = true
}

variable "tags" {
  description = "A mapping of tags to assign to the resources"
  type        = map(string)
  default = {
    Environment = "demo"
    Project     = "localization"
    CreatedBy   = "Terraform"
  }
}