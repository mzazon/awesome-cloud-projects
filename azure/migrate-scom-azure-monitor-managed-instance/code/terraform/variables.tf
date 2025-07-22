# Variables for SCOM Migration to Azure Monitor SCOM Managed Instance
# This file defines all the configurable parameters for the deployment

# Basic Configuration Variables
variable "location" {
  description = "The Azure region where resources will be created"
  type        = string
  default     = "East US"
  
  validation {
    condition = can(regex("^[A-Za-z0-9 ]+$", var.location))
    error_message = "Location must be a valid Azure region name."
  }
}

variable "resource_group_name" {
  description = "Name of the resource group for SCOM migration resources"
  type        = string
  default     = "rg-scom-migration"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._-]+$", var.resource_group_name))
    error_message = "Resource group name must contain only alphanumeric characters, periods, underscores, and hyphens."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "production"
  
  validation {
    condition     = contains(["dev", "staging", "prod", "production"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod, production."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "scom-migration"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.project_name))
    error_message = "Project name must contain only alphanumeric characters and hyphens."
  }
}

# Network Configuration Variables
variable "virtual_network_address_space" {
  description = "Address space for the virtual network"
  type        = list(string)
  default     = ["10.0.0.0/16"]
  
  validation {
    condition     = length(var.virtual_network_address_space) > 0
    error_message = "At least one address space must be specified."
  }
}

variable "scom_subnet_address_prefix" {
  description = "Address prefix for the SCOM Managed Instance subnet"
  type        = string
  default     = "10.0.1.0/24"
  
  validation {
    condition     = can(cidrhost(var.scom_subnet_address_prefix, 0))
    error_message = "SCOM subnet address prefix must be a valid CIDR block."
  }
}

variable "sql_subnet_address_prefix" {
  description = "Address prefix for the SQL Managed Instance subnet"
  type        = string
  default     = "10.0.2.0/27"
  
  validation {
    condition     = can(cidrhost(var.sql_subnet_address_prefix, 0))
    error_message = "SQL subnet address prefix must be a valid CIDR block."
  }
}

# SQL Managed Instance Configuration Variables
variable "sql_managed_instance_name" {
  description = "Name for the SQL Managed Instance"
  type        = string
  default     = null
  
  validation {
    condition     = var.sql_managed_instance_name == null || can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.sql_managed_instance_name))
    error_message = "SQL MI name must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

variable "sql_admin_username" {
  description = "Administrator username for SQL Managed Instance"
  type        = string
  default     = "scomadmin"
  
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]*$", var.sql_admin_username))
    error_message = "SQL admin username must start with a letter and contain only letters, numbers, and underscores."
  }
}

variable "sql_admin_password" {
  description = "Administrator password for SQL Managed Instance"
  type        = string
  sensitive   = true
  default     = null
  
  validation {
    condition     = var.sql_admin_password == null || can(regex("^(?=.*[a-z])(?=.*[A-Z])(?=.*\\d)(?=.*[@$!%*?&])[A-Za-z\\d@$!%*?&]{12,}$", var.sql_admin_password))
    error_message = "SQL admin password must be at least 12 characters long and contain uppercase, lowercase, numbers, and special characters."
  }
}

variable "sql_sku_name" {
  description = "SKU name for SQL Managed Instance"
  type        = string
  default     = "GP_Gen5"
  
  validation {
    condition     = contains(["GP_Gen5", "BC_Gen5", "GP_Gen8IM", "BC_Gen8IM"], var.sql_sku_name)
    error_message = "SQL SKU must be one of: GP_Gen5, BC_Gen5, GP_Gen8IM, BC_Gen8IM."
  }
}

variable "sql_vcores" {
  description = "Number of vCores for SQL Managed Instance"
  type        = number
  default     = 8
  
  validation {
    condition     = var.sql_vcores >= 4 && var.sql_vcores <= 80
    error_message = "SQL vCores must be between 4 and 80."
  }
}

variable "sql_storage_size_gb" {
  description = "Storage size in GB for SQL Managed Instance"
  type        = number
  default     = 256
  
  validation {
    condition     = var.sql_storage_size_gb >= 32 && var.sql_storage_size_gb <= 16384
    error_message = "SQL storage size must be between 32 and 16384 GB."
  }
}

variable "sql_license_type" {
  description = "License type for SQL Managed Instance"
  type        = string
  default     = "BasePrice"
  
  validation {
    condition     = contains(["BasePrice", "LicenseIncluded"], var.sql_license_type)
    error_message = "SQL license type must be either BasePrice or LicenseIncluded."
  }
}

# SCOM Managed Instance Configuration Variables
variable "scom_managed_instance_name" {
  description = "Name for the SCOM Managed Instance"
  type        = string
  default     = null
  
  validation {
    condition     = var.scom_managed_instance_name == null || can(regex("^[a-zA-Z][a-zA-Z0-9-]*[a-zA-Z0-9]$", var.scom_managed_instance_name))
    error_message = "SCOM MI name must start with a letter, contain only letters, numbers, and hyphens, and end with a letter or number."
  }
}

variable "scom_domain_name" {
  description = "Domain name for SCOM Managed Instance"
  type        = string
  default     = "contoso.com"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.scom_domain_name))
    error_message = "Domain name must be a valid FQDN format."
  }
}

variable "scom_domain_user_name" {
  description = "Domain username for SCOM Managed Instance"
  type        = string
  default     = "scomuser"
  
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]*$", var.scom_domain_user_name))
    error_message = "Domain username must start with a letter and contain only letters, numbers, and underscores."
  }
}

