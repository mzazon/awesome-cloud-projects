# Variables for AI Code Review Assistant with Reasoning and Functions
# This file defines all configurable parameters for the infrastructure deployment

variable "resource_group_name" {
  description = "Name of the Azure Resource Group where resources will be created"
  type        = string
  default     = null
  
  validation {
    condition     = var.resource_group_name == null || can(regex("^[a-zA-Z0-9._-]+$", var.resource_group_name))
    error_message = "Resource group name must contain only alphanumeric characters, periods, underscores, and hyphens."
  }
}

variable "location" {
  description = "Azure region where resources will be deployed. Must support Azure OpenAI o1-mini model"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US",
      "West US",
      "North Central US",
      "South Central US",
      "West Europe",
      "North Europe"
    ], var.location)
    error_message = "Location must be a region that supports Azure OpenAI o1-mini model."
  }
}

variable "environment" {
  description = "Environment name for resource tagging and naming"
  type        = string
  default     = "demo"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.environment))
    error_message = "Environment must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "project_name" {
  description = "Project name used for resource naming and tagging"
  type        = string
  default     = "ai-code-review"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "openai_sku_name" {
  description = "SKU name for Azure OpenAI Service"
  type        = string
  default     = "S0"
  
  validation {
    condition     = contains(["S0"], var.openai_sku_name)
    error_message = "OpenAI SKU must be S0 for Azure OpenAI Service."
  }
}

variable "o1_mini_model_version" {
  description = "Version of the o1-mini model to deploy"
  type        = string
  default     = "2024-09-12"
  
  validation {
    condition     = can(regex("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", var.o1_mini_model_version))
    error_message = "Model version must be in YYYY-MM-DD format."
  }
}

variable "o1_mini_deployment_capacity" {
  description = "Capacity for the o1-mini model deployment"
  type        = number
  default     = 10
  
  validation {
    condition     = var.o1_mini_deployment_capacity >= 1 && var.o1_mini_deployment_capacity <= 100
    error_message = "Deployment capacity must be between 1 and 100."
  }
}

variable "storage_account_tier" {
  description = "Performance tier for the storage account"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be either Standard or Premium."
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
  description = "SKU for the App Service Plan hosting the Function App"
  type        = string
  default     = "Y1"
  
  validation {
    condition     = contains(["Y1", "EP1", "EP2", "EP3"], var.function_app_service_plan_sku)
    error_message = "Function App service plan SKU must be Y1 (consumption) or EP1-EP3 (premium)."
  }
}

variable "function_app_runtime_version" {
  description = "Python runtime version for the Function App"
  type        = string
  default     = "3.11"
  
  validation {
    condition     = contains(["3.8", "3.9", "3.10", "3.11"], var.function_app_runtime_version)
    error_message = "Function App runtime version must be 3.8, 3.9, 3.10, or 3.11."
  }
}

variable "enable_application_insights" {
  description = "Enable Application Insights for Function App monitoring"
  type        = bool
  default     = true
}

variable "enable_storage_logging" {
  description = "Enable diagnostic logging for the storage account"
  type        = bool
  default     = true
}

variable "blob_container_access_type" {
  description = "Access type for blob containers"
  type        = string
  default     = "private"
  
  validation {
    condition     = contains(["private", "blob", "container"], var.blob_container_access_type)
    error_message = "Blob container access type must be private, blob, or container."
  }
}

variable "tags" {
  description = "A map of tags to assign to all resources"
  type        = map(string)
  default = {
    Environment = "demo"
    Project     = "ai-code-review"
    Purpose     = "recipe"
    ManagedBy   = "terraform"
  }
  
  validation {
    condition     = alltrue([for k, v in var.tags : can(regex("^[a-zA-Z0-9+\\-=._:/@]+$", k))])
    error_message = "Tag keys must contain only alphanumeric characters and the following special characters: + - = . _ : / @"
  }
}

variable "custom_domain_name" {
  description = "Custom domain name for Azure OpenAI Service (auto-generated if not provided)"
  type        = string
  default     = null
  
  validation {
    condition     = var.custom_domain_name == null || can(regex("^[a-z0-9-]+$", var.custom_domain_name))
    error_message = "Custom domain name must contain only lowercase letters, numbers, and hyphens."
  }
}