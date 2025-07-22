# Variables for Enterprise ETL Orchestration Infrastructure

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = "rg-etl-orchestration"
}

variable "location" {
  description = "Azure region for resource deployment"
  type        = string
  default     = "East US"
  
  validation {
    condition = can(regex("^[A-Za-z0-9\\s-]+$", var.location))
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
  description = "Name of the project for resource naming"
  type        = string
  default     = "etl-orchestration"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

# Data Factory Variables
variable "data_factory_name" {
  description = "Name of the Azure Data Factory (leave empty for auto-generation)"
  type        = string
  default     = ""
}

variable "data_factory_managed_identity_enabled" {
  description = "Enable system-assigned managed identity for Data Factory"
  type        = bool
  default     = true
}

# MySQL Database Variables
variable "mysql_server_name" {
  description = "Name of the MySQL Flexible Server (leave empty for auto-generation)"
  type        = string
  default     = ""
}

variable "mysql_admin_username" {
  description = "Administrator username for MySQL server"
  type        = string
  default     = "mysqladmin"
  
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]*$", var.mysql_admin_username))
    error_message = "MySQL admin username must start with a letter and contain only letters, numbers, and underscores."
  }
}

variable "mysql_admin_password" {
  description = "Administrator password for MySQL server"
  type        = string
  sensitive   = true
  
  validation {
    condition     = length(var.mysql_admin_password) >= 8
    error_message = "MySQL admin password must be at least 8 characters long."
  }
}

variable "mysql_version" {
  description = "MySQL server version"
  type        = string
  default     = "8.0.21"
  
  validation {
    condition     = contains(["5.7", "8.0.21"], var.mysql_version)
    error_message = "MySQL version must be either 5.7 or 8.0.21."
  }
}

variable "mysql_sku_name" {
  description = "SKU name for MySQL Flexible Server"
  type        = string
  default     = "Standard_D2ds_v4"
}

variable "mysql_storage_size_gb" {
  description = "Storage size in GB for MySQL server"
  type        = number
  default     = 128
  
  validation {
    condition     = var.mysql_storage_size_gb >= 20 && var.mysql_storage_size_gb <= 16384
    error_message = "MySQL storage size must be between 20 and 16384 GB."
  }
}

variable "mysql_backup_retention_days" {
  description = "Backup retention period in days"
  type        = number
  default     = 7
  
  validation {
    condition     = var.mysql_backup_retention_days >= 1 && var.mysql_backup_retention_days <= 35
    error_message = "Backup retention days must be between 1 and 35."
  }
}

variable "mysql_high_availability_enabled" {
  description = "Enable high availability for MySQL server"
  type        = bool
  default     = true
}

variable "mysql_zone" {
  description = "Availability zone for MySQL server"
  type        = string
  default     = "1"
}

variable "mysql_standby_zone" {
  description = "Standby availability zone for MySQL server (when HA is enabled)"
  type        = string
  default     = "2"
}

# Key Vault Variables
variable "key_vault_name" {
  description = "Name of the Key Vault (leave empty for auto-generation)"
  type        = string
  default     = ""
}

variable "key_vault_sku" {
  description = "SKU for Key Vault"
  type        = string
  default     = "standard"
  
  validation {
    condition     = contains(["standard", "premium"], var.key_vault_sku)
    error_message = "Key Vault SKU must be either 'standard' or 'premium'."
  }
}

variable "key_vault_soft_delete_retention_days" {
  description = "Soft delete retention period in days"
  type        = number
  default     = 7
  
  validation {
    condition     = var.key_vault_soft_delete_retention_days >= 7 && var.key_vault_soft_delete_retention_days <= 90
    error_message = "Key Vault soft delete retention days must be between 7 and 90."
  }
}

# Log Analytics Variables
variable "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace (leave empty for auto-generation)"
  type        = string
  default     = ""
}

variable "log_analytics_sku" {
  description = "SKU for Log Analytics workspace"
  type        = string
  default     = "PerGB2018"
  
  validation {
    condition     = contains(["Free", "PerNode", "PerGB2018", "Standalone"], var.log_analytics_sku)
    error_message = "Log Analytics SKU must be one of: Free, PerNode, PerGB2018, Standalone."
  }
}

variable "log_analytics_retention_days" {
  description = "Log retention period in days"
  type        = number
  default     = 90
  
  validation {
    condition     = var.log_analytics_retention_days >= 30 && var.log_analytics_retention_days <= 730
    error_message = "Log Analytics retention days must be between 30 and 730."
  }
}

# Source Database Connection Variables
variable "source_mysql_connection_string" {
  description = "Connection string for source MySQL database"
  type        = string
  default     = "server=your-onprem-mysql.domain.com;port=3306;database=source_db;uid=etl_user;pwd=SecurePassword123!"
  sensitive   = true
}

variable "target_database_name" {
  description = "Name of the target database to create"
  type        = string
  default     = "consolidated_data"
}

# Monitoring and Alerting Variables
variable "enable_diagnostic_settings" {
  description = "Enable diagnostic settings for monitoring"
  type        = bool
  default     = true
}

variable "enable_pipeline_failure_alert" {
  description = "Enable alert for pipeline failures"
  type        = bool
  default     = true
}

variable "alert_email_addresses" {
  description = "Email addresses for alert notifications"
  type        = list(string)
  default     = []
}

# Tagging Variables
variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Purpose     = "ETL Orchestration"
    Environment = "Demo"
    Project     = "Enterprise Data Integration"
    CreatedBy   = "Terraform"
  }
}

# Network Security Variables
variable "allowed_ip_ranges" {
  description = "List of IP ranges allowed to access MySQL server"
  type        = list(string)
  default     = ["0.0.0.0/0"] # Note: Restrict this in production
}

variable "enable_ssl_enforcement" {
  description = "Enable SSL enforcement for MySQL server"
  type        = bool
  default     = true
}

# Integration Runtime Variables
variable "self_hosted_ir_name" {
  description = "Name of the self-hosted integration runtime"
  type        = string
  default     = "SelfHostedIR"
}