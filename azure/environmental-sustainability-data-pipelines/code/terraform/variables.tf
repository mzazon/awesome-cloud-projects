# Core Variables
variable "location" {
  description = "Azure region for deploying resources"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "North Central US", "South Central US", "West Central US",
      "Canada Central", "Canada East", "Brazil South", "UK South", "UK West",
      "West Europe", "North Europe", "France Central", "Germany West Central",
      "Norway East", "Switzerland North", "UAE North", "South Africa North",
      "Australia East", "Australia Southeast", "Central India", "South India",
      "Japan East", "Japan West", "Korea Central", "Southeast Asia", "East Asia"
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
  default     = "env-data-pipeline"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

# Data Factory Variables
variable "data_factory_name" {
  description = "Name of the Azure Data Factory instance"
  type        = string
  default     = null
}

variable "data_factory_managed_vnet_enabled" {
  description = "Enable managed virtual network for Data Factory"
  type        = bool
  default     = true
}

variable "data_factory_public_network_enabled" {
  description = "Enable public network access for Data Factory"
  type        = bool
  default     = true
}

# Storage Variables
variable "storage_account_name" {
  description = "Name of the storage account (must be globally unique)"
  type        = string
  default     = null
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

variable "storage_replication_type" {
  description = "Storage account replication type"
  type        = string
  default     = "LRS"
  
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_replication_type)
    error_message = "Storage replication type must be LRS, GRS, RAGRS, ZRS, GZRS, or RAGZRS."
  }
}

variable "enable_data_lake" {
  description = "Enable Data Lake Gen2 features on storage account"
  type        = bool
  default     = true
}

# Function App Variables
variable "function_app_name" {
  description = "Name of the Azure Function App"
  type        = string
  default     = null
}

variable "function_app_service_plan_sku" {
  description = "SKU for the Function App Service Plan"
  type        = string
  default     = "Y1"
  
  validation {
    condition     = contains(["Y1", "EP1", "EP2", "EP3", "P1v2", "P2v2", "P3v2"], var.function_app_service_plan_sku)
    error_message = "Function App Service Plan SKU must be a valid consumption or premium tier."
  }
}

variable "function_app_runtime" {
  description = "Runtime for the Function App"
  type        = string
  default     = "python"
  
  validation {
    condition     = contains(["python", "node", "dotnet", "java"], var.function_app_runtime)
    error_message = "Function App runtime must be python, node, dotnet, or java."
  }
}

variable "function_app_runtime_version" {
  description = "Runtime version for the Function App"
  type        = string
  default     = "3.9"
}

# Log Analytics Variables
variable "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  type        = string
  default     = null
}

variable "log_analytics_retention_days" {
  description = "Number of days to retain logs in Log Analytics"
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
    condition     = contains(["Free", "PerNode", "PerGB2018", "Standalone", "Standard", "Premium"], var.log_analytics_sku)
    error_message = "Log Analytics SKU must be a valid tier."
  }
}

# Application Insights Variables
variable "application_insights_name" {
  description = "Name of the Application Insights instance"
  type        = string
  default     = null
}

variable "application_insights_type" {
  description = "Application type for Application Insights"
  type        = string
  default     = "web"
  
  validation {
    condition     = contains(["web", "other"], var.application_insights_type)
    error_message = "Application Insights type must be web or other."
  }
}

# Key Vault Variables
variable "key_vault_name" {
  description = "Name of the Key Vault"
  type        = string
  default     = null
}

variable "key_vault_sku" {
  description = "SKU for Key Vault"
  type        = string
  default     = "standard"
  
  validation {
    condition     = contains(["standard", "premium"], var.key_vault_sku)
    error_message = "Key Vault SKU must be standard or premium."
  }
}

variable "key_vault_enabled_for_disk_encryption" {
  description = "Enable Key Vault for disk encryption"
  type        = bool
  default     = true
}

variable "key_vault_enabled_for_deployment" {
  description = "Enable Key Vault for deployment"
  type        = bool
  default     = true
}

