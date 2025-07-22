# Variables for Azure Storage Lifecycle Management Infrastructure

# Basic Configuration Variables
variable "resource_group_name" {
  description = "Name of the resource group for lifecycle management resources"
  type        = string
  default     = "rg-lifecycle-demo"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._-]+$", var.resource_group_name))
    error_message = "Resource group name must contain only letters, numbers, periods, hyphens, and underscores."
  }
}

variable "location" {
  description = "Azure region where resources will be deployed"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "North Central US", "South Central US", "West Central US",
      "Canada Central", "Canada East", "Brazil South", "North Europe",
      "West Europe", "UK South", "UK West", "France Central", "Germany West Central",
      "Switzerland North", "Norway East", "Sweden Central", "Australia East",
      "Australia Southeast", "Japan East", "Japan West", "Korea Central",
      "Korea South", "Asia Pacific", "Southeast Asia", "India Central",
      "India South", "India West"
    ], var.location)
    error_message = "Location must be a valid Azure region."
  }
}

variable "environment" {
  description = "Environment name for resource tagging and naming"
  type        = string
  default     = "development"
  
  validation {
    condition = contains([
      "development", "staging", "production", "testing", "demo"
    ], var.environment)
    error_message = "Environment must be one of: development, staging, production, testing, demo."
  }
}

# Storage Account Configuration Variables
variable "storage_account_name_prefix" {
  description = "Prefix for storage account name (will be suffixed with random string)"
  type        = string
  default     = "stlifecycle"
  
  validation {
    condition     = can(regex("^[a-z0-9]{1,11}$", var.storage_account_name_prefix))
    error_message = "Storage account name prefix must be 1-11 characters, lowercase letters and numbers only."
  }
}

variable "storage_account_tier" {
  description = "Storage account performance tier"
  type        = string
  default     = "Standard"
  
  validation {
    condition = contains([
      "Standard", "Premium"
    ], var.storage_account_tier)
    error_message = "Storage account tier must be either Standard or Premium."
  }
}

