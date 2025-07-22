# Variables for Azure MariaDB to MySQL Migration Infrastructure
# This file defines all configurable parameters for the migration infrastructure

variable "resource_group_name" {
  description = "Name of the Azure resource group for migration resources"
  type        = string
  default     = "rg-mariadb-migration"
  
  validation {
    condition     = length(var.resource_group_name) > 0 && length(var.resource_group_name) <= 90
    error_message = "Resource group name must be between 1 and 90 characters."
  }
}

variable "location" {
  description = "Azure region for deploying resources"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "North Central US", "South Central US",
      "Canada Central", "Canada East", "UK South", "UK West",
      "West Europe", "North Europe", "France Central", "Germany West Central",
      "Switzerland North", "Norway East", "Sweden Central",
      "Australia East", "Australia Southeast", "Japan East", "Japan West",
      "Korea Central", "Southeast Asia", "East Asia", "Central India",
      "South India", "West India", "Brazil South", "South Africa North"
    ], var.location)
    error_message = "Location must be a valid Azure region."
  }
}

variable "environment" {
  description = "Environment tag for resources (dev, staging, production)"
  type        = string
  default     = "production"
  
  validation {
    condition     = contains(["dev", "staging", "production"], var.environment)
    error_message = "Environment must be one of: dev, staging, production."
  }
}

# Source MariaDB Configuration
variable "source_mariadb_server_name" {
  description = "Name of the source Azure Database for MariaDB server"
  type        = string
  default     = ""
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.source_mariadb_server_name)) || var.source_mariadb_server_name == ""
    error_message = "MariaDB server name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "source_mariadb_admin_username" {
  description = "Administrator username for source MariaDB server"
  type        = string
  default     = "mariadbadmin"
  sensitive   = true
  
  validation {
    condition     = length(var.source_mariadb_admin_username) >= 1 && length(var.source_mariadb_admin_username) <= 63
    error_message = "Admin username must be between 1 and 63 characters."
  }
}

variable "source_mariadb_admin_password" {
  description = "Administrator password for source MariaDB server"
  type        = string
  default     = ""
  sensitive   = true
  
  validation {
    condition = var.source_mariadb_admin_password == "" || (
      length(var.source_mariadb_admin_password) >= 8 &&
      length(var.source_mariadb_admin_password) <= 128 &&
      can(regex("[A-Z]", var.source_mariadb_admin_password)) &&
      can(regex("[a-z]", var.source_mariadb_admin_password)) &&
      can(regex("[0-9]", var.source_mariadb_admin_password))
    )
    error_message = "Password must be 8-128 characters with uppercase, lowercase, and numeric characters."
  }
}

# Target MySQL Flexible Server Configuration
variable "target_mysql_server_name" {
  description = "Name of the target Azure Database for MySQL Flexible Server"
  type        = string
  default     = ""
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.target_mysql_server_name)) || var.target_mysql_server_name == ""
    error_message = "MySQL server name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "target_mysql_admin_username" {
  description = "Administrator username for target MySQL Flexible Server"
  type        = string
  default     = "mysqladmin"
  sensitive   = true
  
  validation {
    condition     = length(var.target_mysql_admin_username) >= 1 && length(var.target_mysql_admin_username) <= 63
    error_message = "Admin username must be between 1 and 63 characters."
  }
}

variable "target_mysql_admin_password" {
  description = "Administrator password for target MySQL Flexible Server"
  type        = string
  default     = ""
  sensitive   = true
  
  validation {
    condition = var.target_mysql_admin_password == "" || (
      length(var.target_mysql_admin_password) >= 8 &&
      length(var.target_mysql_admin_password) <= 128 &&
      can(regex("[A-Z]", var.target_mysql_admin_password)) &&
      can(regex("[a-z]", var.target_mysql_admin_password)) &&
      can(regex("[0-9]", var.target_mysql_admin_password))
    )
    error_message = "Password must be 8-128 characters with uppercase, lowercase, and numeric characters."
  }
}

variable "mysql_version" {
  description = "MySQL version for the Flexible Server"
  type        = string
  default     = "5.7"
  
  validation {
    condition     = contains(["5.7", "8.0"], var.mysql_version)
    error_message = "MySQL version must be either 5.7 or 8.0."
  }
}

