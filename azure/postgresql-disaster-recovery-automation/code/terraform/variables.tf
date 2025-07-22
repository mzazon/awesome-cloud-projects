# Variable definitions for PostgreSQL Flexible Server disaster recovery solution
# This file contains all configurable parameters for the infrastructure deployment

# Environment and naming variables
variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "production"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.environment))
    error_message = "Environment must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "project_name" {
  description = "Name of the project (used for resource naming)"
  type        = string
  default     = "postgres-dr"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "resource_prefix" {
  description = "Prefix for all resource names"
  type        = string
  default     = "pgdr"
  
  validation {
    condition     = can(regex("^[a-z0-9]{2,6}$", var.resource_prefix))
    error_message = "Resource prefix must be 2-6 characters long and contain only lowercase letters and numbers."
  }
}

# Location variables
variable "primary_location" {
  description = "Primary Azure region for resources"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "North Central US", "South Central US", "West Central US",
      "Canada Central", "Canada East", "Brazil South", "North Europe",
      "West Europe", "UK South", "UK West", "France Central", "Germany West Central",
      "Switzerland North", "Norway East", "Sweden Central", "Australia East",
      "Australia Southeast", "Southeast Asia", "East Asia", "Japan East",
      "Japan West", "Korea Central", "South India", "Central India"
    ], var.primary_location)
    error_message = "Primary location must be a valid Azure region."
  }
}

variable "secondary_location" {
  description = "Secondary Azure region for disaster recovery"
  type        = string
  default     = "West US 2"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "North Central US", "South Central US", "West Central US",
      "Canada Central", "Canada East", "Brazil South", "North Europe",
      "West Europe", "UK South", "UK West", "France Central", "Germany West Central",
      "Switzerland North", "Norway East", "Sweden Central", "Australia East",
      "Australia Southeast", "Southeast Asia", "East Asia", "Japan East",
      "Japan West", "Korea Central", "South India", "Central India"
    ], var.secondary_location)
    error_message = "Secondary location must be a valid Azure region."
  }
}

# PostgreSQL configuration variables
variable "postgresql_version" {
  description = "PostgreSQL version"
  type        = string
  default     = "14"
  
  validation {
    condition     = contains(["11", "12", "13", "14", "15"], var.postgresql_version)
    error_message = "PostgreSQL version must be one of: 11, 12, 13, 14, 15."
  }
}

variable "postgresql_sku_name" {
  description = "PostgreSQL server SKU name"
  type        = string
  default     = "GP_Standard_D4s_v3"
  
  validation {
    condition = can(regex("^(B_|GP_|MO_)", var.postgresql_sku_name))
    error_message = "PostgreSQL SKU name must start with B_, GP_, or MO_ for Basic, General Purpose, or Memory Optimized tiers."
  }
}

variable "postgresql_storage_mb" {
  description = "PostgreSQL server storage in MB"
  type        = number
  default     = 131072 # 128 GB
  
  validation {
    condition     = var.postgresql_storage_mb >= 32768 && var.postgresql_storage_mb <= 16777216
    error_message = "PostgreSQL storage must be between 32 GB (32768 MB) and 16 TB (16777216 MB)."
  }
}

variable "postgresql_admin_username" {
  description = "PostgreSQL administrator username"
  type        = string
  default     = "pgadmin"
  
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]{0,62}$", var.postgresql_admin_username))
    error_message = "PostgreSQL admin username must start with a letter and contain only letters, numbers, and underscores (max 63 characters)."
  }
}

variable "postgresql_admin_password" {
  description = "PostgreSQL administrator password"
  type        = string
  sensitive   = true
  
  validation {
    condition     = length(var.postgresql_admin_password) >= 8 && length(var.postgresql_admin_password) <= 128
    error_message = "PostgreSQL admin password must be between 8 and 128 characters long."
  }
}

variable "postgresql_backup_retention_days" {
  description = "PostgreSQL backup retention period in days"
  type        = number
  default     = 35
  
  validation {
    condition     = var.postgresql_backup_retention_days >= 7 && var.postgresql_backup_retention_days <= 35
    error_message = "PostgreSQL backup retention days must be between 7 and 35."
  }
}

variable "postgresql_high_availability_enabled" {
  description = "Enable high availability for PostgreSQL server"
  type        = bool
  default     = true
}

variable "postgresql_geo_redundant_backup_enabled" {
  description = "Enable geo-redundant backups for PostgreSQL server"
  type        = bool
  default     = true
}

variable "postgresql_storage_auto_grow_enabled" {
  description = "Enable storage auto-grow for PostgreSQL server"
  type        = bool
  default     = true
}

# Network configuration variables
variable "postgresql_public_network_access_enabled" {
  description = "Enable public network access for PostgreSQL server"
  type        = bool
  default     = true
}

variable "allowed_ip_ranges" {
  description = "List of IP ranges allowed to access PostgreSQL server"
  type        = list(string)
  default     = ["0.0.0.0-255.255.255.255"] # Allow all IPs - restrict in production
  
  validation {
    condition = alltrue([
      for ip_range in var.allowed_ip_ranges : can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}-([0-9]{1,3}\\.){3}[0-9]{1,3}$", ip_range))
    ])
    error_message = "Each IP range must be in the format 'x.x.x.x-y.y.y.y'."
  }
}

