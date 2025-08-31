# Core resource configuration variables
variable "location" {
  description = "Azure region where resources will be deployed"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "North Central US", "South Central US",
      "West Central US", "Canada Central", "Canada East",
      "North Europe", "West Europe", "UK South", "UK West",
      "France Central", "Germany West Central", "Switzerland North",
      "Norway East", "Sweden Central"
    ], var.location)
    error_message = "Location must be a valid Azure region that supports OpenAI services."
  }
}

variable "resource_group_name" {
  description = "Name of the resource group (will be created if it doesn't exist)"
  type        = string
  default     = ""
}

variable "environment" {
  description = "Environment name for resource tagging and naming"
  type        = string
  default     = "demo"
  
  validation {
    condition     = can(regex("^[a-z0-9]+$", var.environment))
    error_message = "Environment must contain only lowercase letters and numbers."
  }
}

variable "project_name" {
  description = "Project name for resource naming and tagging"
  type        = string
  default     = "ai-assistant"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

# OpenAI service configuration
variable "openai_sku_name" {
  description = "SKU name for Azure OpenAI service"
  type        = string
  default     = "S0"
  
  validation {
    condition     = contains(["F0", "S0"], var.openai_sku_name)
    error_message = "OpenAI SKU must be either F0 (free tier) or S0 (standard tier)."
  }
}

variable "gpt_model_name" {
  description = "Name of the GPT model to deploy"
  type        = string
  default     = "gpt-4"
  
  validation {
    condition     = contains(["gpt-4", "gpt-4-32k", "gpt-35-turbo"], var.gpt_model_name)
    error_message = "GPT model must be one of: gpt-4, gpt-4-32k, gpt-35-turbo."
  }
}

variable "gpt_model_version" {
  description = "Version of the GPT model to deploy"
  type        = string
  default     = "0613"
  
  validation {
    condition     = can(regex("^[0-9]{4}$", var.gpt_model_version))
    error_message = "GPT model version must be a 4-digit version code (e.g., 0613)."
  }
}

variable "gpt_model_capacity" {
  description = "Capacity (TPM) for the GPT model deployment"
  type        = number
  default     = 10
  
  validation {
    condition     = var.gpt_model_capacity >= 1 && var.gpt_model_capacity <= 300
    error_message = "GPT model capacity must be between 1 and 300 TPM."
  }
}

# Storage account configuration
variable "storage_account_tier" {
  description = "Storage account tier"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be either Standard or Premium."
  }
}

variable "storage_replication_type" {
  description = "Storage account replication type"
  type        = string
  default     = "LRS"
  
  validation {
    condition = contains([
      "LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"
    ], var.storage_replication_type)
    error_message = "Storage replication type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

# Function App configuration
variable "function_app_os_type" {
  description = "Operating system type for Function App"
  type        = string
  default     = "Linux"
  
  validation {
    condition     = contains(["Linux", "Windows"], var.function_app_os_type)
    error_message = "Function App OS type must be either Linux or Windows."
  }
}

variable "python_version" {
  description = "Python version for Azure Functions"
  type        = string
  default     = "3.11"
  
  validation {
    condition     = contains(["3.8", "3.9", "3.10", "3.11"], var.python_version)
    error_message = "Python version must be one of: 3.8, 3.9, 3.10, 3.11."
  }
}

variable "functions_extension_version" {
  description = "Azure Functions runtime version"
  type        = string
  default     = "~4"
  
  validation {
    condition     = contains(["~3", "~4"], var.functions_extension_version)
    error_message = "Functions extension version must be either ~3 or ~4."
  }
}

# Application Insights configuration
variable "application_insights_type" {
  description = "Application Insights application type"
  type        = string
  default     = "web"
  
  validation {
    condition     = contains(["web", "other"], var.application_insights_type)
    error_message = "Application Insights type must be either 'web' or 'other'."
  }
}

# Security and access configuration
variable "enable_https_only" {
  description = "Enable HTTPS only for Function App"
  type        = bool
  default     = true
}

variable "minimum_tls_version" {
  description = "Minimum TLS version for Function App"
  type        = string
  default     = "1.2"
  
  validation {
    condition     = contains(["1.0", "1.1", "1.2"], var.minimum_tls_version)
    error_message = "Minimum TLS version must be one of: 1.0, 1.1, 1.2."
  }
}

# Monitoring and logging configuration
variable "enable_application_insights" {
  description = "Enable Application Insights for monitoring"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Number of days to retain logs"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_retention_days >= 30 && var.log_retention_days <= 730
    error_message = "Log retention days must be between 30 and 730."
  }
}

# Resource tagging
variable "tags" {
  description = "A map of tags to assign to resources"
  type        = map(string)
  default = {
    Purpose   = "AI Assistant Demo"
    ManagedBy = "Terraform"
  }
}

# Network security configuration
variable "allowed_origins" {
  description = "List of allowed origins for CORS"
  type        = list(string)
  default     = ["*"]
}

variable "ip_restriction_default_action" {
  description = "Default action for IP restrictions"
  type        = string
  default     = "Allow"
  
  validation {
    condition     = contains(["Allow", "Deny"], var.ip_restriction_default_action)
    error_message = "IP restriction default action must be either Allow or Deny."
  }
}

# Cost optimization variables
variable "enable_auto_scale" {
  description = "Enable auto-scaling for Function App"
  type        = bool
  default     = true
}

variable "daily_memory_time_quota" {
  description = "Daily memory time quota for Function App (0 = unlimited)"
  type        = number
  default     = 0
  
  validation {
    condition     = var.daily_memory_time_quota >= 0
    error_message = "Daily memory time quota must be 0 or greater (0 = unlimited)."
  }
}