variable "scom_domain_user_password" {
  description = "Domain user password for SCOM Managed Instance"
  type        = string
  sensitive   = true
  default     = null
  
  validation {
    condition     = var.scom_domain_user_password == null || can(regex("^(?=.*[a-z])(?=.*[A-Z])(?=.*\\d)(?=.*[@$!%*?&])[A-Za-z\\d@$!%*?&]{12,}$", var.scom_domain_user_password))
    error_message = "Domain user password must be at least 12 characters long and contain uppercase, lowercase, numbers, and special characters."
  }
}

# Key Vault Configuration Variables
variable "key_vault_name" {
  description = "Name for the Key Vault"
  type        = string
  default     = null
  
  validation {
    condition     = var.key_vault_name == null || can(regex("^[a-zA-Z][a-zA-Z0-9-]*[a-zA-Z0-9]$", var.key_vault_name))
    error_message = "Key Vault name must start with a letter, contain only letters, numbers, and hyphens, and end with a letter or number."
  }
}

variable "key_vault_sku_name" {
  description = "SKU name for Key Vault"
  type        = string
  default     = "standard"
  
  validation {
    condition     = contains(["standard", "premium"], var.key_vault_sku_name)
    error_message = "Key Vault SKU must be either standard or premium."
  }
}

# Log Analytics Configuration Variables
variable "log_analytics_workspace_name" {
  description = "Name for the Log Analytics workspace"
  type        = string
  default     = null
  
  validation {
    condition     = var.log_analytics_workspace_name == null || can(regex("^[a-zA-Z][a-zA-Z0-9-]*[a-zA-Z0-9]$", var.log_analytics_workspace_name))
    error_message = "Log Analytics workspace name must start with a letter, contain only letters, numbers, and hyphens, and end with a letter or number."
  }
}

variable "log_analytics_retention_days" {
  description = "Retention period in days for Log Analytics workspace"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_analytics_retention_days >= 30 && var.log_analytics_retention_days <= 730
    error_message = "Log Analytics retention days must be between 30 and 730."
  }
}

variable "log_analytics_sku" {
  description = "SKU for Log Analytics workspace"
  type        = string
  default     = "PerGB2018"
  
  validation {
    condition     = contains(["Free", "Standalone", "PerNode", "PerGB2018"], var.log_analytics_sku)
    error_message = "Log Analytics SKU must be one of: Free, Standalone, PerNode, PerGB2018."
  }
}

# Storage Account Configuration Variables
variable "storage_account_name" {
  description = "Name for the storage account used for migration"
  type        = string
  default     = null
  
  validation {
    condition     = var.storage_account_name == null || can(regex("^[a-z0-9]{3,24}$", var.storage_account_name))
    error_message = "Storage account name must be 3-24 characters long and contain only lowercase letters and numbers."
  }
}

variable "storage_account_tier" {
  description = "Tier for the storage account"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be either Standard or Premium."
  }
}

variable "storage_account_replication_type" {
  description = "Replication type for the storage account"
  type        = string
  default     = "LRS"
  
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS"], var.storage_account_replication_type)
    error_message = "Storage account replication type must be one of: LRS, GRS, RAGRS, ZRS."
  }
}

# Action Group Configuration Variables
variable "action_group_name" {
  description = "Name for the Action Group for alerts"
  type        = string
  default     = "ag-scom-alerts"
  
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]*[a-zA-Z0-9]$", var.action_group_name))
    error_message = "Action group name must start with a letter, contain only letters, numbers, and hyphens, and end with a letter or number."
  }
}

variable "alert_email_receivers" {
  description = "List of email receivers for alerts"
  type = list(object({
    name  = string
    email = string
  }))
  default = [
    {
      name  = "admin"
      email = "admin@company.com"
    }
  ]
  
  validation {
    condition     = length(var.alert_email_receivers) > 0
    error_message = "At least one email receiver must be specified."
  }
}

# Tagging Variables
variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default = {
    Purpose     = "SCOM Migration"
    Environment = "Production"
    Owner       = "IT Operations"
    Project     = "Azure Migration"
  }
}

# Network Security Variables
variable "allowed_source_ip_ranges" {
  description = "List of IP ranges allowed to access SCOM services"
  type        = list(string)
  default     = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
  
  validation {
    condition     = length(var.allowed_source_ip_ranges) > 0
    error_message = "At least one IP range must be specified."
  }
}

# Backup Configuration Variables
variable "enable_backup" {
  description = "Enable automatic backups for SQL Managed Instance"
  type        = bool
  default     = true
}

variable "backup_retention_days" {
  description = "Number of days to retain backups"
  type        = number
  default     = 7
  
  validation {
    condition     = var.backup_retention_days >= 7 && var.backup_retention_days <= 35
    error_message = "Backup retention days must be between 7 and 35."
  }
}

# Monitoring Configuration Variables
variable "enable_monitoring" {
  description = "Enable Azure Monitor integration"
  type        = bool
  default     = true
}

variable "enable_diagnostics" {
  description = "Enable diagnostic settings for resources"
  type        = bool
  default     = true
}

# High Availability Configuration Variables
variable "enable_high_availability" {
  description = "Enable high availability features"
  type        = bool
  default     = true
}

variable "availability_zone" {
  description = "Availability zone for resources (if supported in region)"
  type        = string
  default     = null
  
  validation {
    condition     = var.availability_zone == null || can(regex("^[1-3]$", var.availability_zone))
    error_message = "Availability zone must be 1, 2, or 3."
  }
}