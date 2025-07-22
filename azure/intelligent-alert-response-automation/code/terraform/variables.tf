# Variables for Intelligent Alert Response System with Azure Monitor Workbooks and Azure Functions
# These variables allow customization of the infrastructure deployment for different environments
# and organizational requirements while maintaining best practices and security standards.

variable "location" {
  description = "The Azure region where resources will be deployed"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3", 
      "Central US", "North Central US", "South Central US", "West Central US",
      "Canada Central", "Canada East", "Brazil South", "UK South", "UK West",
      "West Europe", "North Europe", "France Central", "Germany West Central",
      "Switzerland North", "Norway East", "Sweden Central", "UAE North",
      "South Africa North", "Australia East", "Australia Southeast", 
      "Southeast Asia", "East Asia", "Japan East", "Japan West", 
      "Korea Central", "India Central", "Central India", "South India"
    ], var.location)
    error_message = "Location must be a valid Azure region."
  }
}

variable "environment" {
  description = "Environment name for resource tagging and naming (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.environment))
    error_message = "Environment must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "resource_group_name" {
  description = "Base name for the resource group (suffix will be added automatically)"
  type        = string
  default     = "rg-intelligent-alerts"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-_().]{1,80}$", var.resource_group_name))
    error_message = "Resource group name must be 1-80 characters and contain only letters, numbers, hyphens, underscores, parentheses, and periods."
  }
}

variable "storage_account_name" {
  description = "Base name for the storage account (must be globally unique, suffix will be added)"
  type        = string
  default     = "stintelligent"
  
  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.storage_account_name))
    error_message = "Storage account name must be 3-24 characters long and contain only lowercase letters and numbers."
  }
}

variable "function_app_name" {
  description = "Base name for the Azure Function App (suffix will be added automatically)"
  type        = string
  default     = "func-alert-response"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{1,40}$", var.function_app_name))
    error_message = "Function app name must be 1-40 characters and contain only letters, numbers, and hyphens."
  }
}

variable "event_grid_topic_name" {
  description = "Base name for the Event Grid Topic (suffix will be added automatically)"
  type        = string
  default     = "eg-alerts"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{3,50}$", var.event_grid_topic_name))
    error_message = "Event Grid topic name must be 3-50 characters and contain only letters, numbers, and hyphens."
  }
}

variable "logic_app_name" {
  description = "Base name for the Logic App (suffix will be added automatically)"
  type        = string
  default     = "logic-notifications"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{1,43}$", var.logic_app_name))
    error_message = "Logic app name must be 1-43 characters and contain only letters, numbers, and hyphens."
  }
}

variable "cosmos_db_account_name" {
  description = "Base name for the Cosmos DB account (suffix will be added automatically)"
  type        = string
  default     = "cosmos-alertstate"
  
  validation {
    condition     = can(regex("^[a-z0-9-]{3,44}$", var.cosmos_db_account_name))
    error_message = "Cosmos DB account name must be 3-44 characters and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "key_vault_name" {
  description = "Base name for the Key Vault (suffix will be added automatically)"
  type        = string
  default     = "kv-alerts"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{3,24}$", var.key_vault_name))
    error_message = "Key Vault name must be 3-24 characters and contain only letters, numbers, and hyphens."
  }
}

variable "log_analytics_workspace_name" {
  description = "Base name for the Log Analytics workspace (suffix will be added automatically)"
  type        = string
  default     = "law-monitoring"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{4,63}$", var.log_analytics_workspace_name))
    error_message = "Log Analytics workspace name must be 4-63 characters and contain only letters, numbers, and hyphens."
  }
}

variable "application_insights_name" {
  description = "Base name for Application Insights (suffix will be added automatically)"
  type        = string
  default     = "ai-functions"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-_().]{1,255}$", var.application_insights_name))
    error_message = "Application Insights name must be 1-255 characters and contain only letters, numbers, hyphens, underscores, parentheses, and periods."
  }
}

variable "workbook_name" {
  description = "Base name for the Azure Monitor Workbook (suffix will be added automatically)"
  type        = string
  default     = "workbook-alerts"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-_().]{1,50}$", var.workbook_name))
    error_message = "Workbook name must be 1-50 characters and contain only letters, numbers, hyphens, underscores, parentheses, and periods."
  }
}

variable "cosmos_db_throughput" {
  description = "Throughput provisioned for Cosmos DB container (RU/s)"
  type        = number
  default     = 400
  
  validation {
    condition     = var.cosmos_db_throughput >= 400 && var.cosmos_db_throughput <= 100000
    error_message = "Cosmos DB throughput must be between 400 and 100000 RU/s."
  }
}

variable "log_analytics_retention_days" {
  description = "Data retention period for Log Analytics workspace (days)"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_analytics_retention_days >= 30 && var.log_analytics_retention_days <= 730
    error_message = "Log Analytics retention must be between 30 and 730 days."
  }
}

