# variables.tf
# Input variables for the Simple Team Poll System infrastructure

variable "location" {
  description = "The Azure region where all resources will be created"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "North Central US", "South Central US", "West Central US",
      "Canada Central", "Canada East", "Brazil South", "UK South", "UK West",
      "West Europe", "North Europe", "France Central", "Germany West Central",
      "Switzerland North", "Norway East", "Sweden Central",
      "Australia East", "Australia Southeast", "East Asia", "Southeast Asia",
      "Japan East", "Japan West", "Korea Central", "India Central",
      "South Africa North", "UAE North"
    ], var.location)
    error_message = "The location must be a valid Azure region."
  }
}

variable "environment" {
  description = "Environment name for resource tagging and naming (e.g., dev, staging, prod)"
  type        = string
  default     = "demo"
  
  validation {
    condition     = length(var.environment) <= 10 && can(regex("^[a-z0-9]+$", var.environment))
    error_message = "Environment must be lowercase alphanumeric and no more than 10 characters."
  }
}

variable "project_name" {
  description = "Project name used for resource naming and tagging"
  type        = string
  default     = "poll"
  
  validation {
    condition     = length(var.project_name) <= 8 && can(regex("^[a-z0-9]+$", var.project_name))
    error_message = "Project name must be lowercase alphanumeric and no more than 8 characters."
  }
}

variable "resource_group_name" {
  description = "Name of the resource group. If not provided, will be generated based on project_name and environment"
  type        = string
  default     = ""
}

variable "service_bus_sku" {
  description = "The SKU of the Service Bus namespace (Basic, Standard, Premium)"
  type        = string
  default     = "Basic"
  
  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.service_bus_sku)
    error_message = "Service Bus SKU must be Basic, Standard, or Premium."
  }
}

variable "storage_account_tier" {
  description = "Storage account performance tier (Standard or Premium)"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be Standard or Premium."
  }
}

variable "storage_account_replication_type" {
  description = "Storage account replication type (LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS)"  
  type        = string
  default     = "LRS"
  
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_account_replication_type)
    error_message = "Storage account replication type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

variable "function_app_service_plan_sku" {
  description = "The SKU for the App Service Plan. Use Y1 for Consumption plan"
  type        = string
  default     = "Y1"
  
  validation {
    condition = contains([
      "Y1",           # Consumption
      "EP1", "EP2", "EP3",  # Elastic Premium
      "P1v2", "P2v2", "P3v2", # Premium v2
      "P1v3", "P2v3", "P3v3"  # Premium v3
    ], var.function_app_service_plan_sku)
    error_message = "Function App service plan SKU must be a valid Azure Functions hosting plan SKU."
  }
}

variable "node_version" {
  description = "Node.js version for the Function App"
  type        = string
  default     = "18"
  
  validation {
    condition     = contains(["16", "18", "20"], var.node_version)
    error_message = "Node.js version must be 16, 18, or 20."
  }
}

variable "enable_cors" {
  description = "Enable CORS for the Function App to allow web browser access"
  type        = bool
  default     = true
}

variable "cors_allowed_origins" {
  description = "List of allowed origins for CORS. Use ['*'] for all origins (not recommended for production)"
  type        = list(string)
  default     = ["*"]
}

variable "service_bus_queue_max_size_in_megabytes" {
  description = "Maximum size of the Service Bus queue in megabytes"
  type        = number
  default     = 1024
  
  validation {
    condition     = var.service_bus_queue_max_size_in_megabytes >= 1024 && var.service_bus_queue_max_size_in_megabytes <= 81920
    error_message = "Service Bus queue max size must be between 1024 and 81920 megabytes."
  }
}

variable "function_timeout_minutes" {
  description = "Function execution timeout in minutes (max 30 minutes for Consumption plan)"
  type        = number
  default     = 5
  
  validation {
    condition     = var.function_timeout_minutes >= 1 && var.function_timeout_minutes <= 30
    error_message = "Function timeout must be between 1 and 30 minutes."
  }
}

variable "tags" {
  description = "A map of tags to add to all resources"
  type        = map(string)
  default = {
    Purpose     = "Team Poll System"
    Environment = "Demo"
    Project     = "Serverless Recipe"
  }
}