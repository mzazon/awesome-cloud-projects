# Variables for Azure Real-Time Data Validation Workflow
# This file defines all configurable variables for the infrastructure deployment

# ============================================================================
# Basic Configuration Variables
# ============================================================================

variable "project_name" {
  description = "Name of the project, used for resource naming"
  type        = string
  default     = "data-validation"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{2,20}$", var.project_name))
    error_message = "Project name must be 2-20 characters long and contain only letters, numbers, and hyphens."
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

variable "location" {
  description = "Azure region for resource deployment"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "North Central US", "South Central US",
      "West Central US", "Canada Central", "Canada East",
      "UK South", "UK West", "West Europe", "North Europe",
      "Germany West Central", "Switzerland North", "Norway East",
      "France Central", "Italy North", "Poland Central",
      "Australia East", "Australia Southeast", "Japan East",
      "Japan West", "Korea Central", "Asia Pacific",
      "Southeast Asia", "Central India", "South India",
      "UAE North", "South Africa North", "Brazil South"
    ], var.location)
    error_message = "Location must be a valid Azure region."
  }
}

# ============================================================================
# Resource Tagging Configuration
# ============================================================================

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Project     = "DataValidation"
    Environment = "Development"
    Owner       = "DataTeam"
    CostCenter  = "Engineering"
    Purpose     = "RealTimeValidation"
  }
}

# ============================================================================
# Storage Account Configuration
# ============================================================================

variable "storage_account_tier" {
  description = "Storage account performance tier"
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
  default     = "LRS"
  
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

variable "table_names" {
  description = "List of table names to create in the storage account"
  type        = list(string)
  default     = ["CustomerOrders", "ValidationRules"]
  
  validation {
    condition     = length(var.table_names) > 0
    error_message = "At least one table name must be specified."
  }
}

# ============================================================================
# Event Grid Configuration
# ============================================================================

variable "event_grid_topic_name" {
  description = "Name of the Event Grid topic"
  type        = string
  default     = "data-validation-events"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{3,50}$", var.event_grid_topic_name))
    error_message = "Event Grid topic name must be 3-50 characters long and contain only letters, numbers, and hyphens."
  }
}

variable "enable_event_grid_local_auth" {
  description = "Enable local authentication for Event Grid topic"
  type        = bool
  default     = true
}

# ============================================================================
# Function App Configuration
# ============================================================================

variable "function_app_name" {
  description = "Name of the Function App"
  type        = string
  default     = "validation-functions"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{2,60}$", var.function_app_name))
    error_message = "Function App name must be 2-60 characters long and contain only letters, numbers, and hyphens."
  }
}

variable "function_app_runtime" {
  description = "Runtime for the Function App"
  type        = string
  default     = "python"
  
  validation {
    condition     = contains(["dotnet", "node", "python", "java", "powershell"], var.function_app_runtime)
    error_message = "Function App runtime must be one of: dotnet, node, python, java, powershell."
  }
}

variable "function_app_runtime_version" {
  description = "Runtime version for the Function App"
  type        = string
  default     = "3.11"
}

variable "function_app_sku_name" {
  description = "SKU name for the Function App service plan"
  type        = string
  default     = "Y1"
  
  validation {
    condition     = contains(["Y1", "EP1", "EP2", "EP3", "P1", "P2", "P3"], var.function_app_sku_name)
    error_message = "Function App SKU must be one of: Y1 (Consumption), EP1-EP3 (Elastic Premium), P1-P3 (Premium)."
  }
}

variable "function_timeout" {
  description = "Function execution timeout in minutes"
  type        = number
  default     = 5
  
  validation {
    condition     = var.function_timeout >= 1 && var.function_timeout <= 10
    error_message = "Function timeout must be between 1 and 10 minutes."
  }
}

# ============================================================================
# Logic App Configuration
# ============================================================================

variable "logic_app_name" {
  description = "Name of the Logic App"
  type        = string
  default     = "validation-workflow"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{2,80}$", var.logic_app_name))
    error_message = "Logic App name must be 2-80 characters long and contain only letters, numbers, and hyphens."
  }
}

