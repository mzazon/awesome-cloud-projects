# Variables for Azure infrastructure chatbot solution

variable "location" {
  description = "The Azure region where resources will be deployed"
  type        = string
  default     = "East US"
  
  validation {
    condition = can(regex("^[A-Za-z0-9 ]+$", var.location))
    error_message = "Location must be a valid Azure region name."
  }
}

variable "environment" {
  description = "Environment name for resource tagging and naming"
  type        = string
  default     = "demo"
  
  validation {
    condition     = contains(["dev", "test", "staging", "prod", "demo"], var.location)
    error_message = "Environment must be one of: dev, test, staging, prod, demo."
  }
}

variable "project_name" {
  description = "Project name used for resource naming and tagging"
  type        = string
  default     = "infra-chatbot"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "resource_group_name" {
  description = "Name of the resource group. If not provided, will be generated based on project_name and environment"
  type        = string
  default     = ""
}

variable "function_app_name" {
  description = "Name of the Azure Functions app. If not provided, will be generated with random suffix"
  type        = string
  default     = ""
}

variable "storage_account_name" {
  description = "Name of the storage account for Function App. If not provided, will be generated with random suffix"
  type        = string
  default     = ""
}

variable "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace. If not provided, will be generated based on project_name"
  type        = string
  default     = ""
}

variable "application_insights_name" {
  description = "Name of the Application Insights resource. If not provided, will be generated based on project_name"
  type        = string
  default     = ""
}

variable "function_app_plan_sku" {
  description = "SKU for the Function App service plan"
  type        = string
  default     = "Y1"  # Consumption plan
  
  validation {
    condition     = contains(["Y1", "EP1", "EP2", "EP3"], var.function_app_plan_sku)
    error_message = "Function App plan SKU must be one of: Y1 (Consumption), EP1, EP2, EP3 (Premium)."
  }
}

variable "log_analytics_sku" {
  description = "SKU for the Log Analytics workspace"
  type        = string
  default     = "PerGB2018"
  
  validation {
    condition     = contains(["Free", "PerNode", "PerGB2018", "Standard", "Premium"], var.log_analytics_sku)
    error_message = "Log Analytics SKU must be one of: Free, PerNode, PerGB2018, Standard, Premium."
  }
}

variable "log_analytics_retention_days" {
  description = "Number of days to retain logs in Log Analytics workspace"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_analytics_retention_days >= 30 && var.log_analytics_retention_days <= 730
    error_message = "Log Analytics retention days must be between 30 and 730."
  }
}

variable "storage_account_tier" {
  description = "Storage account tier for Function App storage"
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
    error_message = "Storage replication type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

variable "function_runtime_version" {
  description = "Runtime version for Azure Functions"
  type        = string
  default     = "~4"
  
  validation {
    condition     = contains(["~3", "~4"], var.function_runtime_version)
    error_message = "Function runtime version must be ~3 or ~4."
  }
}

variable "python_version" {
  description = "Python version for Azure Functions"
  type        = string
  default     = "3.9"
  
  validation {
    condition     = contains(["3.8", "3.9", "3.10", "3.11"], var.python_version)
    error_message = "Python version must be one of: 3.8, 3.9, 3.10, 3.11."
  }
}

variable "enable_application_insights" {
  description = "Enable Application Insights for monitoring"
  type        = bool
  default     = true
}

variable "enable_managed_identity" {
  description = "Enable system-assigned managed identity for the Function App"
  type        = bool
  default     = true
}

variable "tags" {
  description = "A map of tags to assign to all resources"
  type        = map(string)
  default = {
    Purpose     = "infrastructure-chatbot"
    Environment = "demo"
    ManagedBy   = "terraform"
  }
}