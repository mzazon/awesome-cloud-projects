# Variable Definitions for Basic Database Web App
# These variables allow customization of the infrastructure deployment

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
      "Switzerland North", "Norway East", "Sweden Central", "Australia East",
      "Australia Southeast", "Southeast Asia", "East Asia", "Japan East",
      "Japan West", "Korea Central", "South India", "Central India"
    ], var.location)
    error_message = "The location must be a valid Azure region."
  }
}

variable "resource_group_name" {
  description = "Name of the Azure resource group to contain all resources"
  type        = string
  default     = null
  
  validation {
    condition     = var.resource_group_name == null || can(regex("^[a-zA-Z0-9._\\-\\(\\)]+[a-zA-Z0-9._\\-\\(\\)]$", var.resource_group_name))
    error_message = "Resource group name must be valid Azure resource group name."
  }
}

variable "environment" {
  description = "Environment name for resource tagging and naming"
  type        = string
  default     = "demo"
  
  validation {
    condition     = contains(["dev", "staging", "prod", "demo", "test"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod, demo, test."
  }
}

variable "project_name" {
  description = "Project name used for resource naming and tagging"
  type        = string
  default     = "webapp"
  
  validation {
    condition     = can(regex("^[a-z0-9]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters and numbers."
  }
}

# SQL Database Configuration Variables
variable "sql_admin_username" {
  description = "Administrator username for the SQL Database server"
  type        = string
  default     = "sqladmin"
  
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9]{1,127}$", var.sql_admin_username))
    error_message = "SQL admin username must start with a letter and be 2-128 characters long."
  }
}

variable "sql_admin_password" {
  description = "Administrator password for the SQL Database server"
  type        = string
  sensitive   = true
  default     = null
  
  validation {
    condition = var.sql_admin_password == null || (
      length(var.sql_admin_password) >= 8 &&
      length(var.sql_admin_password) <= 128 &&
      can(regex("[A-Z]", var.sql_admin_password)) &&
      can(regex("[a-z]", var.sql_admin_password)) &&
      can(regex("[0-9]", var.sql_admin_password)) &&
      can(regex("[!@#$%^&*(),.?\":{}|<>]", var.sql_admin_password))
    )
    error_message = "SQL admin password must be 8-128 characters with uppercase, lowercase, number, and special character."
  }
}

variable "sql_database_name" {
  description = "Name of the SQL Database"
  type        = string
  default     = "TasksDB"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9_\\-]{0,127}$", var.sql_database_name))
    error_message = "Database name must start with letter/number and be 1-128 characters."
  }
}

variable "sql_sku_name" {
  description = "SKU name for the SQL Database (determines performance and cost)"
  type        = string
  default     = "Basic"
  
  validation {
    condition = contains([
      "Basic", "S0", "S1", "S2", "S3", "S4", "S6", "S7", "S9", "S12",
      "P1", "P2", "P4", "P6", "P11", "P15", "GP_Gen5_2", "GP_Gen5_4",
      "GP_Gen5_8", "GP_Gen5_16", "GP_Gen5_32", "GP_Gen5_80", "BC_Gen5_2"
    ], var.sql_sku_name)
    error_message = "SQL SKU must be a valid Azure SQL Database service tier."
  }
}

# App Service Configuration Variables
variable "app_service_sku_tier" {
  description = "The pricing tier for the App Service Plan"
  type        = string
  default     = "Basic"
  
  validation {
    condition     = contains(["Free", "Shared", "Basic", "Standard", "Premium", "PremiumV2", "PremiumV3"], var.app_service_sku_tier)
    error_message = "App Service SKU tier must be a valid Azure App Service pricing tier."
  }
}

variable "app_service_sku_size" {
  description = "The size of the App Service Plan instances"
  type        = string
  default     = "B1"
  
  validation {
    condition = contains([
      "F1", "D1", "B1", "B2", "B3", "S1", "S2", "S3",
      "P1", "P2", "P3", "P1V2", "P2V2", "P3V2", "P1V3", "P2V3", "P3V3"
    ], var.app_service_sku_size)
    error_message = "App Service SKU size must be a valid Azure App Service instance size."
  }
}

variable "dotnet_version" {
  description = "The .NET version for the web app runtime"
  type        = string
  default     = "8.0"
  
  validation {
    condition     = contains(["6.0", "7.0", "8.0"], var.dotnet_version)
    error_message = "Supported .NET versions are 6.0, 7.0, and 8.0."
  }
}

# Security and Compliance Variables
variable "enable_system_assigned_identity" {
  description = "Whether to enable system-assigned managed identity for the web app"
  type        = bool
  default     = true
}

variable "allow_azure_services_access" {
  description = "Whether to allow Azure services to access the SQL Database"
  type        = bool
  default     = true
}

variable "backup_retention_days" {
  description = "Number of days to retain automated backups for SQL Database"
  type        = number
  default     = 7
  
  validation {
    condition     = var.backup_retention_days >= 1 && var.backup_retention_days <= 35
    error_message = "Backup retention days must be between 1 and 35."
  }
}

# Tagging Variables
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "enable_monitoring" {
  description = "Whether to enable Application Insights for monitoring"
  type        = bool
  default     = false
}