variable "mysql_sku_name" {
  description = "SKU name for MySQL Flexible Server"
  type        = string
  default     = "Standard_D2ds_v4"
  
  validation {
    condition = contains([
      "Standard_B1s", "Standard_B1ms", "Standard_B2s",
      "Standard_D2s_v3", "Standard_D4s_v3", "Standard_D8s_v3",
      "Standard_D2ds_v4", "Standard_D4ds_v4", "Standard_D8ds_v4",
      "Standard_E2s_v3", "Standard_E4s_v3", "Standard_E8s_v3"
    ], var.mysql_sku_name)
    error_message = "SKU name must be a valid MySQL Flexible Server compute size."
  }
}

variable "mysql_storage_gb" {
  description = "Storage size in GB for MySQL Flexible Server"
  type        = number
  default     = 128
  
  validation {
    condition     = var.mysql_storage_gb >= 20 && var.mysql_storage_gb <= 16384
    error_message = "Storage size must be between 20 GB and 16,384 GB."
  }
}

variable "mysql_backup_retention_days" {
  description = "Backup retention period in days for MySQL Flexible Server"
  type        = number
  default     = 35
  
  validation {
    condition     = var.mysql_backup_retention_days >= 1 && var.mysql_backup_retention_days <= 35
    error_message = "Backup retention must be between 1 and 35 days."
  }
}

variable "enable_high_availability" {
  description = "Enable zone-redundant high availability for MySQL Flexible Server"
  type        = bool
  default     = true
}

variable "enable_auto_grow" {
  description = "Enable auto-grow for MySQL Flexible Server storage"
  type        = bool
  default     = true
}

# Monitoring and Logging Configuration
variable "log_analytics_sku" {
  description = "SKU for Log Analytics workspace"
  type        = string
  default     = "PerGB2018"
  
  validation {
    condition     = contains(["Free", "PerNode", "PerGB2018", "Premium", "Standalone"], var.log_analytics_sku)
    error_message = "Log Analytics SKU must be a valid pricing tier."
  }
}

variable "log_retention_days" {
  description = "Log retention period in days for Log Analytics workspace"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_retention_days >= 30 && var.log_retention_days <= 730
    error_message = "Log retention must be between 30 and 730 days."
  }
}

# Networking Configuration
variable "enable_public_access" {
  description = "Enable public network access for database servers"
  type        = bool
  default     = true
}

variable "allowed_ip_ranges" {
  description = "List of allowed IP address ranges for database access"
  type = list(object({
    name     = string
    start_ip = string
    end_ip   = string
  }))
  default = [
    {
      name     = "AllowAzureServices"
      start_ip = "0.0.0.0"
      end_ip   = "0.0.0.0"
    }
  ]
}

# Migration Configuration
variable "enable_migration_storage" {
  description = "Create storage account for migration artifacts"
  type        = bool
  default     = true
}

variable "storage_account_tier" {
  description = "Storage account tier for migration artifacts"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be either Standard or Premium."
  }
}

variable "storage_replication_type" {
  description = "Storage replication type for migration artifacts"
  type        = string
  default     = "LRS"
  
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS"], var.storage_replication_type)
    error_message = "Storage replication type must be LRS, GRS, RAGRS, or ZRS."
  }
}

# Alert Configuration
variable "enable_alerts" {
  description = "Enable monitoring alerts for database servers"
  type        = bool
  default     = true
}

variable "cpu_alert_threshold" {
  description = "CPU usage threshold for alerts (percentage)"
  type        = number
  default     = 80
  
  validation {
    condition     = var.cpu_alert_threshold >= 50 && var.cpu_alert_threshold <= 95
    error_message = "CPU alert threshold must be between 50% and 95%."
  }
}

variable "connection_alert_threshold" {
  description = "Connection count threshold for alerts"
  type        = number
  default     = 800
  
  validation {
    condition     = var.connection_alert_threshold >= 100 && var.connection_alert_threshold <= 2000
    error_message = "Connection alert threshold must be between 100 and 2000."
  }
}

variable "storage_alert_threshold" {
  description = "Storage usage threshold for alerts (percentage)"
  type        = number
  default     = 85
  
  validation {
    condition     = var.storage_alert_threshold >= 70 && var.storage_alert_threshold <= 95
    error_message = "Storage alert threshold must be between 70% and 95%."
  }
}

# Tagging Configuration
variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default = {
    Project     = "MariaDB-MySQL-Migration"
    Owner       = "Database-Team"
    CostCenter  = "IT-Operations"
    ManagedBy   = "Terraform"
  }
}