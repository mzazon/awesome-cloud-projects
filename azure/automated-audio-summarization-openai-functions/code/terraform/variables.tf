# Variable definitions for Azure Audio Summarization Infrastructure
# These variables allow customization of the deployment while maintaining security and best practices

# Resource Group Configuration
variable "resource_group_name" {
  description = "Name of the Azure resource group to create"
  type        = string
  default     = null
  
  validation {
    condition     = var.resource_group_name == null || can(regex("^rg-[a-z0-9-]+$", var.resource_group_name))
    error_message = "Resource group name must follow Azure naming conventions (rg-<name>) or be null for auto-generation."
  }
}

variable "location" {
  description = "Azure region where resources will be deployed"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "North Central US", "South Central US", 
      "West Central US", "Canada East", "Canada Central",
      "North Europe", "West Europe", "UK South", "UK West",
      "France Central", "Germany West Central", "Norway East",
      "Switzerland North", "Sweden Central", "Australia East",
      "Australia Southeast", "Southeast Asia", "East Asia",
      "Japan East", "Japan West", "Korea Central", "India Central",
      "South Africa North", "UAE North", "Brazil South"
    ], var.location)
    error_message = "Location must be a valid Azure region that supports Azure OpenAI services."
  }
}

# Project Configuration
variable "project_name" {
  description = "Name of the project used for resource naming"
  type        = string
  default     = "audio-summarization"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
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

# Storage Account Configuration
variable "storage_account_tier" {
  description = "Storage account performance tier"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be either Standard or Premium."
  }
}

variable "storage_replication_type" {
  description = "Storage account replication strategy"
  type        = string
  default     = "LRS"
  
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_replication_type)
    error_message = "Storage replication type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

# Azure OpenAI Configuration
variable "openai_sku_name" {
  description = "SKU name for Azure OpenAI service"
  type        = string
  default     = "S0"
  
  validation {
    condition     = contains(["S0"], var.openai_sku_name)
    error_message = "OpenAI SKU must be S0 for standard deployment."
  }
}

variable "whisper_model_version" {
  description = "Version of the Whisper model to deploy"
  type        = string
  default     = "001"
  
  validation {
    condition     = can(regex("^[0-9]{3}$", var.whisper_model_version))
    error_message = "Whisper model version must be a 3-digit string (e.g., '001')."
  }
}

variable "gpt_model_name" {
  description = "Name of the GPT model to deploy"
  type        = string
  default     = "gpt-4"
  
  validation {
    condition     = contains(["gpt-4", "gpt-35-turbo"], var.gpt_model_name)
    error_message = "GPT model must be either 'gpt-4' or 'gpt-35-turbo'."
  }
}

variable "gpt_model_version" {
  description = "Version of the GPT model to deploy"
  type        = string
  default     = "0613"
  
  validation {
    condition     = can(regex("^[0-9]{4}$", var.gpt_model_version))
    error_message = "GPT model version must be a 4-digit string (e.g., '0613')."
  }
}

variable "model_sku_capacity" {
  description = "Capacity units for deployed models"
  type        = number
  default     = 10
  
  validation {
    condition     = var.model_sku_capacity >= 1 && var.model_sku_capacity <= 240
    error_message = "Model SKU capacity must be between 1 and 240."
  }
}

# Function App Configuration
variable "function_runtime_version" {
  description = "Python runtime version for Azure Functions"
  type        = string
  default     = "3.12"
  
  validation {
    condition     = contains(["3.11", "3.12"], var.function_runtime_version)
    error_message = "Function runtime version must be either '3.11' or '3.12'."
  }
}

variable "functions_extension_version" {
  description = "Azure Functions extension version"
  type        = string
  default     = "~4"
  
  validation {
    condition     = contains(["~3", "~4"], var.functions_extension_version)
    error_message = "Functions extension version must be either '~3' or '~4'."
  }
}

variable "service_plan_sku_name" {
  description = "SKU name for the App Service Plan (Function App hosting)"
  type        = string
  default     = "Y1"
  
  validation {
    condition     = contains(["Y1", "EP1", "EP2", "EP3", "B1", "B2", "B3", "S1", "S2", "S3"], var.service_plan_sku_name)
    error_message = "Service plan SKU must be a valid Azure Functions hosting plan SKU."
  }
}

# Security Configuration
variable "storage_public_access_enabled" {
  description = "Whether to allow public access to storage containers"
  type        = bool
  default     = false
}

variable "function_https_only" {
  description = "Whether to require HTTPS for function app access"
  type        = bool
  default     = true
}

# Monitoring Configuration
variable "enable_application_insights" {
  description = "Whether to enable Application Insights for monitoring"
  type        = bool
  default     = true
}

# Tagging Configuration
variable "tags" {
  description = "A map of tags to assign to resources"
  type        = map(string)
  default = {
    Purpose     = "Audio Summarization"
    Environment = "Demo"
    Terraform   = "true"
    Recipe      = "automated-audio-summarization-openai-functions"
  }
  
  validation {
    condition     = can(var.tags["Purpose"]) && can(var.tags["Environment"])
    error_message = "Tags must include at least 'Purpose' and 'Environment' keys."
  }
}

# Advanced Configuration
variable "custom_subdomain_name" {
  description = "Custom subdomain name for Azure OpenAI (required for private endpoints)"
  type        = string
  default     = null
}

variable "enable_public_network_access" {
  description = "Whether to enable public network access for cognitive services"
  type        = bool
  default     = true
}

variable "daily_memory_quota_gb" {
  description = "Daily memory quota in GB for consumption plan (0 = no limit)"
  type        = number
  default     = 0
  
  validation {
    condition     = var.daily_memory_quota_gb >= 0
    error_message = "Daily memory quota must be 0 or positive."
  }
}