# Backup configuration variables
variable "backup_vault_redundancy" {
  description = "Storage redundancy for backup vault"
  type        = string
  default     = "GeoRedundant"
  
  validation {
    condition     = contains(["LocallyRedundant", "ZoneRedundant", "GeoRedundant"], var.backup_vault_redundancy)
    error_message = "Backup vault redundancy must be one of: LocallyRedundant, ZoneRedundant, GeoRedundant."
  }
}

variable "backup_policy_retention_days" {
  description = "Backup policy retention period in days"
  type        = number
  default     = 90
  
  validation {
    condition     = var.backup_policy_retention_days >= 7 && var.backup_policy_retention_days <= 9999
    error_message = "Backup policy retention days must be between 7 and 9999."
  }
}

variable "backup_frequency" {
  description = "Backup frequency (Daily, Weekly)"
  type        = string
  default     = "Daily"
  
  validation {
    condition     = contains(["Daily", "Weekly"], var.backup_frequency)
    error_message = "Backup frequency must be either Daily or Weekly."
  }
}

# Storage configuration variables
variable "storage_account_tier" {
  description = "Storage account tier"
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
  default     = "GRS"
  
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_account_replication_type)
    error_message = "Storage account replication type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

variable "storage_account_access_tier" {
  description = "Storage account access tier"
  type        = string
  default     = "Hot"
  
  validation {
    condition     = contains(["Hot", "Cool"], var.storage_account_access_tier)
    error_message = "Storage account access tier must be either Hot or Cool."
  }
}

# Monitoring configuration variables
variable "log_analytics_retention_days" {
  description = "Log Analytics workspace retention period in days"
  type        = number
  default     = 90
  
  validation {
    condition     = var.log_analytics_retention_days >= 30 && var.log_analytics_retention_days <= 730
    error_message = "Log Analytics retention days must be between 30 and 730."
  }
}

variable "log_analytics_sku" {
  description = "Log Analytics workspace SKU"
  type        = string
  default     = "PerGB2018"
  
  validation {
    condition     = contains(["Free", "PerNode", "PerGB2018", "Premium", "Standalone", "Unlimited", "CapacityReservation"], var.log_analytics_sku)
    error_message = "Log Analytics SKU must be one of: Free, PerNode, PerGB2018, Premium, Standalone, Unlimited, CapacityReservation."
  }
}

variable "alert_email_addresses" {
  description = "List of email addresses for disaster recovery alerts"
  type        = list(string)
  default     = ["admin@company.com"]
  
  validation {
    condition = alltrue([
      for email in var.alert_email_addresses : can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", email))
    ])
    error_message = "All email addresses must be valid email format."
  }
}

# Alert configuration variables
variable "connection_failures_threshold" {
  description = "Threshold for connection failures alert"
  type        = number
  default     = 10
  
  validation {
    condition     = var.connection_failures_threshold > 0
    error_message = "Connection failures threshold must be greater than 0."
  }
}

variable "replication_lag_threshold_seconds" {
  description = "Threshold for replication lag alert in seconds"
  type        = number
  default     = 300 # 5 minutes
  
  validation {
    condition     = var.replication_lag_threshold_seconds > 0
    error_message = "Replication lag threshold must be greater than 0 seconds."
  }
}

variable "backup_failures_threshold" {
  description = "Threshold for backup failures alert"
  type        = number
  default     = 0
  
  validation {
    condition     = var.backup_failures_threshold >= 0
    error_message = "Backup failures threshold must be 0 or greater."
  }
}

# Automation configuration variables
variable "enable_automation_account" {
  description = "Enable Azure Automation account for disaster recovery"
  type        = bool
  default     = true
}

variable "automation_account_sku" {
  description = "Azure Automation account SKU"
  type        = string
  default     = "Basic"
  
  validation {
    condition     = contains(["Free", "Basic"], var.automation_account_sku)
    error_message = "Automation account SKU must be either Free or Basic."
  }
}

# Sample data configuration
variable "create_sample_data" {
  description = "Create sample database and test data"
  type        = bool
  default     = true
}

variable "sample_database_name" {
  description = "Name of the sample database"
  type        = string
  default     = "production_db"
  
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]{0,62}$", var.sample_database_name))
    error_message = "Sample database name must start with a letter and contain only letters, numbers, and underscores (max 63 characters)."
  }
}

# Resource tagging variables
variable "tags" {
  description = "A map of tags to assign to resources"
  type        = map(string)
  default = {
    Environment = "production"
    Purpose     = "disaster-recovery"
    ManagedBy   = "terraform"
  }
}

# Feature flags
variable "enable_read_replica" {
  description = "Enable read replica creation in secondary region"
  type        = bool
  default     = true
}

variable "enable_backup_vault" {
  description = "Enable backup vault creation"
  type        = bool
  default     = true
}

variable "enable_monitoring" {
  description = "Enable monitoring and alerting"
  type        = bool
  default     = true
}

variable "enable_automation" {
  description = "Enable automation workflows"
  type        = bool
  default     = true
}