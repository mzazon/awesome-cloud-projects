# Core Configuration Variables
variable "resource_group_name" {
  description = "Name of the Azure resource group"
  type        = string
  default     = "rg-ai-evaluation"
  
  validation {
    condition     = length(var.resource_group_name) >= 3 && length(var.resource_group_name) <= 90
    error_message = "Resource group name must be between 3 and 90 characters."
  }
}

variable "location" {
  description = "Azure region for resource deployment"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3", 
      "Central US", "North Central US", "South Central US", "West Central US",
      "Canada Central", "Canada East",
      "Brazil South",
      "North Europe", "West Europe", "UK South", "UK West",
      "France Central", "Germany West Central", "Norway East", "Switzerland North",
      "Sweden Central",
      "Australia East", "Australia Southeast",
      "Japan East", "Japan West",
      "Korea Central", "Korea South",
      "Southeast Asia", "East Asia"
    ], var.location)
    error_message = "Location must be a valid Azure region that supports Azure OpenAI services."
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

# Project Configuration
variable "project_name" {
  description = "Name of the AI evaluation project"
  type        = string
  default     = "ai-eval-project"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]{0,62}[a-zA-Z0-9]$", var.project_name))
    error_message = "Project name must be 3-64 characters, start and end with alphanumeric, and contain only alphanumeric and hyphens."
  }
}

variable "application_name" {
  description = "Name of the application for resource naming"
  type        = string
  default     = "ai-evaluation"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]{0,18}[a-zA-Z0-9]$", var.project_name))
    error_message = "Application name must be 3-20 characters, start and end with alphanumeric, and contain only alphanumeric and hyphens."
  }
}

# Azure OpenAI Configuration
variable "openai_sku_name" {
  description = "Pricing tier for Azure OpenAI service"
  type        = string
  default     = "S0"
  
  validation {
    condition     = contains(["F0", "S0"], var.openai_sku_name)
    error_message = "OpenAI SKU must be either F0 (Free) or S0 (Standard)."
  }
}

variable "model_deployments" {
  description = "Configuration for AI model deployments"
  type = map(object({
    model_name    = string
    model_version = string
    model_format  = string
    sku_name      = string
    sku_capacity  = number
  }))
  
  default = {
    "gpt-4o-eval" = {
      model_name    = "gpt-4o"
      model_version = "2024-08-06"
      model_format  = "OpenAI"
      sku_name      = "Standard"
      sku_capacity  = 10
    },
    "gpt-35-turbo-eval" = {
      model_name    = "gpt-35-turbo"
      model_version = "0125"
      model_format  = "OpenAI"
      sku_name      = "Standard"
      sku_capacity  = 10
    },
    "gpt-4o-mini-eval" = {
      model_name    = "gpt-4o-mini"
      model_version = "2024-07-18"
      model_format  = "OpenAI"
      sku_name      = "Standard"
      sku_capacity  = 10
    }
  }
}

# Storage Configuration
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

# Machine Learning Workspace Configuration
variable "ml_workspace_sku" {
  description = "SKU for Azure Machine Learning workspace"
  type        = string
  default     = "Basic"
  
  validation {
    condition     = contains(["Free", "Basic", "Standard", "Premium"], var.ml_workspace_sku)
    error_message = "ML workspace SKU must be one of: Free, Basic, Standard, Premium."
  }
}

variable "ml_workspace_description" {
  description = "Description for the Machine Learning workspace"
  type        = string
  default     = "AI Model Evaluation and Benchmarking Workspace"
}

# Key Vault Configuration
variable "key_vault_sku" {
  description = "SKU for Azure Key Vault"
  type        = string
  default     = "standard"
  
  validation {
    condition     = contains(["standard", "premium"], var.key_vault_sku)
    error_message = "Key Vault SKU must be either standard or premium."
  }
}

variable "key_vault_purge_protection_enabled" {
  description = "Enable purge protection for Key Vault"
  type        = bool
  default     = false
}

# Application Insights Configuration
variable "application_insights_type" {
  description = "Application type for Application Insights"
  type        = string
  default     = "web"
  
  validation {
    condition     = contains(["ios", "java", "MobileCenter", "Node.JS", "other", "phone", "store", "web"], var.application_insights_type)
    error_message = "Application Insights type must be one of the supported application types."
  }
}

# Network Security Configuration
variable "public_network_access_enabled" {
  description = "Enable public network access for resources"
  type        = bool
  default     = true
}

variable "local_auth_enabled" {
  description = "Enable local authentication for Cognitive Services"
  type        = bool
  default     = true
}

# Resource Tagging
variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Purpose     = "AI Model Evaluation"
    Environment = "Demo"
    Workload    = "AI-ML"
    Owner       = "Data Science Team"
  }
}

# Advanced Configuration
variable "enable_high_business_impact" {
  description = "Enable high business impact mode for ML workspace"
  type        = bool
  default     = false
}

variable "container_registry_enabled" {
  description = "Create and associate Azure Container Registry"
  type        = bool
  default     = false
}

variable "enable_customer_managed_key" {
  description = "Enable customer-managed encryption keys"
  type        = bool
  default     = false
}

# Cost Management
variable "enable_automatic_scaling" {
  description = "Enable automatic scaling for compute resources"
  type        = bool
  default     = false
}

variable "delete_protection_enabled" {
  description = "Enable deletion protection for critical resources"
  type        = bool
  default     = false
}