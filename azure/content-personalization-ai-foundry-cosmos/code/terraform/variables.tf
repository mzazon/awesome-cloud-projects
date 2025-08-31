# ===================================================================
# Variables for Azure Content Personalization Engine
# ===================================================================
# This file defines all configurable parameters for the content
# personalization infrastructure deployment.

# ===================================================================
# General Configuration
# ===================================================================

variable "location" {
  description = "The Azure region where resources will be deployed"
  type        = string
  default     = "East US"

  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "North Central US", "South Central US", "West Central US",
      "Canada Central", "Canada East", "UK South", "UK West",
      "North Europe", "West Europe", "France Central", "Germany West Central",
      "Switzerland North", "Norway East", "Sweden Central",
      "Australia East", "Australia Southeast", "Japan East", "Japan West",
      "Korea Central", "Southeast Asia", "East Asia"
    ], var.location)
    error_message = "The location must be a valid Azure region that supports the required services."
  }
}

variable "environment" {
  description = "Environment name (dev, test, staging, prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "test", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, test, staging, prod."
  }
}

variable "tags" {
  description = "A map of tags to apply to all resources"
  type        = map(string)
  default = {
    Project     = "ContentPersonalization"
    Environment = "dev"
    CreatedBy   = "Terraform"
    Purpose     = "AI-powered content personalization engine"
  }
}

# ===================================================================
# Resource Naming
# ===================================================================

variable "resource_group_name" {
  description = "Name of the resource group. If empty, will be auto-generated with suffix"
  type        = string
  default     = ""

  validation {
    condition     = can(regex("^[a-zA-Z0-9._()-]{1,90}$", var.resource_group_name)) || var.resource_group_name == ""
    error_message = "Resource group name must be 1-90 characters and can contain alphanumeric, underscore, parentheses, hyphen, and period characters."
  }
}

variable "cosmos_account_name" {
  description = "Name of the Cosmos DB account. If empty, will be auto-generated with suffix"
  type        = string
  default     = ""

  validation {
    condition     = can(regex("^[a-z0-9-]{3,44}$", var.cosmos_account_name)) || var.cosmos_account_name == ""
    error_message = "Cosmos DB account name must be 3-44 characters, lowercase letters, numbers, and hyphens only."
  }
}

variable "openai_service_name" {
  description = "Name of the Azure OpenAI service. If empty, will be auto-generated with suffix"
  type        = string
  default     = ""

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9._-]{1,62}[a-zA-Z0-9]$", var.openai_service_name)) || var.openai_service_name == ""
    error_message = "OpenAI service name must be 2-64 characters, start and end with alphanumeric, and contain only alphanumeric, dots, underscores, and hyphens."
  }
}

variable "function_app_name" {
  description = "Name of the Azure Function App. If empty, will be auto-generated with suffix"
  type        = string
  default     = ""

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]{1,58}[a-zA-Z0-9]$", var.function_app_name)) || var.function_app_name == ""
    error_message = "Function App name must be 2-60 characters, start and end with alphanumeric, and contain only alphanumeric and hyphens."
  }
}

variable "storage_account_name" {
  description = "Name of the storage account for Functions. If empty, will be auto-generated with suffix"
  type        = string
  default     = ""

  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.storage_account_name)) || var.storage_account_name == ""
    error_message = "Storage account name must be 3-24 characters, lowercase letters and numbers only."
  }
}

variable "ai_foundry_workspace_name" {
  description = "Name of the AI Foundry workspace. If empty, will be auto-generated with suffix"
  type        = string
  default     = ""

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9_-]{2,32}[a-zA-Z0-9]$", var.ai_foundry_workspace_name)) || var.ai_foundry_workspace_name == ""
    error_message = "AI Foundry workspace name must be 3-33 characters, start and end with alphanumeric, and contain only alphanumeric, underscores, and hyphens."
  }
}

# ===================================================================
# Azure OpenAI Configuration
# ===================================================================