variable "key_vault_enabled_for_template_deployment" {
  description = "Enable Key Vault for template deployment"
  type        = bool
  default     = true
}

variable "key_vault_soft_delete_retention_days" {
  description = "Number of days to retain soft-deleted Key Vault items"
  type        = number
  default     = 90
  
  validation {
    condition     = var.key_vault_soft_delete_retention_days >= 7 && var.key_vault_soft_delete_retention_days <= 90
    error_message = "Key Vault soft delete retention days must be between 7 and 90."
  }
}

# Monitoring Variables
variable "enable_monitoring" {
  description = "Enable comprehensive monitoring and alerting"
  type        = bool
  default     = true
}

variable "alert_email_address" {
  description = "Email address for alert notifications"
  type        = string
  default     = "admin@company.com"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.alert_email_address))
    error_message = "Alert email address must be a valid email format."
  }
}

variable "enable_diagnostic_settings" {
  description = "Enable diagnostic settings for all resources"
  type        = bool
  default     = true
}

# Pipeline Configuration Variables
variable "pipeline_schedule_frequency" {
  description = "Frequency for pipeline schedule (Day, Hour, Week, Month)"
  type        = string
  default     = "Day"
  
  validation {
    condition     = contains(["Day", "Hour", "Week", "Month"], var.pipeline_schedule_frequency)
    error_message = "Pipeline schedule frequency must be Day, Hour, Week, or Month."
  }
}

variable "pipeline_schedule_interval" {
  description = "Interval for pipeline schedule"
  type        = number
  default     = 1
  
  validation {
    condition     = var.pipeline_schedule_interval >= 1 && var.pipeline_schedule_interval <= 100
    error_message = "Pipeline schedule interval must be between 1 and 100."
  }
}

variable "pipeline_schedule_start_time" {
  description = "Start time for pipeline schedule (format: HH:MM)"
  type        = string
  default     = "06:00"
  
  validation {
    condition     = can(regex("^([0-1]?[0-9]|2[0-3]):[0-5][0-9]$", var.pipeline_schedule_start_time))
    error_message = "Pipeline schedule start time must be in HH:MM format."
  }
}

# Security Variables
variable "enable_private_endpoints" {
  description = "Enable private endpoints for supported services"
  type        = bool
  default     = false
}

variable "allowed_ip_ranges" {
  description = "List of IP ranges allowed to access resources"
  type        = list(string)
  default     = []
}

variable "enable_network_security_groups" {
  description = "Enable Network Security Groups for enhanced security"
  type        = bool
  default     = true
}

# Tagging Variables
variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Purpose     = "Environmental Data Pipeline"
    Environment = "Development"
    Project     = "Sustainability Monitoring"
    Owner       = "Data Engineering Team"
  }
}

variable "additional_tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}

# Cost Management Variables
variable "enable_cost_alerts" {
  description = "Enable cost management alerts"
  type        = bool
  default     = true
}

variable "monthly_budget_amount" {
  description = "Monthly budget amount for cost alerts (in USD)"
  type        = number
  default     = 500
  
  validation {
    condition     = var.monthly_budget_amount > 0
    error_message = "Monthly budget amount must be greater than 0."
  }
}

# Data Retention Variables
variable "data_retention_days" {
  description = "Number of days to retain environmental data"
  type        = number
  default     = 365
  
  validation {
    condition     = var.data_retention_days >= 30 && var.data_retention_days <= 2555
    error_message = "Data retention days must be between 30 and 2555."
  }
}

# Backup Variables
variable "enable_backup" {
  description = "Enable backup for critical resources"
  type        = bool
  default     = true
}

variable "backup_retention_days" {
  description = "Number of days to retain backups"
  type        = number
  default     = 30
  
  validation {
    condition     = var.backup_retention_days >= 7 && var.backup_retention_days <= 365
    error_message = "Backup retention days must be between 7 and 365."
  }
}