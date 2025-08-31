# Variables for Azure Email Notifications Infrastructure

variable "location" {
  description = "The Azure region where resources will be created"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "North Central US", "South Central US", "West Central US",
      "Canada Central", "Canada East", "Brazil South", "UK South", "UK West",
      "West Europe", "North Europe", "France Central", "Germany West Central",
      "Norway East", "Switzerland North", "UAE North", "South Africa North",
      "Australia East", "Australia Southeast", "Southeast Asia", "East Asia",
      "Japan East", "Japan West", "Korea Central", "India Central"
    ], var.location)
    error_message = "The location must be a valid Azure region."
  }
}

variable "environment" {
  description = "Environment name for resource naming and tagging"
  type        = string
  default     = "demo"
  
  validation {
    condition     = can(regex("^[a-z0-9-]{2,10}$", var.environment))
    error_message = "Environment must be 2-10 characters, lowercase letters, numbers, and hyphens only."
  }
}

variable "project_name" {
  description = "Project name for resource naming and tagging"
  type        = string
  default     = "email-notifications"
  
  validation {
    condition     = can(regex("^[a-z0-9-]{2,20}$", var.project_name))
    error_message = "Project name must be 2-20 characters, lowercase letters, numbers, and hyphens only."
  }
}

variable "resource_group_name" {
  description = "Name of the resource group. If not provided, will be generated based on project_name and environment"
  type        = string
  default     = ""
}

variable "communication_services_data_location" {
  description = "Data residency location for Communication Services"
  type        = string
  default     = "United States"
  
  validation {
    condition = contains([
      "Africa", "Asia Pacific", "Australia", "Brazil", "Canada", "Europe", 
      "France", "Germany", "India", "Japan", "Korea", "Norway", "Switzerland", 
      "UAE", "UK", "United States"
    ], var.communication_services_data_location)
    error_message = "Data location must be a valid Communication Services data residency location."
  }
}

variable "function_app_plan_sku_size" {
  description = "The SKU size for the Function App Service Plan (Y1 for Consumption plan)"
  type        = string
  default     = "Y1"
  
  validation {
    condition = contains([
      "Y1",           # Consumption plan
      "EP1", "EP2", "EP3",  # Elastic Premium plans
      "P1v2", "P2v2", "P3v2" # Premium v2 plans
    ], var.function_app_plan_sku_size)
    error_message = "SKU size must be a valid Function App plan SKU."
  }
}

variable "storage_account_tier" {
  description = "Storage account performance tier"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be Standard or Premium."
  }
}

variable "storage_account_replication_type" {
  description = "Storage account replication type"
  type        = string
  default     = "LRS"
  
  validation {
    condition = contains([
      "LRS",    # Locally redundant storage
      "GRS",    # Geo-redundant storage
      "RAGRS",  # Read-access geo-redundant storage
      "ZRS",    # Zone-redundant storage
      "GZRS",   # Geo-zone-redundant storage
      "RAGZRS"  # Read-access geo-zone-redundant storage
    ], var.storage_account_replication_type)
    error_message = "Storage replication type must be a valid Azure storage replication option."
  }
}

variable "function_runtime_version" {
  description = "Node.js runtime version for the Function App"
  type        = string
  default     = "~18"
  
  validation {
    condition     = contains(["~14", "~16", "~18", "~20"], var.function_runtime_version)
    error_message = "Function runtime version must be a supported Node.js version."
  }
}

variable "enable_application_insights" {
  description = "Enable Application Insights for Function App monitoring"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default = {
    Purpose     = "Email Notifications Recipe"
    ManagedBy   = "Terraform"
    Recipe      = "simple-email-notifications-communication-functions"
  }
}

variable "allowed_cors_origins" {
  description = "List of allowed CORS origins for the Function App"
  type        = list(string)
  default     = ["*"]
}

variable "function_timeout" {
  description = "Function execution timeout in minutes"
  type        = number
  default     = 5
  
  validation {
    condition     = var.function_timeout >= 1 && var.function_timeout <= 10
    error_message = "Function timeout must be between 1 and 10 minutes."
  }
}