variable "openai_location" {
  description = "Azure region for OpenAI service (may differ from main location for availability)"
  type        = string
  default     = ""

  validation {
    condition = var.openai_location == "" || contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "North Central US", "South Central US",
      "Canada Central", "UK South", "West Europe", "France Central",
      "Switzerland North", "Sweden Central", "Australia East", "Japan East"
    ], var.openai_location)
    error_message = "OpenAI location must be empty (auto-select) or a region that supports Azure OpenAI service."
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

variable "gpt4_capacity" {
  description = "Token capacity for GPT-4 deployment (Tokens Per Minute in thousands)"
  type        = number
  default     = 10

  validation {
    condition     = var.gpt4_capacity >= 1 && var.gpt4_capacity <= 240
    error_message = "GPT-4 capacity must be between 1 and 240 (representing 1K to 240K TPM)."
  }
}

variable "embedding_capacity" {
  description = "Token capacity for embedding model deployment (Tokens Per Minute in thousands)"
  type        = number
  default     = 10

  validation {
    condition     = var.embedding_capacity >= 1 && var.embedding_capacity <= 350
    error_message = "Embedding capacity must be between 1 and 350 (representing 1K to 350K TPM)."
  }
}

# ===================================================================
# Cosmos DB Configuration
# ===================================================================

variable "cosmos_throughput" {
  description = "Throughput for Cosmos DB containers (Request Units per second)"
  type        = number
  default     = 400

  validation {
    condition     = var.cosmos_throughput >= 400 && var.cosmos_throughput <= 100000
    error_message = "Cosmos DB throughput must be between 400 and 100,000 RU/s."
  }
}

variable "cosmos_consistency_level" {
  description = "Consistency level for Cosmos DB account"
  type        = string
  default     = "Session"

  validation {
    condition     = contains(["Eventual", "ConsistentPrefix", "Session", "BoundedStaleness", "Strong"], var.cosmos_consistency_level)
    error_message = "Cosmos DB consistency level must be one of: Eventual, ConsistentPrefix, Session, BoundedStaleness, Strong."
  }
}

variable "cosmos_enable_automatic_failover" {
  description = "Enable automatic failover for Cosmos DB account"
  type        = bool
  default     = true
}

variable "cosmos_enable_multiple_write_locations" {
  description = "Enable multiple write locations for Cosmos DB account"
  type        = bool
  default     = false
}

# ===================================================================
# Azure Functions Configuration
# ===================================================================

variable "function_app_sku" {
  description = "SKU for the Azure Functions service plan"
  type        = string
  default     = "Y1"

  validation {
    condition     = contains(["Y1", "EP1", "EP2", "EP3", "P1v2", "P2v2", "P3v2"], var.function_app_sku)
    error_message = "Function App SKU must be one of: Y1 (Consumption), EP1-EP3 (Elastic Premium), or P1v2-P3v2 (Dedicated)."
  }
}

variable "function_runtime_version" {
  description = "Azure Functions runtime version"
  type        = string
  default     = "~4"

  validation {
    condition     = contains(["~4", "~3"], var.function_runtime_version)
    error_message = "Function runtime version must be ~3 or ~4."
  }
}

variable "python_version" {
  description = "Python version for Azure Functions"
  type        = string
  default     = "3.12"

  validation {
    condition     = contains(["3.9", "3.10", "3.11", "3.12"], var.python_version)
    error_message = "Python version must be 3.9, 3.10, 3.11, or 3.12."
  }
}

variable "cors_allowed_origins" {
  description = "List of allowed origins for CORS on the Function App"
  type        = list(string)
  default     = ["*"]

  validation {
    condition     = length(var.cors_allowed_origins) > 0
    error_message = "At least one CORS origin must be specified."
  }
}

# ===================================================================
# Monitoring and Logging Configuration
# ===================================================================

variable "application_insights_retention_days" {
  description = "Data retention period for Application Insights in days"
  type        = number
  default     = 30

  validation {
    condition     = contains([30, 60, 90, 120, 180, 270, 365, 550, 730], var.application_insights_retention_days)
    error_message = "Application Insights retention must be one of: 30, 60, 90, 120, 180, 270, 365, 550, or 730 days."
  }
}

