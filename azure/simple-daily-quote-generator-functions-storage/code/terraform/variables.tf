#
# Variables for Azure simple daily quote generator
# These variables allow customization of the deployment
#

variable "resource_group_name" {
  description = "Name of the Azure resource group"
  type        = string
  default     = null
  
  validation {
    condition = var.resource_group_name == null || (
      length(var.resource_group_name) >= 1 && 
      length(var.resource_group_name) <= 90 &&
      can(regex("^[a-zA-Z0-9._\\-]+$", var.resource_group_name))
    )
    error_message = "Resource group name must be 1-90 characters and contain only alphanumeric, period, underscore, and hyphen characters."
  }
}

variable "location" {
  description = "Azure region for deploying resources"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "South Central US", "North Central US",
      "Canada Central", "Canada East",
      "Brazil South",
      "North Europe", "West Europe", "UK South", "UK West",
      "France Central", "Germany West Central", "Norway East",
      "Switzerland North", "Sweden Central",
      "Australia East", "Australia Southeast",
      "Japan East", "Japan West",
      "Korea Central", "Southeast Asia", "East Asia",
      "Central India", "South India", "West India"
    ], var.location)
    error_message = "Location must be a valid Azure region."
  }
}

variable "environment" {
  description = "Environment name (dev, test, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "test", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, test, staging, prod."
  }
}

variable "project_name" {
  description = "Name of the project (used in resource naming)"
  type        = string
  default     = "quote-generator"
  
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.project_name)) && length(var.project_name) <= 20
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens, and be 20 characters or less."
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
    condition = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_account_replication_type)
    error_message = "Storage account replication type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

variable "function_app_runtime" {
  description = "Runtime stack for the Function App"
  type        = string
  default     = "node"
  
  validation {
    condition     = contains(["node", "dotnet", "java", "python", "powershell"], var.function_app_runtime)
    error_message = "Function app runtime must be one of: node, dotnet, java, python, powershell."
  }
}

variable "function_app_runtime_version" {
  description = "Runtime version for the Function App"
  type        = string
  default     = "20"
  
  validation {
    condition = var.function_app_runtime == "node" ? contains(["18", "20"], var.function_app_runtime_version) : true
    error_message = "For Node.js runtime, version must be 18 or 20."
  }
}

variable "enable_cors" {
  description = "Enable CORS for the Function App"
  type        = bool
  default     = true
}

variable "cors_allowed_origins" {
  description = "List of allowed origins for CORS"
  type        = list(string)
  default     = ["*"]
  
  validation {
    condition     = length(var.cors_allowed_origins) > 0
    error_message = "At least one CORS origin must be specified."
  }
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Purpose     = "Recipe Demo"
    Environment = "Development"
    Recipe      = "simple-daily-quote-generator"
  }
}

variable "sample_quotes" {
  description = "Sample quotes to populate the table storage"
  type = list(object({
    quote    = string
    author   = string
    category = string
  }))
  default = [
    {
      quote    = "The only way to do great work is to love what you do."
      author   = "Steve Jobs"
      category = "motivation"
    },
    {
      quote    = "Innovation distinguishes between a leader and a follower."
      author   = "Steve Jobs"
      category = "innovation"
    },
    {
      quote    = "Success is not final, failure is not fatal."
      author   = "Winston Churchill"
      category = "perseverance"
    },
    {
      quote    = "The future belongs to those who believe in the beauty of their dreams."
      author   = "Eleanor Roosevelt"
      category = "dreams"
    },
    {
      quote    = "It is during our darkest moments that we must focus to see the light."
      author   = "Aristotle"
      category = "hope"
    }
  ]
}