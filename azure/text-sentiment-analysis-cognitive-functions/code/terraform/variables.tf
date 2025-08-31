# Variables for the text sentiment analysis solution
# These variables allow customization of the deployment

variable "resource_group_name" {
  description = "Name of the Azure resource group to create"
  type        = string
  default     = null
  
  validation {
    condition = var.resource_group_name == null || (
      length(var.resource_group_name) >= 1 && 
      length(var.resource_group_name) <= 90 &&
      can(regex("^[a-zA-Z0-9._\\-()]+$", var.resource_group_name))
    )
    error_message = "Resource group name must be 1-90 characters and contain only alphanumeric characters, periods, underscores, hyphens, and parentheses."
  }
}

variable "location" {
  description = "Azure region where resources will be deployed"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "North Central US", "South Central US", "West Central US",
      "Canada Central", "Canada East", "Brazil South", "North Europe", 
      "West Europe", "UK South", "UK West", "France Central", "Germany West Central",
      "Switzerland North", "Norway East", "Sweden Central", "Australia East",
      "Australia Southeast", "East Asia", "Southeast Asia", "Japan East",
      "Japan West", "Korea Central", "India Central", "South Africa North"
    ], var.location)
    error_message = "Location must be a valid Azure region."
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
  description = "Name of the project for resource naming"
  type        = string
  default     = "sentiment"
  
  validation {
    condition = length(var.project_name) >= 2 && length(var.project_name) <= 20
    error_message = "Project name must be between 2 and 20 characters."
  }
}

variable "cognitive_services_sku" {
  description = "SKU for the Azure Cognitive Services Language resource"
  type        = string
  default     = "S0"
  
  validation {
    condition     = contains(["F0", "S0", "S1", "S2", "S3", "S4"], var.cognitive_services_sku)
    error_message = "Cognitive Services SKU must be one of: F0, S0, S1, S2, S3, S4."
  }
}

variable "function_app_service_plan_sku" {
  description = "SKU for the App Service Plan (use Y1 for consumption plan)"
  type        = string
  default     = "Y1"
  
  validation {
    condition = var.function_app_service_plan_sku == "Y1" || can(regex("^(B[1-3]|S[1-3]|P[1-3]V[2-3]|EP[1-3]|WS[1-3])$", var.function_app_service_plan_sku))
    error_message = "Function App Service Plan SKU must be Y1 (consumption) or valid premium/dedicated SKU."
  }
}

variable "storage_account_tier" {
  description = "Storage account performance tier"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be either Standard or Premium."
  }
}

variable "storage_account_replication_type" {
  description = "Storage account replication type"
  type        = string
  default     = "LRS"
  
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_account_replication_type)
    error_message = "Storage account replication type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

variable "enable_application_insights" {
  description = "Enable Application Insights for monitoring"
  type        = bool
  default     = true
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

variable "function_timeout_duration" {
  description = "Timeout duration for function execution (in seconds, max 600 for consumption plan)"
  type        = number
  default     = 300
  
  validation {
    condition     = var.function_timeout_duration >= 1 && var.function_timeout_duration <= 600
    error_message = "Function timeout must be between 1 and 600 seconds for consumption plan."
  }
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Purpose     = "Sentiment Analysis"
    Environment = "Demo"
    Recipe      = "text-sentiment-analysis-cognitive-functions"
  }
}