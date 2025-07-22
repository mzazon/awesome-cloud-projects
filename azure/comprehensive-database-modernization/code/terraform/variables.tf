# Azure Database Migration Service with Azure Backup - Variables
# This file defines all input variables for the database modernization infrastructure

variable "resource_group_name" {
  description = "Name of the resource group for all resources"
  type        = string
  default     = "rg-db-migration"
}

variable "location" {
  description = "Azure region where resources will be created"
  type        = string
  default     = "East US"
  
  validation {
    condition = can(regex("^[A-Za-z0-9 ]+$", var.location))
    error_message = "Location must be a valid Azure region name."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "demo"
  
  validation {
    condition     = contains(["dev", "staging", "prod", "demo"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod, demo."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "dbmigration"
  
  validation {
    condition     = can(regex("^[a-z0-9]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters and numbers."
  }
}

# SQL Server Configuration
variable "sql_server_admin_username" {
  description = "Administrator username for Azure SQL Server"
  type        = string
  default     = "sqladmin"
  
  validation {
    condition     = length(var.sql_server_admin_username) > 0
    error_message = "SQL Server admin username cannot be empty."
  }
}

variable "sql_server_admin_password" {
  description = "Administrator password for Azure SQL Server"
  type        = string
  sensitive   = true
  default     = "ComplexP@ssw0rd123!"
  
  validation {
    condition     = length(var.sql_server_admin_password) >= 8
    error_message = "SQL Server admin password must be at least 8 characters long."
  }
}

variable "sql_database_name" {
  description = "Name of the Azure SQL Database"
  type        = string
  default     = "modernized-db"
}

variable "sql_database_sku" {
  description = "SKU/service tier for the Azure SQL Database"
  type        = string
  default     = "S2"
  
  validation {
    condition = contains([
      "Basic", "S0", "S1", "S2", "S3", "S4", "S6", "S7", "S9", "S12",
      "P1", "P2", "P4", "P6", "P11", "P15",
      "GP_Gen5_2", "GP_Gen5_4", "GP_Gen5_8", "GP_Gen5_16", "GP_Gen5_32",
      "BC_Gen5_2", "BC_Gen5_4", "BC_Gen5_8", "BC_Gen5_16", "BC_Gen5_32"
    ], var.sql_database_sku)
    error_message = "SQL Database SKU must be a valid Azure SQL Database service tier."
  }
}

variable "sql_backup_storage_redundancy" {
  description = "Backup storage redundancy for Azure SQL Database"
  type        = string
  default     = "Local"
  
  validation {
    condition     = contains(["Local", "Zone", "Geo"], var.sql_backup_storage_redundancy)
    error_message = "Backup storage redundancy must be one of: Local, Zone, Geo."
  }
}

# Database Migration Service Configuration
variable "dms_sku_name" {
  description = "SKU name for Azure Database Migration Service"
  type        = string
  default     = "Premium_4vCores"
  
  validation {
    condition = contains([
      "Standard_1vCores", "Standard_2vCores", "Standard_4vCores",
      "Premium_1vCores", "Premium_2vCores", "Premium_4vCores"
    ], var.dms_sku_name)
    error_message = "DMS SKU must be a valid Azure Database Migration Service SKU."
  }
}

# Storage Account Configuration
variable "storage_account_tier" {
  description = "Performance tier for the storage account"
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
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_account_replication_type)
    error_message = "Storage replication type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

variable "storage_account_access_tier" {
  description = "Access tier for the storage account"
  type        = string
  default     = "Hot"
  
  validation {
    condition     = contains(["Hot", "Cool"], var.storage_account_access_tier)
    error_message = "Storage access tier must be either Hot or Cool."
  }
}

# Recovery Services Vault Configuration
variable "backup_vault_storage_model_type" {
  description = "Storage model type for the Recovery Services Vault"
  type        = string
  default     = "LocallyRedundant"
  
  validation {
    condition     = contains(["LocallyRedundant", "GeoRedundant", "ReadAccessGeoRedundant"], var.backup_vault_storage_model_type)
    error_message = "Backup vault storage model must be one of: LocallyRedundant, GeoRedundant, ReadAccessGeoRedundant."
  }
}

variable "backup_policy_timezone" {
  description = "Timezone for backup policy schedules"
  type        = string
  default     = "UTC"
}

variable "backup_policy_retention_days" {
  description = "Number of days to retain daily backups"
  type        = number
  default     = 30
  
  validation {
    condition     = var.backup_policy_retention_days >= 7 && var.backup_policy_retention_days <= 9999
    error_message = "Backup retention days must be between 7 and 9999."
  }
}

variable "backup_policy_time" {
  description = "Time of day for backup policy (24-hour format, e.g., 02:00)"
  type        = string
  default     = "02:00"
  
  validation {
    condition     = can(regex("^([0-1][0-9]|2[0-3]):[0-5][0-9]$", var.backup_policy_time))
    error_message = "Backup policy time must be in 24-hour format (HH:MM)."
  }
}

# Log Analytics Configuration
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
  description = "Number of days to retain log data"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_analytics_retention_days >= 7 && var.log_analytics_retention_days <= 730
    error_message = "Log Analytics retention days must be between 7 and 730."
  }
}

# Monitoring and Alerting Configuration
variable "alert_email_address" {
  description = "Email address for migration and backup alerts"
  type        = string
  default     = "admin@contoso.com"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.alert_email_address))
    error_message = "Alert email address must be a valid email format."
  }
}

variable "enable_advanced_threat_protection" {
  description = "Enable Advanced Threat Protection for Azure SQL Database"
  type        = bool
  default     = true
}

variable "enable_vulnerability_assessments" {
  description = "Enable vulnerability assessments for Azure SQL Database"
  type        = bool
  default     = true
}

# Network Configuration
variable "allowed_ip_addresses" {
  description = "List of IP addresses allowed to access the SQL Server"
  type        = list(string)
  default     = []
}

variable "enable_public_network_access" {
  description = "Enable public network access for Azure SQL Server"
  type        = bool
  default     = true
}

# Tags
variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Purpose     = "database-migration"
    Environment = "demo"
    Project     = "database-modernization"
    ManagedBy   = "terraform"
  }
}