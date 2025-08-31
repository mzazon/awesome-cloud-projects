# ==============================================================================
# Simple Text Translation with Functions and Translator - Variables
# ==============================================================================
# Input variables for customizing the deployment of the text translation
# infrastructure. These variables allow flexible configuration for different
# environments and requirements.

# Resource Group Configuration
variable "resource_group_name" {
  description = "Name of the Azure Resource Group to create for the translation services"
  type        = string
  default     = "rg-translation"
  
  validation {
    condition     = length(var.resource_group_name) <= 90 && length(var.resource_group_name) >= 1
    error_message = "Resource group name must be between 1 and 90 characters."
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
      "North Europe", "West Europe", "France Central", "Germany West Central",
      "Switzerland North", "Norway East", "Sweden Central",
      "Australia East", "Australia Southeast", "East Asia", "Southeast Asia",
      "Japan East", "Japan West", "Korea Central", "India Central"
    ], var.location)
    error_message = "Location must be a valid Azure region."
  }
}

variable "environment" {
  description = "Environment name for resource tagging and naming (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = length(var.environment) <= 10 && can(regex("^[a-z0-9]+$", var.environment))
    error_message = "Environment must be lowercase alphanumeric and no more than 10 characters."
  }
}

# Storage Account Configuration
variable "storage_account_prefix" {
  description = "Prefix for the storage account name (will be suffixed with random string)"
  type        = string
  default     = "storage"
  
  validation {
    condition     = length(var.storage_account_prefix) <= 18 && can(regex("^[a-z0-9]+$", var.storage_account_prefix))
    error_message = "Storage account prefix must be lowercase alphanumeric and no more than 18 characters."
  }
}

# Function App Configuration
variable "function_app_prefix" {
  description = "Prefix for the Function App name (will be suffixed with random string)"
  type        = string
  default     = "translate-func"
  
  validation {
    condition     = length(var.function_app_prefix) <= 50 && can(regex("^[a-zA-Z0-9-]+$", var.function_app_prefix))
    error_message = "Function App prefix must be alphanumeric with hyphens and no more than 50 characters."
  }
}

variable "function_app_sku" {
  description = "SKU for the Function App Service Plan"
  type        = string
  default     = "Y1"
  
  validation {
    condition = contains([
      "Y1",           # Consumption Plan
      "EP1", "EP2", "EP3",  # Elastic Premium
      "P1", "P2", "P3"      # Premium
    ], var.function_app_sku)
    error_message = "Function App SKU must be a valid Azure Functions plan: Y1 (Consumption), EP1-EP3 (Elastic Premium), or P1-P3 (Premium)."
  }
}

variable "node_version" {
  description = "Node.js version for the Function App runtime"
  type        = string
  default     = "20"
  
  validation {
    condition     = contains(["18", "20"], var.node_version)
    error_message = "Node.js version must be either 18 or 20."
  }
}

variable "enable_staging_slot" {
  description = "Whether to create a staging slot for blue-green deployments"
  type        = bool
  default     = false
}

# Azure AI Translator Configuration
variable "translator_prefix" {
  description = "Prefix for the Azure AI Translator service name"
  type        = string
  default     = "translator"
  
  validation {
    condition     = length(var.translator_prefix) <= 50 && can(regex("^[a-zA-Z0-9-]+$", var.translator_prefix))
    error_message = "Translator prefix must be alphanumeric with hyphens and no more than 50 characters."
  }
}

variable "translator_sku" {
  description = "SKU for the Azure AI Translator service"
  type        = string
  default     = "F0"
  
  validation {
    condition = contains([
      "F0",                    # Free tier: 2M chars/month
      "S1", "S2", "S3", "S4"  # Standard tiers with different pricing
    ], var.translator_sku)
    error_message = "Translator SKU must be F0 (Free) or S1-S4 (Standard tiers)."
  }
}

# Security and Access Configuration
variable "cors_allowed_origins" {
  description = "List of allowed origins for CORS configuration"
  type        = list(string)
  default     = ["*"]
  
  validation {
    condition     = length(var.cors_allowed_origins) > 0
    error_message = "At least one CORS origin must be specified."
  }
}

variable "enable_public_access" {
  description = "Whether to allow public access to the Function App (if false, requires VNet integration)"
  type        = bool
  default     = true
}

# Monitoring and Logging Configuration
variable "application_insights_retention_days" {
  description = "Number of days to retain Application Insights data"
  type        = number
  default     = 90
  
  validation {
    condition     = var.application_insights_retention_days >= 30 && var.application_insights_retention_days <= 730
    error_message = "Application Insights retention must be between 30 and 730 days."
  }
}

variable "log_level" {
  description = "Logging level for the Function App"
  type        = string
  default     = "Information"
  
  validation {
    condition = contains([
      "Trace", "Debug", "Information", "Warning", "Error", "Critical", "None"
    ], var.log_level)
    error_message = "Log level must be one of: Trace, Debug, Information, Warning, Error, Critical, None."
  }
}

# Cost Management Configuration
variable "enable_auto_shutdown" {
  description = "Whether to enable automatic shutdown for cost savings (Consumption plan always scales to zero)"
  type        = bool
  default     = true
}

variable "max_burst" {
  description = "Maximum number of instances for scaling (only applicable for Premium plans)"
  type        = number
  default     = 200
  
  validation {
    condition     = var.max_burst >= 1 && var.max_burst <= 200
    error_message = "Max burst must be between 1 and 200 instances."
  }
}

# Advanced Configuration
variable "additional_app_settings" {
  description = "Additional application settings for the Function App"
  type        = map(string)
  default     = {}
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# Network Configuration (for advanced scenarios)
variable "subnet_id" {
  description = "Subnet ID for VNet integration (optional)"
  type        = string
  default     = null
}

variable "enable_private_endpoint" {
  description = "Whether to create a private endpoint for the storage account"
  type        = bool
  default     = false
}

# Function-specific Configuration
variable "function_timeout" {
  description = "Function execution timeout in minutes (max 10 for Consumption plan)"
  type        = number
  default     = 5
  
  validation {
    condition     = var.function_timeout >= 1 && var.function_timeout <= 10
    error_message = "Function timeout must be between 1 and 10 minutes for Consumption plan."
  }
}

variable "max_translation_length" {
  description = "Maximum characters allowed per translation request"
  type        = number
  default     = 10000
  
  validation {
    condition     = var.max_translation_length >= 1 && var.max_translation_length <= 50000
    error_message = "Max translation length must be between 1 and 50,000 characters."
  }
}