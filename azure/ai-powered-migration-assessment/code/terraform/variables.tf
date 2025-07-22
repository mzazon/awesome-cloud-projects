# ==============================================================================
# Variable Definitions for Azure AI-Powered Migration Assessment
# ==============================================================================

# Core Infrastructure Variables
variable "resource_group_name" {
  description = "Name of the resource group for all migration assessment resources"
  type        = string
  default     = "rg-migrate-ai-assessment"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._-]+$", var.resource_group_name))
    error_message = "Resource group name must contain only letters, numbers, periods, hyphens, and underscores."
  }
}

variable "location" {
  description = "Azure region where resources will be deployed"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "South Central US", "North Central US", "West Central US",
      "Canada Central", "Canada East", "North Europe", "West Europe",
      "UK South", "UK West", "France Central", "Switzerland North",
      "Germany West Central", "Norway East", "Sweden Central",
      "Australia East", "Australia Southeast", "East Asia", "Southeast Asia",
      "Japan East", "Japan West", "Korea Central", "South India",
      "Central India", "West India", "UAE North", "South Africa North",
      "Brazil South"
    ], var.location)
    error_message = "Location must be a valid Azure region."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod", "test"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod, test."
  }
}

# Storage Account Variables
variable "storage_account_prefix" {
  description = "Prefix for storage account name (must be globally unique)"
  type        = string
  default     = "stamigrate"
  
  validation {
    condition     = can(regex("^[a-z0-9]{3,11}$", var.storage_account_prefix))
    error_message = "Storage account prefix must be 3-11 characters long and contain only lowercase letters and numbers."
  }
}

variable "storage_account_tier" {
  description = "Storage account tier (Standard or Premium)"
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

# Azure OpenAI Service Variables
variable "openai_service_prefix" {
  description = "Prefix for Azure OpenAI service name"
  type        = string
  default     = "openai-migrate"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{2,50}$", var.openai_service_prefix))
    error_message = "OpenAI service prefix must be 2-50 characters long and contain only letters, numbers, and hyphens."
  }
}

variable "openai_location" {
  description = "Azure region for OpenAI service (limited availability)"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2",
      "South Central US", "West Europe", "France Central",
      "UK South", "Sweden Central", "Switzerland North",
      "Japan East", "Australia East", "Canada East"
    ], var.openai_location)
    error_message = "OpenAI location must be a region with Azure OpenAI service availability."
  }
}

variable "openai_sku" {
  description = "SKU for Azure OpenAI service"
  type        = string
  default     = "S0"
  
  validation {
    condition     = contains(["S0"], var.openai_sku)
    error_message = "OpenAI SKU must be S0 (Standard)."
  }
}

variable "openai_allowed_ips" {
  description = "List of IP addresses allowed to access OpenAI service"
  type        = list(string)
  default     = []
  
  validation {
    condition = alltrue([
      for ip in var.openai_allowed_ips : can(cidrhost(ip, 0))
    ])
    error_message = "All IP addresses must be valid CIDR notation."
  }
}

variable "gpt_model_name" {
  description = "GPT model name for deployment"
  type        = string
  default     = "gpt-4"
  
  validation {
    condition     = contains(["gpt-4", "gpt-4-32k", "gpt-35-turbo", "gpt-35-turbo-16k"], var.gpt_model_name)
    error_message = "GPT model name must be one of: gpt-4, gpt-4-32k, gpt-35-turbo, gpt-35-turbo-16k."
  }
}

variable "gpt_model_version" {
  description = "GPT model version for deployment"
  type        = string
  default     = "0613"
  
  validation {
    condition     = can(regex("^[0-9]{4}$", var.gpt_model_version))
    error_message = "GPT model version must be a 4-digit version number."
  }
}

variable "gpt_deployment_capacity" {
  description = "Deployment capacity for GPT model (tokens per minute)"
  type        = number
  default     = 20
  
  validation {
    condition     = var.gpt_deployment_capacity >= 1 && var.gpt_deployment_capacity <= 120
    error_message = "GPT deployment capacity must be between 1 and 120."
  }
}

# Azure Migrate Variables
variable "migrate_project_prefix" {
  description = "Prefix for Azure Migrate project name"
  type        = string
  default     = "migrate-project"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{2,50}$", var.migrate_project_prefix))
    error_message = "Migrate project prefix must be 2-50 characters long and contain only letters, numbers, and hyphens."
  }
}

# Azure Functions Variables
variable "function_app_name" {
  description = "Name prefix for Azure Function App"
  type        = string
  default     = "func-migrate-ai"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{2,50}$", var.function_app_name))
    error_message = "Function app name must be 2-50 characters long and contain only letters, numbers, and hyphens."
  }
}

variable "function_app_plan_sku" {
  description = "SKU for Function App service plan"
  type        = string
  default     = "Y1"
  
  validation {
    condition     = contains(["Y1", "EP1", "EP2", "EP3", "P1V2", "P2V2", "P3V2"], var.function_app_plan_sku)
    error_message = "Function app plan SKU must be one of: Y1 (Consumption), EP1-EP3 (Elastic Premium), P1V2-P3V2 (Premium)."
  }
}

