# Variables for Azure Tutorial Generator Infrastructure

# Core Configuration Variables
variable "location" {
  description = "The Azure region where resources will be created"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "North Central US", "South Central US", "West Central US",
      "Canada Central", "Canada East", "Brazil South", "UK South", "UK West",
      "West Europe", "North Europe", "France Central", "Germany West Central",
      "Switzerland North", "Norway East", "Sweden Central", "Australia East",
      "Australia Southeast", "Southeast Asia", "East Asia", "Japan East",
      "Japan West", "Korea Central", "South India", "Central India"
    ], var.location)
    error_message = "Location must be a valid Azure region that supports Azure OpenAI."
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
  default     = "tutorial-gen"
  
  validation {
    condition     = can(regex("^[a-z0-9-]{2,20}$", var.project_name))
    error_message = "Project name must be 2-20 characters, lowercase letters, numbers, and hyphens only."
  }
}

# Resource Group Configuration
variable "resource_group_name" {
  description = "Name of the resource group (leave empty to auto-generate)"
  type        = string
  default     = ""
}

# Storage Account Configuration
variable "storage_account_tier" {
  description = "Storage account tier for tutorial content storage"
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
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_replication_type)
    error_message = "Storage replication type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

variable "storage_access_tier" {
  description = "Storage account access tier for blob storage"
  type        = string
  default     = "Hot"
  
  validation {
    condition     = contains(["Hot", "Cool"], var.storage_access_tier)
    error_message = "Storage access tier must be either Hot or Cool."
  }
}

# Azure OpenAI Configuration
variable "openai_sku_name" {
  description = "SKU name for Azure OpenAI service"
  type        = string
  default     = "S0"
  
  validation {
    condition     = contains(["S0"], var.openai_sku_name)
    error_message = "OpenAI SKU name must be S0 for standard tier."
  }
}

variable "openai_model_name" {
  description = "Name of the OpenAI model to deploy"
  type        = string
  default     = "gpt-4o-mini"
  
  validation {
    condition     = contains(["gpt-4o-mini", "gpt-35-turbo", "gpt-4", "gpt-4-32k"], var.openai_model_name)
    error_message = "Model name must be one of the supported OpenAI models."
  }
}

variable "openai_model_version" {
  description = "Version of the OpenAI model to deploy"
  type        = string
  default     = "2024-07-18"
}

variable "openai_deployment_capacity" {
  description = "Capacity (tokens per minute) for the OpenAI model deployment"
  type        = number
  default     = 10
  
  validation {
    condition     = var.openai_deployment_capacity >= 1 && var.openai_deployment_capacity <= 100
    error_message = "OpenAI deployment capacity must be between 1 and 100."
  }
}

# Function App Configuration
variable "function_app_service_plan_sku" {
  description = "SKU for the Function App service plan"
  type        = string
  default     = "Y1"
  
  validation {
    condition     = contains(["Y1", "EP1", "EP2", "EP3"], var.function_app_service_plan_sku)
    error_message = "Function App SKU must be one of: Y1 (Consumption), EP1, EP2, EP3 (Premium)."
  }
}

variable "function_runtime_version" {
  description = "Runtime version for Azure Functions"
  type        = string
  default     = "~4"
  
  validation {
    condition     = contains(["~3", "~4"], var.function_runtime_version)
    error_message = "Function runtime version must be ~3 or ~4."
  }
}

variable "python_version" {
  description = "Python version for the Function App"
  type        = string
  default     = "3.11"
  
  validation {
    condition     = contains(["3.8", "3.9", "3.10", "3.11"], var.python_version)
    error_message = "Python version must be one of: 3.8, 3.9, 3.10, 3.11."
  }
}

# Tagging Configuration
variable "tags" {
  description = "A map of tags to assign to resources"
  type        = map(string)
  default = {
    Project     = "Tutorial Generator"
    Purpose     = "Educational Content Creation"
    Environment = "Demo"
    ManagedBy   = "Terraform"
  }
}

# Security and Access Configuration
variable "enable_public_access" {
  description = "Enable public access to storage account (for tutorial content delivery)"
  type        = bool
  default     = true
}

variable "cors_allowed_origins" {
  description = "List of allowed origins for CORS on the Function App"
  type        = list(string)
  default     = ["*"]
}

# Monitoring and Logging Configuration
variable "enable_application_insights" {
  description = "Enable Application Insights for Function App monitoring"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Number of days to retain logs in Application Insights"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_retention_days >= 30 && var.log_retention_days <= 730
    error_message = "Log retention must be between 30 and 730 days."
  }
}