variable "logic_app_sku_name" {
  description = "SKU name for the Logic App"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Standard", "Premium"], var.logic_app_sku_name)
    error_message = "Logic App SKU must be either Standard or Premium."
  }
}

# ============================================================================
# Monitoring Configuration
# ============================================================================

variable "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  type        = string
  default     = "validation-monitoring"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{4,63}$", var.log_analytics_workspace_name))
    error_message = "Log Analytics workspace name must be 4-63 characters long and contain only letters, numbers, and hyphens."
  }
}

variable "log_analytics_retention_in_days" {
  description = "Log retention period in days"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_analytics_retention_in_days >= 30 && var.log_analytics_retention_in_days <= 730
    error_message = "Log retention must be between 30 and 730 days."
  }
}

variable "application_insights_name" {
  description = "Name of the Application Insights instance"
  type        = string
  default     = "validation-insights"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{1,260}$", var.application_insights_name))
    error_message = "Application Insights name must be 1-260 characters long and contain only letters, numbers, and hyphens."
  }
}

variable "application_insights_type" {
  description = "Application type for Application Insights"
  type        = string
  default     = "web"
  
  validation {
    condition     = contains(["web", "other"], var.application_insights_type)
    error_message = "Application Insights type must be either 'web' or 'other'."
  }
}

# ============================================================================
# Security Configuration
# ============================================================================

variable "enable_https_only" {
  description = "Enable HTTPS only for Function App"
  type        = bool
  default     = true
}

variable "enable_storage_encryption" {
  description = "Enable encryption for storage account"
  type        = bool
  default     = true
}

variable "minimum_tls_version" {
  description = "Minimum TLS version for services"
  type        = string
  default     = "1.2"
  
  validation {
    condition     = contains(["1.0", "1.1", "1.2"], var.minimum_tls_version)
    error_message = "Minimum TLS version must be one of: 1.0, 1.1, 1.2."
  }
}

# ============================================================================
# Notification Configuration
# ============================================================================

variable "notification_email" {
  description = "Email address for notifications"
  type        = string
  default     = "admin@company.com"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address."
  }
}

variable "high_value_order_threshold" {
  description = "Threshold amount for high-value order notifications"
  type        = number
  default     = 1000
  
  validation {
    condition     = var.high_value_order_threshold > 0
    error_message = "High-value order threshold must be greater than 0."
  }
}

# ============================================================================
# Validation Rules Configuration
# ============================================================================

variable "validation_rules" {
  description = "List of validation rules to configure"
  type = list(object({
    name        = string
    rule        = string
    description = string
  }))
  default = [
    {
      name        = "MinAmount"
      rule        = "amount >= 1"
      description = "Minimum order amount validation"
    },
    {
      name        = "MaxAmount"
      rule        = "amount <= 10000"
      description = "Maximum order amount validation"
    },
    {
      name        = "EmailFormat"
      rule        = "email contains @"
      description = "Email format validation"
    }
  ]
}

# ============================================================================
# Advanced Configuration
# ============================================================================

variable "enable_advanced_monitoring" {
  description = "Enable advanced monitoring features"
  type        = bool
  default     = true
}

variable "enable_auto_scaling" {
  description = "Enable auto-scaling for Function App"
  type        = bool
  default     = true
}

variable "max_function_instances" {
  description = "Maximum number of function instances"
  type        = number
  default     = 200
  
  validation {
    condition     = var.max_function_instances >= 1 && var.max_function_instances <= 1000
    error_message = "Maximum function instances must be between 1 and 1000."
  }
}

variable "enable_backup" {
  description = "Enable backup for critical resources"
  type        = bool
  default     = false
}

variable "backup_retention_days" {
  description = "Backup retention period in days"
  type        = number
  default     = 7
  
  validation {
    condition     = var.backup_retention_days >= 1 && var.backup_retention_days <= 365
    error_message = "Backup retention must be between 1 and 365 days."
  }
}