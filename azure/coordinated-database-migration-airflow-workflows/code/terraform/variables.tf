# ===================================================================================
# Terraform Variables: Intelligent Database Migration Orchestration
# Description: Variable definitions for Azure Data Factory with Workflow Orchestration,
#              Database Migration Service, and comprehensive monitoring infrastructure
# Version: 1.0
# ===================================================================================

# ===================================================================================
# CORE INFRASTRUCTURE VARIABLES
# ===================================================================================

variable "resource_group_name" {
  type        = string
  description = "Name of the Azure resource group where all resources will be deployed"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-_\\.\\(\\)]{1,90}$", var.resource_group_name))
    error_message = "Resource group name must be 1-90 characters and can contain alphanumeric characters, periods, underscores, hyphens, and parentheses."
  }
}

variable "location" {
  type        = string
  description = "The Azure region where all resources will be deployed"
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "South Central US", "North Central US", "West Central US",
      "Canada Central", "Canada East", "Brazil South", "UK South", "UK West",
      "West Europe", "North Europe", "France Central", "Germany West Central",
      "Switzerland North", "Norway East", "Sweden Central", "Poland Central",
      "Italy North", "Spain Central", "Israel Central", "UAE North",
      "South Africa North", "Australia East", "Australia Southeast",
      "Central India", "South India", "West India", "Japan East", "Japan West",
      "Korea Central", "Korea South", "Southeast Asia", "East Asia"
    ], var.location)
    error_message = "Location must be a valid Azure region."
  }
}

variable "environment" {
  type        = string
  description = "Environment name for resource tagging and naming (dev, test, prod)"
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "test", "prod"], var.environment)
    error_message = "Environment must be one of: dev, test, prod."
  }
}

variable "project_name" {
  type        = string
  description = "Project name used for resource naming and tagging"
  default     = "db-migration"
  
  validation {
    condition     = can(regex("^[a-z0-9-]{2,20}$", var.project_name))
    error_message = "Project name must be 2-20 characters, lowercase letters, numbers, and hyphens only."
  }
}

variable "tags" {
  type        = map(string)
  description = "A map of tags to apply to all resources"
  default = {
    purpose     = "database-migration"
    recipe      = "intelligent-migration-orchestration"
    costCenter  = "IT"
    project     = "database-modernization"
    owner       = "migration-team"
    managedBy   = "terraform"
  }
}

# ===================================================================================
# AZURE DATA FACTORY VARIABLES
# ===================================================================================

variable "data_factory_name" {
  type        = string
  description = "Name for the Azure Data Factory instance (leave empty for auto-generation)"
  default     = ""
  
  validation {
    condition     = var.data_factory_name == "" || can(regex("^[a-zA-Z0-9-]{3,63}$", var.data_factory_name))
    error_message = "Data Factory name must be 3-63 characters and contain only alphanumeric characters and hyphens."
  }
}

variable "enable_managed_vnet" {
  type        = bool
  description = "Enable managed virtual network for Data Factory for enhanced security"
  default     = true
}

variable "enable_git_integration" {
  type        = bool
  description = "Enable Git repository integration for Data Factory source control"
  default     = false
}

variable "git_configuration" {
  type = object({
    type                = optional(string, "FactoryGitHubConfiguration")
    account_name        = optional(string, "")
    repository_name     = optional(string, "")
    collaboration_branch = optional(string, "main")
    root_folder         = optional(string, "/")
  })
  description = "Git repository configuration for Data Factory (required if git integration is enabled)"
  default = {
    type                = "FactoryGitHubConfiguration"
    account_name        = ""
    repository_name     = ""
    collaboration_branch = "main"
    root_folder         = "/"
  }
}

# ===================================================================================
# DATABASE MIGRATION SERVICE VARIABLES
# ===================================================================================

variable "dms_name" {
  type        = string
  description = "Name for the Database Migration Service instance (leave empty for auto-generation)"
  default     = ""
  
  validation {
    condition     = var.dms_name == "" || can(regex("^[a-zA-Z0-9-]{3,63}$", var.dms_name))
    error_message = "DMS name must be 3-63 characters and contain only alphanumeric characters and hyphens."
  }
}