variable "function_app_runtime" {
  description = "Runtime version for Azure Functions"
  type        = string
  default     = "3.11"
  
  validation {
    condition     = contains(["3.8", "3.9", "3.10", "3.11"], var.function_app_runtime)
    error_message = "Function app runtime must be one of: 3.8, 3.9, 3.10, 3.11."
  }
}

variable "enable_monitoring" {
  description = "Enable comprehensive monitoring and diagnostics"
  type        = bool
  default     = true
}

variable "enable_rbac_authorization" {
  description = "Enable RBAC authorization for Key Vault"
  type        = bool
  default     = true
}

variable "key_vault_soft_delete_retention_days" {
  description = "Soft delete retention period for Key Vault (days)"
  type        = number
  default     = 7
  
  validation {
    condition     = var.key_vault_soft_delete_retention_days >= 7 && var.key_vault_soft_delete_retention_days <= 90
    error_message = "Key Vault soft delete retention must be between 7 and 90 days."
  }
}

variable "cosmos_db_consistency_level" {
  description = "Consistency level for Cosmos DB account"
  type        = string
  default     = "Session"
  
  validation {
    condition     = contains(["Strong", "BoundedStaleness", "Session", "ConsistentPrefix", "Eventual"], var.cosmos_db_consistency_level)
    error_message = "Cosmos DB consistency level must be one of: Strong, BoundedStaleness, Session, ConsistentPrefix, Eventual."
  }
}

variable "function_app_service_plan_sku" {
  description = "SKU for the Function App service plan"
  type        = string
  default     = "Y1"
  
  validation {
    condition     = contains(["Y1", "EP1", "EP2", "EP3", "P1V2", "P2V2", "P3V2"], var.function_app_service_plan_sku)
    error_message = "Function App service plan SKU must be one of: Y1, EP1, EP2, EP3, P1V2, P2V2, P3V2."
  }
}

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
    condition     = contains(["LRS", "ZRS", "GRS", "RAGRS", "GZRS", "RAGZRS"], var.storage_account_replication_type)
    error_message = "Storage account replication type must be one of: LRS, ZRS, GRS, RAGRS, GZRS, RAGZRS."
  }
}

variable "test_metric_alert_threshold" {
  description = "CPU threshold percentage for test metric alert"
  type        = number
  default     = 80
  
  validation {
    condition     = var.test_metric_alert_threshold >= 1 && var.test_metric_alert_threshold <= 100
    error_message = "Test metric alert threshold must be between 1 and 100 percent."
  }
}

variable "test_metric_alert_severity" {
  description = "Severity level for test metric alert (0=Critical, 1=Error, 2=Warning, 3=Informational, 4=Verbose)"
  type        = number
  default     = 2
  
  validation {
    condition     = var.test_metric_alert_severity >= 0 && var.test_metric_alert_severity <= 4
    error_message = "Test metric alert severity must be between 0 and 4."
  }
}

variable "event_grid_max_events_per_batch" {
  description = "Maximum number of events per batch for Event Grid subscriptions"
  type        = number
  default     = 1
  
  validation {
    condition     = var.event_grid_max_events_per_batch >= 1 && var.event_grid_max_events_per_batch <= 5000
    error_message = "Event Grid max events per batch must be between 1 and 5000."
  }
}

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
  
  validation {
    condition     = length(var.additional_tags) <= 50
    error_message = "Maximum of 50 additional tags allowed."
  }
}

variable "cosmos_db_enable_free_tier" {
  description = "Enable free tier for Cosmos DB account (only one per subscription)"
  type        = bool
  default     = false
}

variable "cosmos_db_geo_locations" {
  description = "List of geo locations for Cosmos DB account"
  type = list(object({
    location          = string
    failover_priority = number
  }))
  default = []
}

variable "function_app_always_on" {
  description = "Enable always on for Function App (requires Premium plan)"
  type        = bool
  default     = false
}

variable "key_vault_network_rules" {
  description = "Network access rules for Key Vault"
  type = object({
    default_action = string
    bypass         = string
    ip_rules       = list(string)
    virtual_network_subnet_ids = list(string)
  })
  default = {
    default_action = "Allow"
    bypass         = "AzureServices"
    ip_rules       = []
    virtual_network_subnet_ids = []
  }
}

variable "enable_diagnostic_settings" {
  description = "Enable diagnostic settings for resources"
  type        = bool
  default     = true
}

variable "diagnostic_setting_categories" {
  description = "Log and metric categories for diagnostic settings"
  type = object({
    log_categories    = list(string)
    metric_categories = list(string)
  })
  default = {
    log_categories    = ["FunctionAppLogs", "AuditEvent"]
    metric_categories = ["AllMetrics"]
  }
}