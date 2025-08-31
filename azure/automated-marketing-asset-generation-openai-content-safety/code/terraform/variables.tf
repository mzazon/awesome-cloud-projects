# Variables for Azure Marketing Asset Generation Infrastructure
# This file defines all configurable parameters for the marketing automation solution

# Core Infrastructure Variables
variable "resource_group_name" {
  description = "Name of the Azure resource group to create all resources in"
  type        = string
  default     = null
  
  validation {
    condition     = var.resource_group_name == null || can(regex("^[a-zA-Z0-9._-]+$", var.resource_group_name))
    error_message = "Resource group name must contain only alphanumeric characters, periods, underscores, and hyphens."
  }
}

variable "location" {
  description = "Azure region where all resources will be deployed"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "Central US", "North Central US", "South Central US",
      "West Central US", "West US", "West US 2", "West US 3",
      "Canada Central", "Canada East",
      "Brazil South",
      "North Europe", "West Europe", "France Central", "Germany West Central",
      "Norway East", "Sweden Central", "Switzerland North", "UK South", "UK West",
      "Australia East", "Australia Southeast", "Central India", "East Asia",
      "Japan East", "Japan West", "Korea Central", "Southeast Asia"
    ], var.location)
    error_message = "Location must be a valid Azure region that supports OpenAI services."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod) for resource tagging and naming"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming and tagging"
  type        = string
  default     = "marketing-ai"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

# Storage Configuration
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
  description = "Storage account replication type for marketing assets"
  type        = string
  default     = "LRS"
  
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_replication_type)
    error_message = "Storage replication type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

variable "storage_access_tier" {
  description = "Default access tier for storage account (Hot or Cool)"
  type        = string
  default     = "Hot"
  
  validation {
    condition     = contains(["Hot", "Cool"], var.storage_access_tier)
    error_message = "Storage access tier must be either Hot or Cool."
  }
}

# Azure OpenAI Configuration
variable "openai_sku_name" {
  description = "SKU name for Azure OpenAI service (S0 for standard)"
  type        = string
  default     = "S0"
  
  validation {
    condition     = contains(["S0"], var.openai_sku_name)
    error_message = "OpenAI SKU name must be S0 for standard pricing tier."
  }
}

variable "gpt4_deployment_capacity" {
  description = "Token capacity for GPT-4 model deployment (tokens per minute)"
  type        = number
  default     = 10
  
  validation {
    condition     = var.gpt4_deployment_capacity >= 1 && var.gpt4_deployment_capacity <= 300
    error_message = "GPT-4 deployment capacity must be between 1 and 300 tokens per minute."
  }
}

variable "dalle3_deployment_capacity" {
  description = "Image generation capacity for DALL-E 3 model deployment"
  type        = number
  default     = 1
  
  validation {
    condition     = var.dalle3_deployment_capacity >= 1 && var.dalle3_deployment_capacity <= 10
    error_message = "DALL-E 3 deployment capacity must be between 1 and 10."
  }
}

# Content Safety Configuration
variable "content_safety_sku_name" {
  description = "SKU name for Azure Content Safety service"
  type        = string
  default     = "S0"
  
  validation {
    condition     = contains(["S0"], var.content_safety_sku_name)
    error_message = "Content Safety SKU name must be S0 for standard pricing tier."
  }
}

# Azure Functions Configuration
variable "function_app_service_plan_sku" {
  description = "SKU for the Function App service plan (Y1 for consumption)"
  type        = string
  default     = "Y1"
  
  validation {
    condition     = contains(["Y1", "EP1", "EP2", "EP3"], var.function_app_service_plan_sku)
    error_message = "Function App service plan SKU must be Y1 (consumption) or EP1/EP2/EP3 (premium)."
  }
}

variable "function_timeout_minutes" {
  description = "Function execution timeout in minutes (max 10 for consumption plan)"
  type        = number
  default     = 5
  
  validation {
    condition     = var.function_timeout_minutes >= 1 && var.function_timeout_minutes <= 10
    error_message = "Function timeout must be between 1 and 10 minutes for consumption plan."
  }
}

# Security and Networking
variable "enable_managed_identity" {
  description = "Enable system-assigned managed identity for Function App"
  type        = bool
  default     = true
}

variable "enable_https_only" {
  description = "Enforce HTTPS-only access for all services"
  type        = bool
  default     = true
}

variable "minimum_tls_version" {
  description = "Minimum TLS version for secure connections"
  type        = string
  default     = "1.2"
  
  validation {
    condition     = contains(["1.0", "1.1", "1.2"], var.minimum_tls_version)
    error_message = "Minimum TLS version must be 1.0, 1.1, or 1.2."
  }
}

# Monitoring and Logging
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
    error_message = "Log retention days must be between 30 and 730."
  }
}

# Resource Tagging
variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default = {
    Purpose     = "Marketing Automation"
    Environment = "Demo"
    ManagedBy   = "Terraform"
  }
}

# Content Safety Thresholds
variable "content_safety_severity_threshold" {
  description = "Severity threshold for content safety filtering (0-7, higher is more restrictive)"
  type        = number
  default     = 4
  
  validation {
    condition     = var.content_safety_severity_threshold >= 0 && var.content_safety_severity_threshold <= 7
    error_message = "Content safety severity threshold must be between 0 and 7."
  }
}

# Container Configuration
variable "marketing_containers" {
  description = "Configuration for marketing content containers"
  type = map(object({
    name        = string
    access_type = string
  }))
  default = {
    requests = {
      name        = "marketing-requests"
      access_type = "private"
    }
    assets = {
      name        = "marketing-assets"
      access_type = "blob"
    }
    rejected = {
      name        = "rejected-content"
      access_type = "private"
    }
  }
}

# Cost Management
variable "enable_cost_alerts" {
  description = "Enable cost monitoring and alerts for the solution"
  type        = bool
  default     = true
}

variable "monthly_budget_limit" {
  description = "Monthly budget limit in USD for cost monitoring"
  type        = number
  default     = 100
  
  validation {
    condition     = var.monthly_budget_limit > 0
    error_message = "Monthly budget limit must be greater than 0."
  }
}