variable "dms_sku" {
  type        = string
  description = "SKU for the Database Migration Service"
  default     = "Standard_4vCores"
  
  validation {
    condition     = contains(["Standard_1vCore", "Standard_2vCores", "Standard_4vCores"], var.dms_sku)
    error_message = "DMS SKU must be one of: Standard_1vCore, Standard_2vCores, Standard_4vCores."
  }
}

# ===================================================================================
# STORAGE ACCOUNT VARIABLES
# ===================================================================================

variable "storage_account_name" {
  type        = string
  description = "Name for the storage account (leave empty for auto-generation, must be globally unique)"
  default     = ""
  
  validation {
    condition     = var.storage_account_name == "" || can(regex("^[a-z0-9]{3,24}$", var.storage_account_name))
    error_message = "Storage account name must be 3-24 characters, lowercase letters and numbers only."
  }
}

variable "storage_account_tier" {
  type        = string
  description = "Performance tier for the storage account"
  default     = "Standard"
  
  validation {
    condition     = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be either Standard or Premium."
  }
}

variable "storage_replication_type" {
  type        = string
  description = "Replication type for the storage account"
  default     = "LRS"
  
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_replication_type)
    error_message = "Storage replication type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

variable "storage_access_tier" {
  type        = string
  description = "Access tier for the storage account"
  default     = "Hot"
  
  validation {
    condition     = contains(["Hot", "Cool"], var.storage_access_tier)
    error_message = "Storage access tier must be either Hot or Cool."
  }
}

variable "storage_container_names" {
  type        = list(string)
  description = "List of container names to create in the storage account"
  default     = ["airflow-dags", "migration-artifacts", "migration-logs", "configuration"]
  
  validation {
    condition     = length(var.storage_container_names) > 0
    error_message = "At least one storage container name must be provided."
  }
}

# ===================================================================================
# LOG ANALYTICS VARIABLES
# ===================================================================================

variable "log_analytics_workspace_name" {
  type        = string
  description = "Name for the Log Analytics workspace (leave empty for auto-generation)"
  default     = ""
  
  validation {
    condition     = var.log_analytics_workspace_name == "" || can(regex("^[a-zA-Z0-9-]{4,63}$", var.log_analytics_workspace_name))
    error_message = "Log Analytics workspace name must be 4-63 characters and contain only alphanumeric characters and hyphens."
  }
}

variable "log_analytics_sku" {
  type        = string
  description = "SKU for the Log Analytics workspace"
  default     = "PerGB2018"
  
  validation {
    condition     = contains(["Free", "Standalone", "PerNode", "PerGB2018"], var.log_analytics_sku)
    error_message = "Log Analytics SKU must be one of: Free, Standalone, PerNode, PerGB2018."
  }
}

variable "log_analytics_retention_days" {
  type        = number
  description = "Number of days to retain data in Log Analytics workspace"
  default     = 30
  
  validation {
    condition     = var.log_analytics_retention_days >= 30 && var.log_analytics_retention_days <= 730
    error_message = "Log Analytics retention days must be between 30 and 730."
  }
}

variable "log_analytics_daily_quota_gb" {
  type        = number
  description = "Daily quota in GB for Log Analytics workspace (-1 for unlimited)"
  default     = -1
  
  validation {
    condition     = var.log_analytics_daily_quota_gb == -1 || var.log_analytics_daily_quota_gb >= 1
    error_message = "Log Analytics daily quota must be -1 (unlimited) or at least 1 GB."
  }
}

# ===================================================================================
# MONITORING AND ALERTING VARIABLES
# ===================================================================================

variable "enable_monitoring" {
  type        = bool
  description = "Enable comprehensive monitoring and alerting for the migration solution"
  default     = true
}

variable "alert_notification_email" {
  type        = string
  description = "Email address for alert notifications"
  default     = "admin@company.com"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.alert_notification_email))
    error_message = "Alert notification email must be a valid email address."
  }
}

