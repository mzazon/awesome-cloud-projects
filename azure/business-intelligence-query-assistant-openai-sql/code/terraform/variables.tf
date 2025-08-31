# Variables for Azure Business Intelligence Query Assistant Infrastructure

variable "resource_group_name" {
  description = "Name of the Azure resource group"
  type        = string
  default     = "rg-bi-assistant"
  
  validation {
    condition     = length(var.resource_group_name) <= 90 && can(regex("^[a-zA-Z0-9._()-]+$", var.resource_group_name))
    error_message = "Resource group name must be 1-90 characters and contain only letters, numbers, periods, underscores, hyphens, and parentheses."
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
      "Switzerland North", "Norway East", "Sweden Central", "Australia East",
      "Australia Southeast", "East Asia", "Southeast Asia", "Japan East",
      "Japan West", "Korea Central", "Central India", "South India", "West India"
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
  description = "Project name for resource naming and tagging"
  type        = string
  default     = "bi-assistant"
  
  validation {
    condition     = length(var.project_name) <= 20 && can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must be 1-20 characters, lowercase letters, numbers, and hyphens only."
  }
}

variable "sql_admin_username" {
  description = "SQL Server administrator username"
  type        = string
  default     = "sqladmin"
  
  validation {
    condition     = length(var.sql_admin_username) >= 1 && length(var.sql_admin_username) <= 128
    error_message = "SQL admin username must be between 1 and 128 characters."
  }
}

variable "sql_admin_password" {
  description = "SQL Server administrator password"
  type        = string
  sensitive   = true
  default     = null
  
  validation {
    condition = var.sql_admin_password == null || (
      length(var.sql_admin_password) >= 8 && 
      length(var.sql_admin_password) <= 128 &&
      can(regex("^(?=.*[a-z])(?=.*[A-Z])(?=.*\\d)(?=.*[@$!%*?&])[A-Za-z\\d@$!%*?&]", var.sql_admin_password))
    )
    error_message = "SQL admin password must be 8-128 characters with uppercase, lowercase, number, and special character."
  }
}

variable "sql_database_name" {
  description = "Name of the SQL database"
  type        = string
  default     = "BiAnalyticsDB"
  
  validation {
    condition     = length(var.sql_database_name) >= 1 && length(var.sql_database_name) <= 128
    error_message = "Database name must be between 1 and 128 characters."
  }
}

variable "sql_database_sku" {
  description = "SQL Database SKU"
  type        = string
  default     = "Basic"
  
  validation {
    condition = contains([
      "Basic", "S0", "S1", "S2", "S3", "S4", "S6", "S7", "S9", "S12",
      "P1", "P2", "P4", "P6", "P11", "P15", "GP_S_Gen5_1", "GP_S_Gen5_2",
      "GP_Gen5_2", "GP_Gen5_4", "GP_Gen5_6", "GP_Gen5_8", "GP_Gen5_10"
    ], var.sql_database_sku)
    error_message = "SQL Database SKU must be a valid Azure SQL Database service tier."
  }
}

variable "openai_model_name" {
  description = "Azure OpenAI model name to deploy"
  type        = string
  default     = "gpt-4o"
  
  validation {
    condition = contains([
      "gpt-4o", "gpt-4", "gpt-4-32k", "gpt-35-turbo", "gpt-35-turbo-16k"
    ], var.openai_model_name)
    error_message = "OpenAI model must be a supported Azure OpenAI model."
  }
}

variable "openai_model_version" {
  description = "Azure OpenAI model version"
  type        = string
  default     = "2024-11-20"
}

variable "openai_deployment_capacity" {
  description = "Capacity for OpenAI model deployment (tokens per minute)"
  type        = number
  default     = 10
  
  validation {
    condition     = var.openai_deployment_capacity >= 1 && var.openai_deployment_capacity <= 100
    error_message = "OpenAI deployment capacity must be between 1 and 100."
  }
}

variable "function_app_runtime" {
  description = "Function App runtime stack"
  type        = string
  default     = "node"
  
  validation {
    condition     = contains(["node", "dotnet", "python", "java"], var.function_app_runtime)
    error_message = "Function App runtime must be one of: node, dotnet, python, java."
  }
}

variable "function_app_runtime_version" {
  description = "Function App runtime version"
  type        = string
  default     = "18"
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

variable "enable_application_insights" {
  description = "Enable Application Insights for Function App monitoring"
  type        = bool
  default     = true
}

variable "enable_managed_identity" {
  description = "Enable managed identity for Function App"
  type        = bool
  default     = true
}

variable "allowed_ip_ranges" {
  description = "List of IP ranges allowed to access SQL Database"
  type        = list(string)
  default     = []
  
  validation {
    condition = alltrue([
      for ip in var.allowed_ip_ranges : can(cidrhost(ip, 0))
    ])
    error_message = "All IP ranges must be valid CIDR notation."
  }
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Purpose     = "Business Intelligence"
    Environment = "Demo"
    CreatedBy   = "Terraform"
  }
}