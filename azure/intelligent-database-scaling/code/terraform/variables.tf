# Input Variables
# This file defines all configurable parameters for the autonomous database scaling solution

# Basic Configuration Variables
variable "resource_group_name" {
  description = "Name of the Azure Resource Group to create all resources in"
  type        = string
  default     = null
  
  validation {
    condition     = var.resource_group_name == null || can(regex("^[a-zA-Z0-9-_\\.\\(\\)]{1,90}$", var.resource_group_name))
    error_message = "Resource group name must be 1-90 characters and can contain alphanumeric, hyphens, underscores, periods, and parentheses."
  }
}

variable "location" {
  description = "Azure region where all resources will be deployed"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "North Central US", "South Central US", "West Central US",
      "Canada Central", "Canada East", "Brazil South", "UK South", "UK West",
      "West Europe", "North Europe", "France Central", "Germany West Central",
      "Switzerland North", "Norway East", "Sweden Central",
      "Australia East", "Australia Southeast", "Asia Pacific", "Southeast Asia",
      "East Asia", "Japan East", "Japan West", "Korea Central", "India Central"
    ], var.location)
    error_message = "Location must be a valid Azure region."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod) for resource tagging and naming"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "project_name" {
  description = "Project name for resource naming and tagging"
  type        = string
  default     = "autonomous-scaling"
  
  validation {
    condition     = can(regex("^[a-z0-9-]{2,20}$", var.project_name))
    error_message = "Project name must be 2-20 characters, lowercase letters, numbers, and hyphens only."
  }
}

# SQL Database Configuration Variables
variable "sql_server_admin_username" {
  description = "Administrator username for the SQL Server"
  type        = string
  default     = "sqladmin"
  sensitive   = true
  
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9]{1,127}$", var.sql_server_admin_username))
    error_message = "SQL admin username must start with a letter and be 2-128 characters of letters and numbers."
  }
}

variable "sql_server_admin_password" {
  description = "Administrator password for the SQL Server. Must meet Azure password complexity requirements."
  type        = string
  default     = null
  sensitive   = true
  
  validation {
    condition = var.sql_server_admin_password == null || can(regex("^.{8,128}$", var.sql_server_admin_password))
    error_message = "SQL admin password must be 8-128 characters long."
  }
}

variable "sql_database_name" {
  description = "Name of the SQL Database (Hyperscale)"
  type        = string
  default     = "hyperscale-db"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]{1,128}$", var.sql_database_name))
    error_message = "Database name must be 1-128 characters and contain only letters, numbers, hyphens, and underscores."
  }
}

variable "sql_database_initial_sku" {
  description = "Initial SKU for the Hyperscale database (format: HS_Gen5_X where X is vCore count)"
  type        = string
  default     = "HS_Gen5_2"
  
  validation {
    condition     = can(regex("^HS_Gen5_[0-9]+$", var.sql_database_initial_sku))
    error_message = "SKU must be in format HS_Gen5_X where X is the number of vCores (e.g., HS_Gen5_2, HS_Gen5_4)."
  }
}

variable "sql_database_max_size_gb" {
  description = "Maximum size in GB for the database. For Hyperscale, this is just initial allocation."
  type        = number
  default     = 100
  
  validation {
    condition     = var.sql_database_max_size_gb >= 40 && var.sql_database_max_size_gb <= 102400
    error_message = "Database max size must be between 40 GB and 100 TB (102400 GB)."
  }
}

# Scaling Configuration Variables
variable "cpu_scale_up_threshold" {
  description = "CPU percentage threshold that triggers scale-up action"
  type        = number
  default     = 80
  
  validation {
    condition     = var.cpu_scale_up_threshold >= 50 && var.cpu_scale_up_threshold <= 95
    error_message = "CPU scale-up threshold must be between 50% and 95%."
  }
}

variable "cpu_scale_down_threshold" {
  description = "CPU percentage threshold that triggers scale-down action"
  type        = number
  default     = 30
  
  validation {
    condition     = var.cpu_scale_down_threshold >= 10 && var.cpu_scale_down_threshold <= 50
    error_message = "CPU scale-down threshold must be between 10% and 50%."
  }
}

variable "scale_up_evaluation_window_minutes" {
  description = "Time window in minutes for scale-up evaluation"
  type        = number
  default     = 5
  
  validation {
    condition     = contains([1, 5, 15, 30, 60, 360, 720, 1440], var.scale_up_evaluation_window_minutes)
    error_message = "Evaluation window must be one of: 1, 5, 15, 30, 60, 360, 720, 1440 minutes."
  }
}

variable "scale_down_evaluation_window_minutes" {
  description = "Time window in minutes for scale-down evaluation (longer to prevent flapping)"
  type        = number
  default     = 15
  
  validation {
    condition     = contains([1, 5, 15, 30, 60, 360, 720, 1440], var.scale_down_evaluation_window_minutes)
    error_message = "Evaluation window must be one of: 1, 5, 15, 30, 60, 360, 720, 1440 minutes."
  }
}

