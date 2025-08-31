# Variable definitions for Customer Support Assistant with OpenAI Assistants and Functions
# These variables allow customization of the deployment without modifying the main configuration

variable "location" {
  description = "The Azure region where all resources will be deployed"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3", "Central US",
      "North Central US", "South Central US", "West Central US", "Canada Central",
      "Canada East", "Brazil South", "North Europe", "West Europe", "UK South",
      "UK West", "France Central", "Germany West Central", "Switzerland North",
      "Norway East", "Sweden Central", "Australia East", "Australia Southeast",
      "Southeast Asia", "East Asia", "Japan East", "Japan West", "Korea Central",
      "India Central", "South Africa North", "UAE North"
    ], var.location)
    error_message = "Location must be a valid Azure region that supports Azure OpenAI Service."
  }
}

variable "environment" {
  description = "Environment tag for resource organization (dev, test, prod)"
  type        = string
  default     = "demo"
  
  validation {
    condition     = contains(["dev", "test", "staging", "prod", "demo"], var.environment)
    error_message = "Environment must be one of: dev, test, staging, prod, demo."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming and tagging"
  type        = string
  default     = "support-assistant"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "openai_model_version" {
  description = "Version of the GPT-4o model to deploy"
  type        = string
  default     = "2024-11-20"
  
  validation {
    condition     = can(regex("^\\d{4}-\\d{2}-\\d{2}$", var.openai_model_version))
    error_message = "Model version must be in YYYY-MM-DD format."
  }
}

variable "openai_sku" {
  description = "SKU for Azure OpenAI Service (S0 for standard)"
  type        = string
  default     = "S0"
  
  validation {
    condition     = contains(["S0"], var.openai_sku)
    error_message = "OpenAI SKU must be S0 for standard pricing tier."
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

variable "storage_replication_type" {
  description = "Storage account replication type (LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS)"
  type        = string
  default     = "LRS"
  
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_replication_type)
    error_message = "Storage replication type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

variable "function_app_runtime" {
  description = "Runtime version for the Function App"
  type        = string
  default     = "20"
  
  validation {
    condition     = contains(["18", "20"], var.function_app_runtime)
    error_message = "Function App runtime must be either 18 or 20."
  }
}

variable "log_retention_days" {
  description = "Number of days to retain logs in Log Analytics workspace"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_retention_days >= 30 && var.log_retention_days <= 730
    error_message = "Log retention days must be between 30 and 730 days."
  }
}

variable "enable_monitoring" {
  description = "Enable Application Insights and Log Analytics for monitoring"
  type        = bool
  default     = true
}

variable "enable_cors" {
  description = "Enable CORS for Function App to allow web client access"
  type        = bool
  default     = true
}

variable "cors_allowed_origins" {
  description = "List of allowed origins for CORS configuration"
  type        = list(string)
  default     = ["*"]
  
  validation {
    condition     = length(var.cors_allowed_origins) > 0
    error_message = "At least one CORS origin must be specified."
  }
}

variable "storage_delete_retention_days" {
  description = "Number of days to retain deleted blobs"
  type        = number
  default     = 7
  
  validation {
    condition     = var.storage_delete_retention_days >= 1 && var.storage_delete_retention_days <= 365
    error_message = "Storage delete retention days must be between 1 and 365 days."
  }
}

variable "function_app_always_on" {
  description = "Keep Function App always on (not applicable for consumption plan)"
  type        = bool
  default     = false
}

variable "enable_system_identity" {
  description = "Enable system-assigned managed identity for Function App"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
  
  validation {
    condition = alltrue([
      for key, value in var.tags : can(regex("^[a-zA-Z0-9_.-]+$", key))
    ])
    error_message = "Tag keys must contain only alphanumeric characters, underscores, periods, and hyphens."
  }
}

variable "openai_public_access_enabled" {
  description = "Allow public network access to Azure OpenAI Service"
  type        = bool
  default     = true
}

variable "application_insights_type" {
  description = "Application type for Application Insights"
  type        = string
  default     = "Node.JS"
  
  validation {
    condition     = contains(["web", "Node.JS", "other"], var.application_insights_type)
    error_message = "Application Insights type must be one of: web, Node.JS, other."
  }
}