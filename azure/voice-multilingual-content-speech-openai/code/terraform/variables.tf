# General Configuration Variables
variable "location" {
  description = "Azure region where resources will be deployed"
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
      "Japan West", "Korea Central", "South India", "Central India", "West India"
    ], var.location)
    error_message = "Location must be a valid Azure region."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "demo"
  
  validation {
    condition     = length(var.environment) <= 10 && can(regex("^[a-z0-9]+$", var.environment))
    error_message = "Environment must be alphanumeric and no more than 10 characters."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming and tagging"
  type        = string
  default     = "voice-pipeline"
  
  validation {
    condition     = length(var.project_name) <= 20 && can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must be lowercase alphanumeric with hyphens and no more than 20 characters."
  }
}

# Resource Naming Variables
variable "resource_group_name" {
  description = "Name of the resource group (leave empty for auto-generated name)"
  type        = string
  default     = ""
}

variable "storage_account_name" {
  description = "Name of the storage account (leave empty for auto-generated name)"
  type        = string
  default     = ""
  
  validation {
    condition = var.storage_account_name == "" || (
      length(var.storage_account_name) >= 3 && 
      length(var.storage_account_name) <= 24 && 
      can(regex("^[a-z0-9]+$", var.storage_account_name))
    )
    error_message = "Storage account name must be 3-24 characters, lowercase alphanumeric only."
  }
}

# Cognitive Services Configuration
variable "speech_service_sku" {
  description = "SKU for Azure Speech Service"
  type        = string
  default     = "S0"
  
  validation {
    condition     = contains(["F0", "S0"], var.speech_service_sku)
    error_message = "Speech service SKU must be F0 (Free) or S0 (Standard)."
  }
}

variable "openai_service_sku" {
  description = "SKU for Azure OpenAI Service"
  type        = string
  default     = "S0"
  
  validation {
    condition     = contains(["S0"], var.openai_service_sku)
    error_message = "OpenAI service SKU must be S0 (Standard)."
  }
}

variable "translator_service_sku" {
  description = "SKU for Azure Translator Service"
  type        = string
  default     = "S1"
  
  validation {
    condition     = contains(["F0", "S1", "S2", "S3", "S4"], var.translator_service_sku)
    error_message = "Translator service SKU must be F0, S1, S2, S3, or S4."
  }
}

# Azure Functions Configuration
variable "function_app_plan_sku" {
  description = "SKU for Azure Functions Service Plan"
  type        = string
  default     = "Y1"
  
  validation {
    condition     = contains(["Y1", "EP1", "EP2", "EP3"], var.function_app_plan_sku)
    error_message = "Function app plan SKU must be Y1 (Consumption), EP1, EP2, or EP3 (Premium)."
  }
}

variable "function_app_runtime" {
  description = "Runtime for Azure Functions"
  type        = string
  default     = "python"
  
  validation {
    condition     = contains(["python", "node", "dotnet", "java"], var.function_app_runtime)
    error_message = "Function app runtime must be python, node, dotnet, or java."
  }
}

variable "function_app_version" {
  description = "Version for Azure Functions runtime"
  type        = string
  default     = "3.11"
  
  validation {
    condition = var.function_app_runtime == "python" ? contains(["3.9", "3.10", "3.11"], var.function_app_version) : (
      var.function_app_runtime == "node" ? contains(["18", "20"], var.function_app_version) : (
        var.function_app_runtime == "dotnet" ? contains(["6.0", "8.0"], var.function_app_version) : (
          var.function_app_runtime == "java" ? contains(["8", "11", "17"], var.function_app_version) : true
        )
      )
    )
    error_message = "Function app version must be compatible with the selected runtime."
  }
}

# Processing Configuration
variable "target_languages" {
  description = "List of target languages for translation (ISO 639-1 codes)"
  type        = list(string)
  default     = ["es", "fr", "de", "ja", "pt"]
  
  validation {
    condition = alltrue([
      for lang in var.target_languages : 
      contains([
        "ar", "bg", "ca", "zh", "zh-tw", "hr", "cs", "da", "nl", "en", "et", 
        "fi", "fr", "de", "el", "he", "hi", "hu", "is", "id", "it", "ja", 
        "ko", "lv", "lt", "ms", "mt", "no", "pl", "pt", "ro", "ru", "sk", 
        "sl", "es", "sv", "th", "tr", "uk", "vi"
      ], lang)
    ])
    error_message = "All target languages must be valid ISO 639-1 language codes."
  }
}

# Storage Configuration
variable "storage_account_tier" {
  description = "Storage account tier"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be Standard or Premium."
  }
}

variable "storage_replication_type" {
  description = "Storage account replication type"
  type        = string
  default     = "LRS"
  
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_replication_type)
    error_message = "Storage replication type must be LRS, GRS, RAGRS, ZRS, GZRS, or RAGZRS."
  }
}

# Monitoring and Logging
variable "enable_application_insights" {
  description = "Enable Application Insights for monitoring"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Number of days to retain logs"
  type        = number
  default     = 90
  
  validation {
    condition     = var.log_retention_days >= 30 && var.log_retention_days <= 730
    error_message = "Log retention days must be between 30 and 730."
  }
}

# Security Configuration
variable "enable_public_network_access" {
  description = "Enable public network access for cognitive services"
  type        = bool
  default     = true
}

variable "allowed_ip_ranges" {
  description = "List of allowed IP ranges for storage account (empty for no restrictions)"
  type        = list(string)
  default     = []
}

# Tags
variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# Advanced Configuration
variable "openai_deployments" {
  description = "Configuration for OpenAI model deployments"
  type = list(object({
    name           = string
    model_name     = string  
    model_version  = string
    scale_type     = string
    scale_capacity = optional(number, 1)
  }))
  default = [
    {
      name           = "gpt-4"
      model_name     = "gpt-4"
      model_version  = "1106-Preview"
      scale_type     = "Standard"
      scale_capacity = 1
    }
  ]
}

variable "custom_domain_enabled" {
  description = "Enable custom domain for cognitive services"
  type        = bool
  default     = true
}

variable "network_access_rules" {
  description = "Network access rules for storage account"
  type = object({
    default_action = string
    bypass         = optional(list(string), ["AzureServices"])
    ip_rules       = optional(list(string), [])
  })
  default = {
    default_action = "Allow"
    bypass         = ["AzureServices"]
    ip_rules       = []
  }
}