variable "max_vcores" {
  description = "Maximum number of vCores the database can scale to"
  type        = number
  default     = 40
  
  validation {
    condition     = var.max_vcores >= 2 && var.max_vcores <= 128
    error_message = "Maximum vCores must be between 2 and 128."
  }
}

variable "min_vcores" {
  description = "Minimum number of vCores the database should maintain"
  type        = number
  default     = 2
  
  validation {
    condition     = var.min_vcores >= 2 && var.min_vcores <= 128
    error_message = "Minimum vCores must be between 2 and 128."
  }
}

variable "scaling_step_size" {
  description = "Number of vCores to add/remove during each scaling operation"
  type        = number
  default     = 2
  
  validation {
    condition     = var.scaling_step_size >= 1 && var.scaling_step_size <= 8
    error_message = "Scaling step size must be between 1 and 8 vCores."
  }
}

# Monitoring and Alerting Configuration
variable "log_analytics_retention_days" {
  description = "Number of days to retain logs in Log Analytics workspace"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_analytics_retention_days >= 30 && var.log_analytics_retention_days <= 730
    error_message = "Log retention must be between 30 and 730 days."
  }
}

variable "enable_detailed_monitoring" {
  description = "Enable detailed monitoring and custom metrics collection"
  type        = bool
  default     = true
}

variable "alert_email_recipients" {
  description = "List of email addresses to receive scaling alerts"
  type        = list(string)
  default     = []
  
  validation {
    condition = alltrue([
      for email in var.alert_email_recipients : can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", email))
    ])
    error_message = "All email addresses must be valid email format."
  }
}

# Security Configuration Variables
variable "enable_key_vault_rbac" {
  description = "Enable RBAC authorization for Key Vault instead of access policies"
  type        = bool
  default     = true
}

variable "key_vault_sku" {
  description = "SKU for the Key Vault (standard or premium)"
  type        = string
  default     = "standard"
  
  validation {
    condition     = contains(["standard", "premium"], var.key_vault_sku)
    error_message = "Key Vault SKU must be either 'standard' or 'premium'."
  }
}

variable "sql_server_public_access_enabled" {
  description = "Allow public network access to SQL Server"
  type        = bool
  default     = true
}

variable "allowed_ip_ranges" {
  description = "List of IP ranges allowed to access the SQL Server"
  type = list(object({
    name     = string
    start_ip = string
    end_ip   = string
  }))
  default = []
}

# Logic Apps Configuration
variable "logic_app_consumption_plan" {
  description = "Use Consumption plan for Logic Apps (true) or Standard plan (false)"
  type        = bool
  default     = true
}

variable "workflow_trigger_frequency" {
  description = "How often the Logic App should check for scaling opportunities (in minutes)"
  type        = number
  default     = 5
  
  validation {
    condition     = var.workflow_trigger_frequency >= 1 && var.workflow_trigger_frequency <= 60
    error_message = "Workflow trigger frequency must be between 1 and 60 minutes."
  }
}

# Cost Management Variables
variable "enable_cost_alerts" {
  description = "Enable cost monitoring and alerts for the solution"
  type        = bool
  default     = true
}

variable "monthly_budget_limit" {
  description = "Monthly budget limit in USD for cost alerts"
  type        = number
  default     = 500
  
  validation {
    condition     = var.monthly_budget_limit >= 50 && var.monthly_budget_limit <= 10000
    error_message = "Monthly budget limit must be between $50 and $10,000."
  }
}

# Common Tags
variable "common_tags" {
  description = "Common tags to be applied to all resources"
  type        = map(string)
  default = {
    Solution    = "Autonomous Database Scaling"
    Environment = "Development"
    CreatedBy   = "Terraform"
    Recipe      = "implementing-autonomous-database-scaling-with-azure-sql-database-hyperscale-and-azure-logic-apps"
  }
}

# Advanced Configuration Variables
variable "enable_zone_redundancy" {
  description = "Enable zone redundancy for SQL Database (requires Premium tier regions)"
  type        = bool
  default     = false
}

variable "backup_retention_days" {
  description = "Number of days to retain automated backups"
  type        = number
  default     = 7
  
  validation {
    condition     = var.backup_retention_days >= 1 && var.backup_retention_days <= 35
    error_message = "Backup retention must be between 1 and 35 days."
  }
}

variable "enable_threat_detection" {
  description = "Enable Advanced Threat Protection for SQL Database"
  type        = bool
  default     = true
}

variable "storage_account_replication_type" {
  description = "Replication type for storage accounts used in the solution"
  type        = string
  default     = "LRS"
  
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_account_replication_type)
    error_message = "Storage replication type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}