variable "storage_account_replication_type" {
  description = "Storage account replication type"
  type        = string
  default     = "LRS"
  
  validation {
    condition = contains([
      "LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"
    ], var.storage_account_replication_type)
    error_message = "Storage account replication type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

variable "storage_account_kind" {
  description = "Storage account kind"
  type        = string
  default     = "StorageV2"
  
  validation {
    condition = contains([
      "BlobStorage", "BlockBlobStorage", "FileStorage", "Storage", "StorageV2"
    ], var.storage_account_kind)
    error_message = "Storage account kind must be one of: BlobStorage, BlockBlobStorage, FileStorage, Storage, StorageV2."
  }
}

variable "storage_account_access_tier" {
  description = "Default access tier for blob storage"
  type        = string
  default     = "Hot"
  
  validation {
    condition = contains([
      "Hot", "Cool"
    ], var.storage_account_access_tier)
    error_message = "Storage account access tier must be either Hot or Cool."
  }
}

# Blob Storage Configuration Variables
variable "enable_blob_versioning" {
  description = "Enable blob versioning for the storage account"
  type        = bool
  default     = true
}

variable "enable_blob_soft_delete" {
  description = "Enable soft delete for blob storage"
  type        = bool
  default     = true
}

variable "blob_soft_delete_retention_days" {
  description = "Number of days to retain soft-deleted blobs"
  type        = number
  default     = 30
  
  validation {
    condition     = var.blob_soft_delete_retention_days >= 1 && var.blob_soft_delete_retention_days <= 365
    error_message = "Blob soft delete retention days must be between 1 and 365."
  }
}

variable "enable_container_soft_delete" {
  description = "Enable soft delete for containers"
  type        = bool
  default     = true
}

variable "container_soft_delete_retention_days" {
  description = "Number of days to retain soft-deleted containers"
  type        = number
  default     = 30
  
  validation {
    condition     = var.container_soft_delete_retention_days >= 1 && var.container_soft_delete_retention_days <= 365
    error_message = "Container soft delete retention days must be between 1 and 365."
  }
}

# Storage Containers Configuration
variable "storage_containers" {
  description = "List of storage containers to create"
  type = list(object({
    name                  = string
    container_access_type = string
  }))
  default = [
    {
      name                  = "documents"
      container_access_type = "private"
    },
    {
      name                  = "logs"
      container_access_type = "private"
    }
  ]
  
  validation {
    condition = alltrue([
      for container in var.storage_containers : contains(["blob", "container", "private"], container.container_access_type)
    ])
    error_message = "Container access type must be one of: blob, container, private."
  }
}

# Lifecycle Management Policy Configuration
variable "lifecycle_policy_enabled" {
  description = "Enable lifecycle management policy"
  type        = bool
  default     = true
}

variable "document_lifecycle_rules" {
  description = "Lifecycle rules for documents container"
  type = object({
    tier_to_cool_days    = number
    tier_to_archive_days = number
    delete_after_days    = number
  })
  default = {
    tier_to_cool_days    = 30
    tier_to_archive_days = 90
    delete_after_days    = 365
  }
  
  validation {
    condition = (
      var.document_lifecycle_rules.tier_to_cool_days < var.document_lifecycle_rules.tier_to_archive_days &&
      var.document_lifecycle_rules.tier_to_archive_days < var.document_lifecycle_rules.delete_after_days
    )
    error_message = "Lifecycle rules must have increasing day values: tier_to_cool_days < tier_to_archive_days < delete_after_days."
  }
}

variable "log_lifecycle_rules" {
  description = "Lifecycle rules for logs container"
  type = object({
    tier_to_cool_days    = number
    tier_to_archive_days = number
    delete_after_days    = number
  })
  default = {
    tier_to_cool_days    = 7
    tier_to_archive_days = 30
    delete_after_days    = 180
  }
  
  validation {
    condition = (
      var.log_lifecycle_rules.tier_to_cool_days < var.log_lifecycle_rules.tier_to_archive_days &&
      var.log_lifecycle_rules.tier_to_archive_days < var.log_lifecycle_rules.delete_after_days
    )
    error_message = "Lifecycle rules must have increasing day values: tier_to_cool_days < tier_to_archive_days < delete_after_days."
  }
}

# Log Analytics Configuration Variables
variable "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  type        = string
  default     = "law-storage-monitoring"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]{0,61}[a-zA-Z0-9]$", var.log_analytics_workspace_name))
    error_message = "Log Analytics workspace name must be 1-63 characters, start and end with alphanumeric characters, and contain only alphanumeric characters and hyphens."
  }
}

variable "log_analytics_sku" {
  description = "Log Analytics workspace SKU"
  type        = string
  default     = "PerGB2018"
  
  validation {
    condition = contains([
      "Free", "Standalone", "PerNode", "PerGB2018", "Premium", "Standard", "Unlimited", "CapacityReservation"
    ], var.log_analytics_sku)
    error_message = "Log Analytics SKU must be one of: Free, Standalone, PerNode, PerGB2018, Premium, Standard, Unlimited, CapacityReservation."
  }
}

variable "log_analytics_retention_in_days" {
  description = "Number of days to retain logs in Log Analytics workspace"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_analytics_retention_in_days >= 30 && var.log_analytics_retention_in_days <= 730
    error_message = "Log Analytics retention must be between 30 and 730 days."
  }
}

# Monitoring and Alerting Configuration
variable "enable_storage_monitoring" {
  description = "Enable storage account monitoring and diagnostics"
  type        = bool
  default     = true
}

variable "diagnostic_logs_retention_days" {
  description = "Number of days to retain diagnostic logs"
  type        = number
  default     = 30
  
  validation {
    condition     = var.diagnostic_logs_retention_days >= 1 && var.diagnostic_logs_retention_days <= 365
    error_message = "Diagnostic logs retention must be between 1 and 365 days."
  }
}

