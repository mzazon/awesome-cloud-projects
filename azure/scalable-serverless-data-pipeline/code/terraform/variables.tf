# Variables for Azure Serverless Data Pipeline Infrastructure

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = "rg-serverless-pipeline"
}

variable "location" {
  description = "Azure region for all resources"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "North Central US", "South Central US", "West Central US",
      "Canada Central", "Canada East", "Brazil South", "UK South", "UK West",
      "West Europe", "North Europe", "France Central", "Germany West Central",
      "Switzerland North", "Norway East", "Japan East", "Japan West",
      "Australia East", "Australia Southeast", "Southeast Asia", "East Asia",
      "South India", "Central India", "Korea Central", "South Africa North"
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
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "pipeline"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.project_name))
    error_message = "Project name must contain only alphanumeric characters and hyphens."
  }
}

variable "synapse_sql_admin_login" {
  description = "SQL administrator login for Synapse workspace"
  type        = string
  default     = "sqladmin"
  
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_-]{2,127}$", var.synapse_sql_admin_login))
    error_message = "SQL admin login must be 3-128 characters, start with a letter, and contain only letters, numbers, underscores, and hyphens."
  }
}

variable "synapse_sql_admin_password" {
  description = "SQL administrator password for Synapse workspace"
  type        = string
  default     = "P@ssw0rd123!"
  sensitive   = true
  
  validation {
    condition     = length(var.synapse_sql_admin_password) >= 8
    error_message = "SQL admin password must be at least 8 characters long."
  }
}

variable "storage_account_tier" {
  description = "Storage account tier"
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
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_account_replication_type)
    error_message = "Storage account replication type must be LRS, GRS, RAGRS, ZRS, GZRS, or RAGZRS."
  }
}

variable "enable_monitoring" {
  description = "Enable monitoring and alerting"
  type        = bool
  default     = true
}

variable "enable_firewall_rules" {
  description = "Enable firewall rules for Synapse workspace"
  type        = bool
  default     = true
}

variable "allowed_ip_ranges" {
  description = "List of IP ranges allowed to access Synapse workspace"
  type = list(object({
    name     = string
    start_ip = string
    end_ip   = string
  }))
  default = [
    {
      name     = "AllowAll"
      start_ip = "0.0.0.0"
      end_ip   = "255.255.255.255"
    }
  ]
}

variable "data_lake_containers" {
  description = "List of data lake containers to create"
  type        = list(string)
  default     = ["raw", "curated", "refined"]
}

variable "key_vault_retention_days" {
  description = "Number of days to retain deleted keys in Key Vault"
  type        = number
  default     = 7
  
  validation {
    condition     = var.key_vault_retention_days >= 7 && var.key_vault_retention_days <= 90
    error_message = "Key Vault retention days must be between 7 and 90."
  }
}

variable "tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default = {
    Environment = "demo"
    Purpose     = "data-pipeline"
    ManagedBy   = "terraform"
  }
}