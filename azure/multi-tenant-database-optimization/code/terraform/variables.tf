# Variables for Azure Multi-Tenant Database Architecture
# This file defines all input variables for the Terraform configuration

# Environment and Resource Naming Variables
variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "prod"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "multitenant-saas"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "location" {
  description = "Azure region for all resources"
  type        = string
  default     = "East US"
  
  validation {
    condition     = contains(["East US", "West US 2", "West Europe", "North Europe", "Southeast Asia"], var.location)
    error_message = "Location must be a supported Azure region."
  }
}

# SQL Server Configuration Variables
variable "sql_admin_username" {
  description = "Administrator username for SQL Server"
  type        = string
  default     = "sqladmin"
  
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]*$", var.sql_admin_username))
    error_message = "SQL admin username must start with a letter and contain only letters, numbers, and underscores."
  }
}

variable "sql_admin_password" {
  description = "Administrator password for SQL Server (leave empty to auto-generate)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "minimum_tls_version" {
  description = "Minimum TLS version for SQL Server"
  type        = string
  default     = "1.2"
  
  validation {
    condition     = contains(["1.0", "1.1", "1.2"], var.minimum_tls_version)
    error_message = "Minimum TLS version must be 1.0, 1.1, or 1.2."
  }
}

# Elastic Pool Configuration Variables
variable "elastic_pool_edition" {
  description = "Edition of the elastic pool (Basic, Standard, Premium)"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.elastic_pool_edition)
    error_message = "Elastic pool edition must be Basic, Standard, or Premium."
  }
}

variable "elastic_pool_dtu" {
  description = "DTU capacity for the elastic pool"
  type        = number
  default     = 200
  
  validation {
    condition     = var.elastic_pool_dtu >= 50 && var.elastic_pool_dtu <= 4000
    error_message = "Elastic pool DTU must be between 50 and 4000."
  }
}

variable "elastic_pool_storage_mb" {
  description = "Storage capacity for the elastic pool in MB"
  type        = number
  default     = 204800
  
  validation {
    condition     = var.elastic_pool_storage_mb >= 51200 && var.elastic_pool_storage_mb <= 4194304
    error_message = "Elastic pool storage must be between 51200 MB (50 GB) and 4194304 MB (4 TB)."
  }
}

variable "database_dtu_min" {
  description = "Minimum DTU allocation per database"
  type        = number
  default     = 0
  
  validation {
    condition     = var.database_dtu_min >= 0 && var.database_dtu_min <= 100
    error_message = "Database minimum DTU must be between 0 and 100."
  }
}

variable "database_dtu_max" {
  description = "Maximum DTU allocation per database"
  type        = number
  default     = 50
  
  validation {
    condition     = var.database_dtu_max >= 5 && var.database_dtu_max <= 200
    error_message = "Database maximum DTU must be between 5 and 200."
  }
}

# Tenant Database Configuration Variables
variable "tenant_count" {
  description = "Number of tenant databases to create"
  type        = number
  default     = 4
  
  validation {
    condition     = var.tenant_count >= 1 && var.tenant_count <= 20
    error_message = "Tenant count must be between 1 and 20."
  }
}

variable "tenant_database_collation" {
  description = "Collation for tenant databases"
  type        = string
  default     = "SQL_Latin1_General_CP1_CI_AS"
}

# Backup Configuration Variables
variable "backup_storage_redundancy" {
  description = "Backup storage redundancy (LocallyRedundant, GeoRedundant, ZoneRedundant)"
  type        = string
  default     = "GeoRedundant"
  
  validation {
    condition     = contains(["LocallyRedundant", "GeoRedundant", "ZoneRedundant"], var.backup_storage_redundancy)
    error_message = "Backup storage redundancy must be LocallyRedundant, GeoRedundant, or ZoneRedundant."
  }
}

variable "backup_retention_days" {
  description = "Backup retention period in days"
  type        = number
  default     = 30
  
  validation {
    condition     = var.backup_retention_days >= 7 && var.backup_retention_days <= 35
    error_message = "Backup retention days must be between 7 and 35."
  }
}

# Cost Management Configuration Variables
variable "monthly_budget_amount" {
  description = "Monthly budget amount in USD for cost management"
  type        = number
  default     = 500
  
  validation {
    condition     = var.monthly_budget_amount >= 100 && var.monthly_budget_amount <= 10000
    error_message = "Monthly budget amount must be between 100 and 10000 USD."
  }
}

variable "budget_alert_threshold" {
  description = "Budget alert threshold percentage (0-100)"
  type        = number
  default     = 80
  
  validation {
    condition     = var.budget_alert_threshold >= 50 && var.budget_alert_threshold <= 100
    error_message = "Budget alert threshold must be between 50 and 100 percent."
  }
}

# Monitoring Configuration Variables
variable "log_retention_days" {
  description = "Log retention period in days for monitoring"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_retention_days >= 7 && var.log_retention_days <= 730
    error_message = "Log retention days must be between 7 and 730."
  }
}

variable "enable_automatic_tuning" {
  description = "Enable automatic tuning for SQL databases"
  type        = bool
  default     = true
}

variable "enable_query_store" {
  description = "Enable Query Store for performance monitoring"
  type        = bool
  default     = true
}

# Network Configuration Variables
variable "allow_azure_services" {
  description = "Allow Azure services to access SQL Server"
  type        = bool
  default     = true
}

variable "allowed_ip_ranges" {
  description = "List of allowed IP ranges for SQL Server access"
  type = list(object({
    name     = string
    start_ip = string
    end_ip   = string
  }))
  default = []
}

# Tagging Variables
variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Purpose        = "multi-tenant-saas"
    CostCenter     = "database-operations"
    ManagedBy      = "terraform"
    Architecture   = "elastic-pools"
  }
}

variable "additional_tags" {
  description = "Additional tags to merge with default tags"
  type        = map(string)
  default     = {}
}