variable "enable_capacity_alerts" {
  description = "Enable storage capacity alerts"
  type        = bool
  default     = true
}

variable "storage_capacity_alert_threshold" {
  description = "Storage capacity alert threshold in bytes"
  type        = number
  default     = 1000000000  # 1GB
  
  validation {
    condition     = var.storage_capacity_alert_threshold > 0
    error_message = "Storage capacity alert threshold must be greater than 0."
  }
}

variable "enable_transaction_alerts" {
  description = "Enable storage transaction alerts"
  type        = bool
  default     = true
}

variable "transaction_count_alert_threshold" {
  description = "Transaction count alert threshold"
  type        = number
  default     = 1000
  
  validation {
    condition     = var.transaction_count_alert_threshold > 0
    error_message = "Transaction count alert threshold must be greater than 0."
  }
}

# Logic App Configuration Variables
variable "logic_app_name" {
  description = "Name of the Logic App for storage alerts"
  type        = string
  default     = "logic-storage-alerts"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]{0,78}[a-zA-Z0-9]$", var.logic_app_name))
    error_message = "Logic App name must be 1-80 characters, start and end with alphanumeric characters, and contain only alphanumeric characters and hyphens."
  }
}

variable "enable_logic_app_alerts" {
  description = "Enable Logic App for automated alerting"
  type        = bool
  default     = true
}

# Action Group Configuration
variable "action_group_name" {
  description = "Name of the action group for alerts"
  type        = string
  default     = "StorageAlertsGroup"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]{0,258}[a-zA-Z0-9]$", var.action_group_name))
    error_message = "Action group name must be 1-260 characters, start and end with alphanumeric characters, and contain only alphanumeric characters and hyphens."
  }
}

variable "action_group_short_name" {
  description = "Short name for the action group (max 12 characters)"
  type        = string
  default     = "StorageAlerts"
  
  validation {
    condition     = length(var.action_group_short_name) <= 12
    error_message = "Action group short name must be 12 characters or less."
  }
}

# Alert Configuration
variable "alert_evaluation_frequency" {
  description = "How often to evaluate alert conditions"
  type        = string
  default     = "PT5M"
  
  validation {
    condition = contains([
      "PT1M", "PT5M", "PT15M", "PT30M", "PT1H"
    ], var.alert_evaluation_frequency)
    error_message = "Alert evaluation frequency must be one of: PT1M, PT5M, PT15M, PT30M, PT1H."
  }
}

variable "alert_window_size" {
  description = "Time window for alert evaluation"
  type        = string
  default     = "PT15M"
  
  validation {
    condition = contains([
      "PT1M", "PT5M", "PT15M", "PT30M", "PT1H", "PT6H", "PT12H", "PT24H"
    ], var.alert_window_size)
    error_message = "Alert window size must be one of: PT1M, PT5M, PT15M, PT30M, PT1H, PT6H, PT12H, PT24H."
  }
}

# Sample Data Configuration
variable "create_sample_data" {
  description = "Create sample data for testing lifecycle management"
  type        = bool
  default     = true
}

variable "sample_data_files" {
  description = "Sample data files to create for testing"
  type = list(object({
    container_name = string
    blob_name      = string
    content        = string
  }))
  default = [
    {
      container_name = "documents"
      blob_name      = "document1.txt"
      content        = "Sample document content - frequently accessed"
    },
    {
      container_name = "logs"
      blob_name      = "app.log"
      content        = "Application log entry - infrequently accessed"
    },
    {
      container_name = "documents"
      blob_name      = "archive.txt"
      content        = "Archive document content - rarely accessed"
    }
  ]
}

# Resource Tagging Variables
variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default = {
    Purpose     = "lifecycle-demo"
    Environment = "development"
    Project     = "storage-lifecycle-management"
    Owner       = "infrastructure-team"
    CostCenter  = "it-infrastructure"
  }
}

variable "additional_tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}