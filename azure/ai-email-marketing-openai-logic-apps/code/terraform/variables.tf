# Variables for AI-powered email marketing solution with Azure OpenAI and Logic Apps
# This file defines all configurable parameters for the infrastructure deployment

# Resource naming and location variables
variable "project_name" {
  description = "Name of the project used for resource naming"
  type        = string
  default     = "email-marketing"
  
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
    error_message = "Environment must be dev, staging, or prod."
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
      "Canada Central", "Canada East", "Brazil South", "UK South", "UK West",
      "West Europe", "North Europe", "France Central", "Germany West Central",
      "Switzerland North", "Norway East", "Sweden Central", "Poland Central",
      "Italy North", "Spain Central", "Australia Central", "Australia East",
      "Australia Southeast", "Central India", "South India", "Japan East",
      "Japan West", "Korea Central", "Southeast Asia", "East Asia"
    ], var.location)
    error_message = "Location must be a valid Azure region."
  }
}

# Azure OpenAI configuration variables
variable "openai_sku_name" {
  description = "SKU name for Azure OpenAI service"
  type        = string
  default     = "S0"
  
  validation {
    condition     = contains(["S0"], var.openai_sku_name)
    error_message = "OpenAI SKU must be S0 for standard pricing."
  }
}

variable "openai_model_name" {
  description = "OpenAI model to deploy for content generation"
  type        = string
  default     = "gpt-4o"
  
  validation {
    condition     = contains(["gpt-4o", "gpt-4", "gpt-35-turbo"], var.openai_model_name)
    error_message = "Model must be gpt-4o, gpt-4, or gpt-35-turbo."
  }
}

variable "openai_model_version" {
  description = "Version of the OpenAI model to deploy"
  type        = string
  default     = "2024-11-20"
}

variable "openai_deployment_capacity" {
  description = "Deployment capacity for OpenAI model (tokens per minute)"
  type        = number
  default     = 10
  
  validation {
    condition     = var.openai_deployment_capacity >= 1 && var.openai_deployment_capacity <= 1000
    error_message = "OpenAI deployment capacity must be between 1 and 1000."
  }
}

# Logic Apps and Function App configuration
variable "function_app_service_plan_sku" {
  description = "SKU for the Function App service plan"
  type        = string
  default     = "Y1"
  
  validation {
    condition     = contains(["Y1", "EP1", "EP2", "EP3"], var.function_app_service_plan_sku)
    error_message = "Function App SKU must be Y1 (Consumption), EP1, EP2, or EP3 (Premium)."
  }
}

variable "function_app_runtime" {
  description = "Runtime for the Function App"
  type        = string
  default     = "node"
  
  validation {
    condition     = contains(["node", "dotnet", "python", "java"], var.function_app_runtime)
    error_message = "Runtime must be node, dotnet, python, or java."
  }
}

variable "function_app_runtime_version" {
  description = "Runtime version for the Function App"
  type        = string
  default     = "18"
}

# Storage account configuration
variable "storage_account_tier" {
  description = "Performance tier for storage account"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage tier must be Standard or Premium."
  }
}

variable "storage_account_replication_type" {
  description = "Replication type for storage account"
  type        = string
  default     = "LRS"
  
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_account_replication_type)
    error_message = "Replication type must be LRS, GRS, RAGRS, ZRS, GZRS, or RAGZRS."
  }
}

# Communication Services configuration
variable "communication_data_location" {
  description = "Data location for Communication Services"
  type        = string
  default     = "United States"
  
  validation {
    condition = contains([
      "Africa", "Asia Pacific", "Australia", "Brazil", "Canada", "Europe", 
      "France", "Germany", "India", "Japan", "Korea", "Norway", "Switzerland", 
      "UAE", "UK", "United States"
    ], var.communication_data_location)
    error_message = "Data location must be a valid Communication Services region."
  }
}

variable "email_domain_management" {
  description = "Domain management type for email service"
  type        = string
  default     = "AzureManaged"
  
  validation {
    condition     = contains(["AzureManaged", "CustomerManaged"], var.email_domain_management)
    error_message = "Domain management must be AzureManaged or CustomerManaged."
  }
}

# Workflow configuration variables
variable "workflow_schedule_frequency" {
  description = "Frequency for the marketing workflow execution"
  type        = string
  default     = "Day"
  
  validation {
    condition     = contains(["Day", "Hour", "Week", "Month"], var.workflow_schedule_frequency)
    error_message = "Schedule frequency must be Day, Hour, Week, or Month."
  }
}

variable "workflow_schedule_interval" {
  description = "Interval for the marketing workflow execution"
  type        = number
  default     = 1
  
  validation {
    condition     = var.workflow_schedule_interval >= 1 && var.workflow_schedule_interval <= 1000
    error_message = "Schedule interval must be between 1 and 1000."
  }
}

variable "workflow_start_time" {
  description = "Start time for the marketing workflow (ISO 8601 format)"
  type        = string
  default     = "2025-01-01T09:00:00Z"
}

# AI content generation parameters
variable "ai_max_tokens" {
  description = "Maximum tokens for AI content generation"
  type        = number
  default     = 800
  
  validation {
    condition     = var.ai_max_tokens >= 100 && var.ai_max_tokens <= 4000
    error_message = "AI max tokens must be between 100 and 4000."
  }
}

variable "ai_temperature" {
  description = "Temperature setting for AI content generation (0.0 to 2.0)"
  type        = number
  default     = 0.7
  
  validation {
    condition     = var.ai_temperature >= 0.0 && var.ai_temperature <= 2.0
    error_message = "AI temperature must be between 0.0 and 2.0."
  }
}

variable "test_email_recipient" {
  description = "Email address for testing the marketing campaigns"
  type        = string
  default     = "test@example.com"
  
  validation {
    condition     = can(regex("^[\\w\\.-]+@[\\w\\.-]+\\.[a-zA-Z]{2,}$", var.test_email_recipient))
    error_message = "Test email recipient must be a valid email address."
  }
}

# Resource tagging
variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Project     = "AI Email Marketing"
    Environment = "Development"
    Owner       = "DevOps Team"
    CostCenter  = "Marketing"
    Purpose     = "Recipe Demo"
  }
}

# Feature flags
variable "enable_application_insights" {
  description = "Enable Application Insights for monitoring and analytics"
  type        = bool
  default     = true
}

variable "enable_managed_identity" {
  description = "Enable system-assigned managed identity for secure resource access"
  type        = bool
  default     = true
}

variable "enable_advanced_threat_protection" {
  description = "Enable Advanced Threat Protection for storage account"
  type        = bool
  default     = false
}