# Variables for Azure Self-Service Infrastructure Provisioning with Deployment Environments

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
      "Switzerland North", "Norway East", "Sweden Central", "Poland Central",
      "Italy North", "Spain Central", "UAE North", "South Africa North",
      "Australia East", "Australia Southeast", "Australia Central",
      "Southeast Asia", "East Asia", "Japan East", "Japan West",
      "Korea Central", "India Central", "India South"
    ], var.location)
    error_message = "The location must be a valid Azure region."
  }
}

variable "resource_group_name" {
  description = "Name of the Azure resource group"
  type        = string
  default     = "rg-selfservice-infra"
  
  validation {
    condition     = length(var.resource_group_name) >= 1 && length(var.resource_group_name) <= 90
    error_message = "Resource group name must be between 1 and 90 characters."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "demo"
  
  validation {
    condition     = can(regex("^[a-z0-9]+$", var.environment))
    error_message = "Environment must contain only lowercase letters and numbers."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "selfservice"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name)) && length(var.project_name) <= 20
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens, and be max 20 characters."
  }
}

variable "devcenter_name" {
  description = "Name of the Azure DevCenter"
  type        = string
  default     = ""
}

variable "project_environment_type" {
  description = "Environment type for the DevCenter project"
  type        = string
  default     = "Development"
  
  validation {
    condition = contains([
      "Development", "Staging", "Production", "Test", "Demo"
    ], var.project_environment_type)
    error_message = "Environment type must be one of: Development, Staging, Production, Test, Demo."
  }
}

variable "catalog_repo_url" {
  description = "Git repository URL containing environment templates"
  type        = string
  default     = "https://github.com/Azure/deployment-environments"
}

variable "catalog_repo_branch" {
  description = "Git repository branch for environment templates"
  type        = string
  default     = "main"
}

variable "catalog_repo_path" {
  description = "Path within the Git repository containing environment templates"
  type        = string
  default     = "/Environments"
}

variable "max_dev_boxes_per_user" {
  description = "Maximum number of dev boxes per user in the project"
  type        = number
  default     = 3
  
  validation {
    condition     = var.max_dev_boxes_per_user >= 1 && var.max_dev_boxes_per_user <= 10
    error_message = "Maximum dev boxes per user must be between 1 and 10."
  }
}

variable "sql_admin_username" {
  description = "Administrator username for SQL Server"
  type        = string
  default     = "sqladmin"
  
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9]*$", var.sql_admin_username))
    error_message = "SQL admin username must start with a letter and contain only letters and numbers."
  }
}

variable "sql_admin_password" {
  description = "Administrator password for SQL Server"
  type        = string
  sensitive   = true
  default     = ""
  
  validation {
    condition = var.sql_admin_password == "" || (
      length(var.sql_admin_password) >= 8 &&
      can(regex("[A-Z]", var.sql_admin_password)) &&
      can(regex("[a-z]", var.sql_admin_password)) &&
      can(regex("[0-9]", var.sql_admin_password)) &&
      can(regex("[^a-zA-Z0-9]", var.sql_admin_password))
    )
    error_message = "SQL admin password must be at least 8 characters and contain uppercase, lowercase, number, and special character, or be empty to auto-generate."
  }
}

variable "sql_database_sku" {
  description = "SKU for the SQL Database"
  type        = string
  default     = "S0"
  
  validation {
    condition = contains([
      "Basic", "S0", "S1", "S2", "S3", "S4", "S6", "S7", "S9", "S12",
      "P1", "P2", "P4", "P6", "P11", "P15", "GP_Gen5_2", "GP_Gen5_4"
    ], var.sql_database_sku)
    error_message = "SQL Database SKU must be a valid Azure SQL Database service objective."
  }
}

variable "key_vault_sku" {
  description = "SKU for Azure Key Vault"
  type        = string
  default     = "standard"
  
  validation {
    condition     = contains(["standard", "premium"], var.key_vault_sku)
    error_message = "Key Vault SKU must be either 'standard' or 'premium'."
  }
}

variable "storage_account_tier" {
  description = "Storage account tier"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be either 'Standard' or 'Premium'."
  }
}

variable "storage_account_replication" {
  description = "Storage account replication type"
  type        = string
  default     = "LRS"
  
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_account_replication)
    error_message = "Storage account replication must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

variable "logic_app_recurrence_frequency" {
  description = "Frequency for lifecycle management Logic App recurrence"
  type        = string
  default     = "Day"
  
  validation {
    condition     = contains(["Day", "Hour", "Week", "Month"], var.logic_app_recurrence_frequency)
    error_message = "Logic App recurrence frequency must be one of: Day, Hour, Week, Month."
  }
}

variable "logic_app_recurrence_interval" {
  description = "Interval for lifecycle management Logic App recurrence"
  type        = number
  default     = 1
  
  validation {
    condition     = var.logic_app_recurrence_interval >= 1 && var.logic_app_recurrence_interval <= 100
    error_message = "Logic App recurrence interval must be between 1 and 100."
  }
}

variable "enable_rbac_authorization" {
  description = "Enable RBAC authorization for Key Vault"
  type        = bool
  default     = true
}

variable "enable_lifecycle_management" {
  description = "Enable automated lifecycle management for environments"
  type        = bool
  default     = true
}

variable "environment_expiry_days" {
  description = "Default environment expiry in days"
  type        = number
  default     = 7
  
  validation {
    condition     = var.environment_expiry_days >= 1 && var.environment_expiry_days <= 365
    error_message = "Environment expiry days must be between 1 and 365."
  }
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Purpose     = "selfservice-infrastructure"
    Environment = "demo"
    Owner       = "platform-team"
    Project     = "deployment-environments"
  }
}