variable "function_runtime_version" {
  description = "Python runtime version for Function App"
  type        = string
  default     = "3.11"
  
  validation {
    condition     = contains(["3.9", "3.10", "3.11"], var.function_runtime_version)
    error_message = "Python runtime version must be one of: 3.9, 3.10, 3.11."
  }
}

variable "functions_extension_version" {
  description = "Azure Functions extension version"
  type        = string
  default     = "~4"
  
  validation {
    condition     = contains(["~4", "~3"], var.functions_extension_version)
    error_message = "Functions extension version must be ~4 or ~3."
  }
}

# Monitoring and Diagnostics Variables
variable "log_analytics_sku" {
  description = "SKU for Log Analytics workspace"
  type        = string
  default     = "PerGB2018"
  
  validation {
    condition     = contains(["PerGB2018", "Free", "Standalone", "PerNode"], var.log_analytics_sku)
    error_message = "Log Analytics SKU must be one of: PerGB2018, Free, Standalone, PerNode."
  }
}

variable "log_retention_days" {
  description = "Number of days to retain logs"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_retention_days >= 7 && var.log_retention_days <= 730
    error_message = "Log retention days must be between 7 and 730."
  }
}

variable "application_insights_type" {
  description = "Application Insights application type"
  type        = string
  default     = "web"
  
  validation {
    condition     = contains(["web", "other"], var.application_insights_type)
    error_message = "Application Insights type must be either web or other."
  }
}

variable "application_insights_sampling_percentage" {
  description = "Application Insights sampling percentage"
  type        = number
  default     = 100
  
  validation {
    condition     = var.application_insights_sampling_percentage >= 0 && var.application_insights_sampling_percentage <= 100
    error_message = "Application Insights sampling percentage must be between 0 and 100."
  }
}

# Security and Compliance Variables
variable "enable_soft_delete" {
  description = "Enable soft delete for storage account blobs"
  type        = bool
  default     = true
}

variable "soft_delete_retention_days" {
  description = "Number of days to retain soft deleted blobs"
  type        = number
  default     = 30
  
  validation {
    condition     = var.soft_delete_retention_days >= 1 && var.soft_delete_retention_days <= 365
    error_message = "Soft delete retention days must be between 1 and 365."
  }
}

variable "enable_versioning" {
  description = "Enable blob versioning for storage account"
  type        = bool
  default     = true
}

variable "min_tls_version" {
  description = "Minimum TLS version for storage account"
  type        = string
  default     = "TLS1_2"
  
  validation {
    condition     = contains(["TLS1_0", "TLS1_1", "TLS1_2"], var.min_tls_version)
    error_message = "Minimum TLS version must be one of: TLS1_0, TLS1_1, TLS1_2."
  }
}

variable "enable_https_only" {
  description = "Enable HTTPS only for storage account"
  type        = bool
  default     = true
}

# Cost Management Variables
variable "enable_cost_anomaly_detection" {
  description = "Enable cost anomaly detection for the resource group"
  type        = bool
  default     = true
}

variable "monthly_budget_amount" {
  description = "Monthly budget amount for cost management (in USD)"
  type        = number
  default     = 1000
  
  validation {
    condition     = var.monthly_budget_amount >= 0
    error_message = "Monthly budget amount must be non-negative."
  }
}

# Resource Tagging Variables
variable "tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default = {
    "Project"     = "AI-Powered Migration Assessment"
    "Purpose"     = "Migration Assessment and Modernization"
    "ManagedBy"   = "Terraform"
    "CostCenter"  = "IT-Migration"
    "Owner"       = "Migration Team"
  }
  
  validation {
    condition     = length(var.tags) <= 50
    error_message = "Maximum of 50 tags allowed."
  }
}

# Network Security Variables
variable "allowed_ip_ranges" {
  description = "List of IP ranges allowed to access resources"
  type        = list(string)
  default     = []
  
  validation {
    condition = alltrue([
      for ip in var.allowed_ip_ranges : can(cidrhost(ip, 0))
    ])
    error_message = "All IP ranges must be valid CIDR notation."
  }
}

variable "enable_private_endpoint" {
  description = "Enable private endpoints for services"
  type        = bool
  default     = false
}

# Data Management Variables
variable "enable_data_export" {
  description = "Enable data export capabilities"
  type        = bool
  default     = true
}

variable "data_retention_days" {
  description = "Number of days to retain assessment data"
  type        = number
  default     = 90
  
  validation {
    condition     = var.data_retention_days >= 30 && var.data_retention_days <= 2555
    error_message = "Data retention days must be between 30 and 2555 (7 years)."
  }
}

# Development and Testing Variables
variable "enable_sample_data" {
  description = "Enable creation of sample assessment data for testing"
  type        = bool
  default     = true
}

variable "enable_debug_logging" {
  description = "Enable debug logging for Function Apps"
  type        = bool
  default     = false
}

variable "cors_allowed_origins" {
  description = "List of allowed CORS origins for Function App"
  type        = list(string)
  default     = ["*"]
}