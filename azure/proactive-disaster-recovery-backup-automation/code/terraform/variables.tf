# Variable definitions for Azure disaster recovery infrastructure
# This file defines all configurable parameters for the disaster recovery solution

# Core deployment configuration
variable "environment" {
  description = "Environment name for resource tagging and naming"
  type        = string
  default     = "production"
  
  validation {
    condition     = contains(["dev", "staging", "production"], var.environment)
    error_message = "Environment must be one of: dev, staging, production."
  }
}

variable "project_name" {
  description = "Project name used for resource naming and tagging"
  type        = string
  default     = "dr-orchestration"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.project_name))
    error_message = "Project name must contain only alphanumeric characters and hyphens."
  }
}

# Geographic configuration for multi-region disaster recovery
variable "primary_location" {
  description = "Primary Azure region for disaster recovery infrastructure"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "Central US",
      "North Central US", "South Central US", "West Central US",
      "North Europe", "West Europe", "UK South", "UK West",
      "Southeast Asia", "East Asia", "Australia East", "Australia Southeast"
    ], var.primary_location)
    error_message = "Primary location must be a valid Azure region."
  }
}

variable "secondary_location" {
  description = "Secondary Azure region for cross-region disaster recovery"
  type        = string
  default     = "West US 2"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "Central US",
      "North Central US", "South Central US", "West Central US",
      "North Europe", "West Europe", "UK South", "UK West",
      "Southeast Asia", "East Asia", "Australia East", "Australia Southeast"
    ], var.secondary_location)
    error_message = "Secondary location must be a valid Azure region."
  }
}

# Recovery Services Vault configuration
variable "backup_storage_redundancy" {
  description = "Storage redundancy type for backup data"
  type        = string
  default     = "GeoRedundant"
  
  validation {
    condition     = contains(["LocallyRedundant", "GeoRedundant", "ZoneRedundant"], var.backup_storage_redundancy)
    error_message = "Backup storage redundancy must be LocallyRedundant, GeoRedundant, or ZoneRedundant."
  }
}

variable "enable_cross_region_restore" {
  description = "Enable cross-region restore capability for disaster recovery"
  type        = bool
  default     = true
}

# Backup policy configuration
variable "vm_backup_frequency" {
  description = "Backup frequency for virtual machines"
  type        = string
  default     = "Daily"
  
  validation {
    condition     = contains(["Daily", "Weekly"], var.vm_backup_frequency)
    error_message = "VM backup frequency must be Daily or Weekly."
  }
}

variable "vm_backup_time" {
  description = "Time of day for VM backups (HH:MM format, 24-hour)"
  type        = string
  default     = "02:00"
  
  validation {
    condition     = can(regex("^([01]?[0-9]|2[0-3]):[0-5][0-9]$", var.vm_backup_time))
    error_message = "VM backup time must be in HH:MM format (24-hour)."
  }
}

variable "vm_backup_retention_days" {
  description = "Number of days to retain daily VM backups"
  type        = number
  default     = 30
  
  validation {
    condition     = var.vm_backup_retention_days >= 7 && var.vm_backup_retention_days <= 9999
    error_message = "VM backup retention days must be between 7 and 9999."
  }
}

variable "vm_weekly_retention_weeks" {
  description = "Number of weeks to retain weekly VM backups"
  type        = number
  default     = 12
  
  validation {
    condition     = var.vm_weekly_retention_weeks >= 1 && var.vm_weekly_retention_weeks <= 5163
    error_message = "VM weekly retention weeks must be between 1 and 5163."
  }
}

# Log Analytics workspace configuration
variable "log_analytics_sku" {
  description = "Pricing tier for Log Analytics workspace"
  type        = string
  default     = "PerGB2018"
  
  validation {
    condition     = contains(["Free", "PerNode", "PerGB2018", "Premium"], var.log_analytics_sku)
    error_message = "Log Analytics SKU must be Free, PerNode, PerGB2018, or Premium."
  }
}

variable "log_retention_days" {
  description = "Number of days to retain logs in Log Analytics workspace"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_retention_days >= 7 && var.log_retention_days <= 730
    error_message = "Log retention days must be between 7 and 730."
  }
}

# Monitoring and alerting configuration
variable "alert_evaluation_frequency" {
  description = "How often alert rules are evaluated (in minutes)"
  type        = number
  default     = 5
  
  validation {
    condition     = contains([1, 5, 15, 30, 60], var.alert_evaluation_frequency)
    error_message = "Alert evaluation frequency must be 1, 5, 15, 30, or 60 minutes."
  }
}

variable "alert_window_size" {
  description = "Time window for alert rule evaluation (in minutes)"
  type        = number
  default     = 15
  
  validation {
    condition     = contains([5, 10, 15, 30, 60, 180, 360, 720, 1440], var.alert_window_size)
    error_message = "Alert window size must be 5, 10, 15, 30, 60, 180, 360, 720, or 1440 minutes."
  }
}

# Notification configuration
variable "admin_email" {
  description = "Email address for disaster recovery notifications"
  type        = string
  default     = "admin@company.com"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.admin_email))
    error_message = "Admin email must be a valid email address."
  }
}

variable "admin_phone" {
  description = "Phone number for SMS notifications (E.164 format)"
  type        = string
  default     = "+1234567890"
  
  validation {
    condition     = can(regex("^\\+[1-9]\\d{1,14}$", var.admin_phone))
    error_message = "Admin phone must be in E.164 format (e.g., +1234567890)."
  }
}

variable "teams_webhook_url" {
  description = "Microsoft Teams webhook URL for notifications"
  type        = string
  default     = ""
  sensitive   = true
}

# Storage account configuration for Logic Apps
variable "storage_account_tier" {
  description = "Performance tier for storage account"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be Standard or Premium."
  }
}

variable "storage_replication_type" {
  description = "Replication type for storage account"
  type        = string
  default     = "LRS"
  
  validation {
    condition     = contains(["LRS", "GRS", "ZRS", "GZRS"], var.storage_replication_type)
    error_message = "Storage replication type must be LRS, GRS, ZRS, or GZRS."
  }
}

# Resource tagging
variable "tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default = {
    Purpose     = "disaster-recovery"
    Environment = "production"
    ManagedBy   = "terraform"
    Solution    = "intelligent-disaster-recovery"
  }
}

# Enable/disable optional features
variable "enable_workbooks" {
  description = "Enable Azure Monitor Workbooks for visualization"
  type        = bool
  default     = true
}

variable "enable_logic_apps" {
  description = "Enable Logic Apps for automated recovery orchestration"
  type        = bool
  default     = true
}

variable "enable_advanced_monitoring" {
  description = "Enable advanced monitoring features and custom metrics"
  type        = bool
  default     = true
}