variable "enable_diagnostic_settings" {
  description = "Enable diagnostic settings for Azure resources"
  type        = bool
  default     = true
}

# ===================================================================
# Security Configuration
# ===================================================================

variable "enable_rbac_authorization" {
  description = "Enable RBAC authorization for Key Vault"
  type        = bool
  default     = true
}

variable "public_network_access_enabled" {
  description = "Enable public network access for services (set to false for private endpoint access)"
  type        = bool
  default     = true
}

variable "minimum_tls_version" {
  description = "Minimum TLS version for services"
  type        = string
  default     = "1.2"

  validation {
    condition     = contains(["1.0", "1.1", "1.2"], var.minimum_tls_version)
    error_message = "Minimum TLS version must be 1.0, 1.1, or 1.2."
  }
}

# ===================================================================
# Backup and Disaster Recovery
# ===================================================================

variable "enable_cosmos_backup" {
  description = "Enable backup for Cosmos DB (automatically enabled for production)"
  type        = bool
  default     = true
}

variable "backup_interval_minutes" {
  description = "Backup interval in minutes for Cosmos DB (between 60 and 1440)"
  type        = number
  default     = 240

  validation {
    condition     = var.backup_interval_minutes >= 60 && var.backup_interval_minutes <= 1440
    error_message = "Backup interval must be between 60 and 1440 minutes."
  }
}

variable "backup_retention_hours" {
  description = "Backup retention period in hours for Cosmos DB (between 8 and 720)"
  type        = number
  default     = 168 # 7 days

  validation {
    condition     = var.backup_retention_hours >= 8 && var.backup_retention_hours <= 720
    error_message = "Backup retention must be between 8 and 720 hours."
  }
}

# ===================================================================
# Cost Management
# ===================================================================

variable "enable_cost_alerts" {
  description = "Enable cost management alerts"
  type        = bool
  default     = false
}

variable "monthly_budget_amount" {
  description = "Monthly budget amount in USD for cost alerts"
  type        = number
  default     = 100

  validation {
    condition     = var.monthly_budget_amount > 0
    error_message = "Monthly budget amount must be greater than 0."
  }
}

# ===================================================================
# Advanced Configuration
# ===================================================================

variable "enable_private_endpoints" {
  description = "Enable private endpoints for enhanced security (requires virtual network)"
  type        = bool
  default     = false
}

variable "virtual_network_id" {
  description = "Virtual Network ID for private endpoints (required if enable_private_endpoints = true)"
  type        = string
  default     = ""

  validation {
    condition     = var.enable_private_endpoints == false || (var.enable_private_endpoints == true && var.virtual_network_id != "")
    error_message = "Virtual Network ID must be provided when private endpoints are enabled."
  }
}

variable "subnet_id" {
  description = "Subnet ID for private endpoints (required if enable_private_endpoints = true)"
  type        = string
  default     = ""

  validation {
    condition     = var.enable_private_endpoints == false || (var.enable_private_endpoints == true && var.subnet_id != "")
    error_message = "Subnet ID must be provided when private endpoints are enabled."
  }
}

# ===================================================================
# Feature Flags
# ===================================================================

variable "enable_vector_search" {
  description = "Enable vector search capabilities in Cosmos DB"
  type        = bool
  default     = true
}

variable "enable_ai_foundry" {
  description = "Enable Azure AI Foundry workspace deployment"
  type        = bool
  default     = true
}

variable "enable_monitoring" {
  description = "Enable comprehensive monitoring with Application Insights"
  type        = bool
  default     = true
}

variable "deploy_sample_data" {
  description = "Deploy sample data for testing (dev/test environments only)"
  type        = bool
  default     = false

  validation {
    condition     = var.deploy_sample_data == false || var.environment != "prod"
    error_message = "Sample data deployment is not allowed in production environment."
  }
}