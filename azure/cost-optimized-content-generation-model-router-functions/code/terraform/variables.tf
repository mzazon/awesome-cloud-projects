# Variable definitions for cost-optimized content generation infrastructure
# These variables allow customization of the deployment for different environments

variable "location" {
  description = "The Azure region where resources will be deployed"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "North Central US", "South Central US", "West Central US",
      "Canada Central", "Canada East", "Brazil South", "UK South", "UK West",
      "West Europe", "North Europe", "France Central", "Germany West Central",
      "Switzerland North", "Norway East", "Sweden Central", "Poland Central",
      "Italy North", "Spain Central", "Israel Central", "UAE North",
      "South Africa North", "Australia East", "Australia Southeast",
      "Central India", "South India", "West India", "Japan East", "Japan West",
      "Korea Central", "Korea South", "Southeast Asia", "East Asia"
    ], var.location)
    error_message = "The location must be a valid Azure region."
  }
}

variable "resource_group_name" {
  description = "Name of the Azure resource group to create"
  type        = string
  default     = null
  
  validation {
    condition     = var.resource_group_name == null || can(regex("^[a-zA-Z0-9._-]+$", var.resource_group_name))
    error_message = "Resource group name must contain only letters, numbers, periods, underscores, and hyphens."
  }
}

variable "project_name" {
  description = "Name of the project, used as prefix for resource names"
  type        = string
  default     = "content-gen"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,10}[a-z0-9]$", var.project_name))
    error_message = "Project name must be 3-12 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens."
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

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Environment = "Development"
    Project     = "Content Generation"
    ManagedBy   = "Terraform"
    Purpose     = "Cost-Optimized AI Content Generation"
  }
}

# Storage configuration variables
variable "storage_account_tier" {
  description = "Performance tier for the storage account"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be either 'Standard' or 'Premium'."
  }
}

variable "storage_replication_type" {
  description = "Replication type for the storage account"
  type        = string
  default     = "LRS"
  
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_replication_type)
    error_message = "Storage replication type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

variable "storage_access_tier" {
  description = "Access tier for the storage account"
  type        = string
  default     = "Hot"
  
  validation {
    condition     = contains(["Hot", "Cool"], var.storage_access_tier)
    error_message = "Storage access tier must be either 'Hot' or 'Cool'."
  }
}

# AI Foundry configuration variables
variable "ai_foundry_sku" {
  description = "SKU for the Azure AI Foundry (Cognitive Services) resource"
  type        = string
  default     = "S0"
  
  validation {
    condition     = contains(["F0", "S0", "S1", "S2", "S3", "S4"], var.ai_foundry_sku)
    error_message = "AI Foundry SKU must be one of: F0, S0, S1, S2, S3, S4."
  }
}

variable "model_router_capacity" {
  description = "Capacity for the Model Router deployment (in units of 1000 TPM)"
  type        = number
  default     = 10
  
  validation {
    condition     = var.model_router_capacity >= 1 && var.model_router_capacity <= 1000
    error_message = "Model Router capacity must be between 1 and 1000 units."
  }
}

# Function App configuration variables
variable "function_app_runtime" {
  description = "Runtime for the Function App"
  type        = string
  default     = "node"
  
  validation {
    condition     = contains(["node", "python", "dotnet", "java"], var.function_app_runtime)
    error_message = "Function App runtime must be one of: node, python, dotnet, java."
  }
}

variable "function_app_runtime_version" {
  description = "Runtime version for the Function App"
  type        = string
  default     = "18"
  
  validation {
    condition = (
      (var.function_app_runtime == "node" && contains(["16", "18", "20"], var.function_app_runtime_version)) ||
      (var.function_app_runtime == "python" && contains(["3.8", "3.9", "3.10", "3.11"], var.function_app_runtime_version)) ||
      (var.function_app_runtime == "dotnet" && contains(["6", "7", "8"], var.function_app_runtime_version)) ||
      (var.function_app_runtime == "java" && contains(["8", "11", "17"], var.function_app_runtime_version))
    )
    error_message = "Runtime version must be compatible with the selected runtime."
  }
}