variable "action_group_name" {
  type        = string
  description = "Name for the action group used for alerts (leave empty for auto-generation)"
  default     = ""
  
  validation {
    condition     = var.action_group_name == "" || can(regex("^[a-zA-Z0-9-_]{1,64}$", var.action_group_name))
    error_message = "Action group name must be 1-64 characters and contain only alphanumeric characters, hyphens, and underscores."
  }
}

variable "alert_rules" {
  type = list(object({
    name                = string
    description         = string
    severity            = number
    metric_namespace    = string
    metric_name         = string
    aggregation         = string
    operator            = string
    threshold           = number
    window_size         = string
    evaluation_frequency = string
  }))
  description = "List of metric alert rules to create"
  default = [
    {
      name                = "migration-failure-alert"
      description         = "Alert when database migration errors occur"
      severity            = 1
      metric_namespace    = "Microsoft.DataMigration/services"
      metric_name         = "MigrationErrors"
      aggregation         = "Count"
      operator            = "GreaterThan"
      threshold           = 0
      window_size         = "PT5M"
      evaluation_frequency = "PT1M"
    },
    {
      name                = "long-migration-alert"
      description         = "Alert when migration duration exceeds 1 hour"
      severity            = 2
      metric_namespace    = "Microsoft.DataMigration/services"
      metric_name         = "MigrationDuration"
      aggregation         = "Average"
      operator            = "GreaterThan"
      threshold           = 3600
      window_size         = "PT15M"
      evaluation_frequency = "PT5M"
    },
    {
      name                = "high-cpu-alert"
      description         = "Alert when DMS CPU usage is high"
      severity            = 2
      metric_namespace    = "Microsoft.DataMigration/services"
      metric_name         = "CpuPercent"
      aggregation         = "Average"
      operator            = "GreaterThan"
      threshold           = 80
      window_size         = "PT10M"
      evaluation_frequency = "PT5M"
    }
  ]
}

# ===================================================================================
# NETWORKING VARIABLES
# ===================================================================================

variable "enable_private_endpoints" {
  type        = bool
  description = "Enable private endpoints for enhanced security (requires VNet configuration)"
  default     = false
}

variable "virtual_network_id" {
  type        = string
  description = "Resource ID of the virtual network for private endpoints (required if private endpoints enabled)"
  default     = ""
  
  validation {
    condition = var.enable_private_endpoints == false || (var.enable_private_endpoints == true && var.virtual_network_id != "")
    error_message = "Virtual network ID is required when private endpoints are enabled."
  }
}

variable "private_endpoint_subnet_id" {
  type        = string
  description = "Resource ID of the subnet for private endpoints (required if private endpoints enabled)"
  default     = ""
  
  validation {
    condition = var.enable_private_endpoints == false || (var.enable_private_endpoints == true && var.private_endpoint_subnet_id != "")
    error_message = "Private endpoint subnet ID is required when private endpoints are enabled."
  }
}

variable "dms_subnet_id" {
  type        = string
  description = "Resource ID of the subnet for Database Migration Service (optional for enhanced security)"
  default     = ""
}

# ===================================================================================
# ADVANCED CONFIGURATION VARIABLES
# ===================================================================================

variable "enable_diagnostic_settings" {
  type        = bool
  description = "Enable diagnostic settings for all supported resources"
  default     = true
}

variable "enable_rbac_assignments" {
  type        = bool
  description = "Enable role-based access control assignments for service principals"
  default     = true
}

variable "storage_container_delete_retention_days" {
  type        = number
  description = "Number of days to retain deleted storage containers"
  default     = 7
  
  validation {
    condition     = var.storage_container_delete_retention_days >= 1 && var.storage_container_delete_retention_days <= 365
    error_message = "Storage container delete retention days must be between 1 and 365."
  }
}

variable "enable_storage_versioning" {
  type        = bool
  description = "Enable blob versioning for the storage account"
  default     = false
}

variable "enable_storage_change_feed" {
  type        = bool
  description = "Enable change feed for the storage account"
  default     = false
}