variable "function_app_os_type" {
  description = "Operating system type for the Function App"
  type        = string
  default     = "Linux"
  
  validation {
    condition     = contains(["Linux", "Windows"], var.function_app_os_type)
    error_message = "Function App OS type must be either 'Linux' or 'Windows'."
  }
}

# Cost management variables
variable "budget_amount" {
  description = "Monthly budget amount in USD for cost monitoring"
  type        = number
  default     = 100
  
  validation {
    condition     = var.budget_amount >= 10 && var.budget_amount <= 10000
    error_message = "Budget amount must be between $10 and $10,000."
  }
}

variable "budget_alert_threshold" {
  description = "Budget alert threshold percentage (0-100)"
  type        = number
  default     = 80
  
  validation {
    condition     = var.budget_alert_threshold >= 50 && var.budget_alert_threshold <= 100
    error_message = "Budget alert threshold must be between 50% and 100%."
  }
}

variable "admin_email" {
  description = "Email address for budget alerts and notifications"
  type        = string
  default     = "admin@company.com"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.admin_email))
    error_message = "Admin email must be a valid email address."
  }
}

# Application Insights configuration
variable "application_insights_retention_days" {
  description = "Data retention period in days for Application Insights"
  type        = number
  default     = 90
  
  validation {
    condition     = contains([30, 60, 90, 120, 180, 270, 365, 550, 730], var.application_insights_retention_days)
    error_message = "Application Insights retention must be one of: 30, 60, 90, 120, 180, 270, 365, 550, 730 days."
  }
}

# Event Grid configuration
variable "event_grid_advanced_filters_enabled" {
  description = "Enable advanced filtering for Event Grid subscriptions"
  type        = bool
  default     = true
}

variable "event_grid_retry_policy" {
  description = "Retry policy configuration for Event Grid"
  type = object({
    max_delivery_attempts = number
    event_time_to_live    = number
  })
  default = {
    max_delivery_attempts = 3
    event_time_to_live    = 1440 # 24 hours in minutes
  }
  
  validation {
    condition = (
      var.event_grid_retry_policy.max_delivery_attempts >= 1 &&
      var.event_grid_retry_policy.max_delivery_attempts <= 30 &&
      var.event_grid_retry_policy.event_time_to_live >= 1 &&
      var.event_grid_retry_policy.event_time_to_live <= 1440
    )
    error_message = "Max delivery attempts must be 1-30, and event TTL must be 1-1440 minutes."
  }
}

# Security and compliance variables
variable "enable_https_only" {
  description = "Enforce HTTPS-only access for all web resources"
  type        = bool
  default     = true
}

variable "minimum_tls_version" {
  description = "Minimum TLS version for secure connections"
  type        = string
  default     = "1.2"
  
  validation {
    condition     = contains(["1.0", "1.1", "1.2", "1.3"], var.minimum_tls_version)
    error_message = "Minimum TLS version must be one of: 1.0, 1.1, 1.2, 1.3."
  }
}

variable "enable_storage_encryption" {
  description = "Enable encryption at rest for storage accounts"
  type        = bool
  default     = true
}

variable "enable_diagnostic_logs" {
  description = "Enable diagnostic logging for all supported resources"
  type        = bool
  default     = true
}

# Performance and scaling variables
variable "function_timeout_duration" {
  description = "Timeout duration for Azure Functions in seconds"
  type        = number
  default     = 300
  
  validation {
    condition     = var.function_timeout_duration >= 1 && var.function_timeout_duration <= 600
    error_message = "Function timeout must be between 1 and 600 seconds."
  }
}

variable "enable_auto_scaling" {
  description = "Enable automatic scaling for Function Apps"
  type        = bool
  default     = true
}