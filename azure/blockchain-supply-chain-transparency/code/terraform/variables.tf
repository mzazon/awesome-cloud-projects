# ==============================================================================
# TERRAFORM VARIABLES
# ==============================================================================
# This file defines all the input variables for the blockchain supply chain
# transparency infrastructure deployment.

# ==============================================================================
# REQUIRED VARIABLES
# ==============================================================================

variable "location" {
  description = "The Azure region where resources will be created"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "West US 2", "North Europe", "West Europe", 
      "Southeast Asia", "UK South", "Australia East"
    ], var.location)
    error_message = "Azure Confidential Ledger is only available in specific regions. Choose from: East US, West US 2, North Europe, West Europe, Southeast Asia, UK South, Australia East."
  }
}

variable "secondary_location" {
  description = "The secondary Azure region for Cosmos DB global distribution"
  type        = string
  default     = "West US 2"
  
  validation {
    condition = contains([
      "East US", "West US 2", "North Europe", "West Europe", 
      "Southeast Asia", "UK South", "Australia East", "Central US", 
      "South Central US", "East US 2", "West US", "North Central US"
    ], var.secondary_location)
    error_message = "Please choose a valid Azure region for secondary location."
  }
}

variable "resource_group_name" {
  description = "The name of the Azure resource group"
  type        = string
  default     = "rg-supply-chain-ledger"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._-]+$", var.resource_group_name))
    error_message = "Resource group name must contain only alphanumeric characters, periods, underscores, and hyphens."
  }
}

variable "environment" {
  description = "The environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod", "demo"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod, demo."
  }
}

variable "publisher_email" {
  description = "The email address for the API Management publisher"
  type        = string
  default     = "admin@supplychain.demo"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.publisher_email))
    error_message = "Publisher email must be a valid email address."
  }
}

variable "alert_email" {
  description = "The email address for receiving monitoring alerts"
  type        = string
  default     = "admin@supplychain.demo"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.alert_email))
    error_message = "Alert email must be a valid email address."
  }
}

# ==============================================================================
# OPTIONAL VARIABLES
# ==============================================================================

variable "tags" {
  description = "A map of tags to assign to all resources"
  type        = map(string)
  default = {
    Project     = "SupplyChainTransparency"
    Environment = "Development"
    Owner       = "DevOps Team"
    Purpose     = "Blockchain Supply Chain"
    ManagedBy   = "Terraform"
  }
}

# ==============================================================================
# COSMOS DB CONFIGURATION
# ==============================================================================

variable "cosmos_db_consistency_level" {
  description = "The consistency level for Cosmos DB"
  type        = string
  default     = "Session"
  
  validation {
    condition = contains([
      "BoundedStaleness", "Eventual", "Session", "Strong", "ConsistentPrefix"
    ], var.cosmos_db_consistency_level)
    error_message = "Consistency level must be one of: BoundedStaleness, Eventual, Session, Strong, ConsistentPrefix."
  }
}

variable "cosmos_db_throughput" {
  description = "The throughput for Cosmos DB containers (RU/s)"
  type        = number
  default     = 1000
  
  validation {
    condition     = var.cosmos_db_throughput >= 400 && var.cosmos_db_throughput <= 1000000
    error_message = "Cosmos DB throughput must be between 400 and 1,000,000 RU/s."
  }
}

variable "cosmos_db_enable_free_tier" {
  description = "Enable free tier for Cosmos DB (only one per subscription)"
  type        = bool
  default     = false
}

variable "cosmos_db_enable_analytical_storage" {
  description = "Enable analytical storage for Cosmos DB"
  type        = bool
  default     = true
}

variable "cosmos_db_backup_type" {
  description = "The backup type for Cosmos DB (Periodic or Continuous)"
  type        = string
  default     = "Periodic"
  
  validation {
    condition     = contains(["Periodic", "Continuous"], var.cosmos_db_backup_type)
    error_message = "Backup type must be either Periodic or Continuous."
  }
}

# ==============================================================================
# STORAGE CONFIGURATION
# ==============================================================================

variable "storage_account_tier" {
  description = "The storage account tier"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be either Standard or Premium."
  }
}

variable "storage_replication_type" {
  description = "The storage account replication type"
  type        = string
  default     = "LRS"
  
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_replication_type)
    error_message = "Storage replication type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

variable "storage_enable_versioning" {
  description = "Enable blob versioning for storage account"
  type        = bool
  default     = true
}

variable "storage_enable_change_feed" {
  description = "Enable change feed for storage account"
  type        = bool
  default     = true
}

variable "storage_lifecycle_archive_days" {
  description = "Number of days after which to archive old documents"
  type        = number
  default     = 90
  
  validation {
    condition     = var.storage_lifecycle_archive_days >= 1 && var.storage_lifecycle_archive_days <= 365
    error_message = "Archive days must be between 1 and 365."
  }
}

# ==============================================================================
# KEY VAULT CONFIGURATION
# ==============================================================================

variable "key_vault_sku" {
  description = "The SKU for Key Vault"
  type        = string
  default     = "standard"
  
  validation {
    condition     = contains(["standard", "premium"], var.key_vault_sku)
    error_message = "Key Vault SKU must be either standard or premium."
  }
}

variable "key_vault_soft_delete_retention_days" {
  description = "Number of days to retain soft-deleted Key Vault"
  type        = number
  default     = 7
  
  validation {
    condition     = var.key_vault_soft_delete_retention_days >= 7 && var.key_vault_soft_delete_retention_days <= 90
    error_message = "Soft delete retention days must be between 7 and 90."
  }
}

variable "key_vault_enable_rbac" {
  description = "Enable RBAC authorization for Key Vault"
  type        = bool
  default     = true
}

variable "key_vault_enable_purge_protection" {
  description = "Enable purge protection for Key Vault (recommended for production)"
  type        = bool
  default     = false
}

# ==============================================================================
# API MANAGEMENT CONFIGURATION
# ==============================================================================

variable "api_management_sku" {
  description = "The SKU for API Management"
  type        = string
  default     = "Consumption_0"
  
  validation {
    condition = contains([
      "Consumption_0", "Developer_1", "Basic_1", "Basic_2", 
      "Standard_1", "Standard_2", "Premium_1", "Premium_2"
    ], var.api_management_sku)
    error_message = "API Management SKU must be a valid SKU name."
  }
}

variable "api_management_publisher_name" {
  description = "The publisher name for API Management"
  type        = string
  default     = "SupplyChainDemo"
  
  validation {
    condition     = length(var.api_management_publisher_name) > 0
    error_message = "Publisher name cannot be empty."
  }
}

variable "api_management_enable_cors" {
  description = "Enable CORS for API Management"
  type        = bool
  default     = true
}

variable "api_management_rate_limit_calls" {
  description = "Number of calls allowed per minute for rate limiting"
  type        = number
  default     = 100
  
  validation {
    condition     = var.api_management_rate_limit_calls >= 1 && var.api_management_rate_limit_calls <= 10000
    error_message = "Rate limit calls must be between 1 and 10,000."
  }
}

variable "api_management_rate_limit_period" {
  description = "Rate limit period in seconds"
  type        = number
  default     = 60
  
  validation {
    condition     = var.api_management_rate_limit_period >= 1 && var.api_management_rate_limit_period <= 3600
    error_message = "Rate limit period must be between 1 and 3600 seconds."
  }
}

# ==============================================================================
# MONITORING CONFIGURATION
# ==============================================================================

variable "log_analytics_sku" {
  description = "The SKU for Log Analytics workspace"
  type        = string
  default     = "PerGB2018"
  
  validation {
    condition = contains([
      "Free", "Standalone", "PerNode", "PerGB2018", "Premium"
    ], var.log_analytics_sku)
    error_message = "Log Analytics SKU must be one of: Free, Standalone, PerNode, PerGB2018, Premium."
  }
}

variable "log_analytics_retention_days" {
  description = "Number of days to retain logs in Log Analytics"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_analytics_retention_days >= 30 && var.log_analytics_retention_days <= 730
    error_message = "Log retention days must be between 30 and 730."
  }
}

variable "application_insights_type" {
  description = "The application type for Application Insights"
  type        = string
  default     = "web"
  
  validation {
    condition = contains([
      "web", "ios", "other", "store", "java", "phone"
    ], var.application_insights_type)
    error_message = "Application Insights type must be one of: web, ios, other, store, java, phone."
  }
}

variable "enable_monitoring_alerts" {
  description = "Enable monitoring alerts"
  type        = bool
  default     = true
}

variable "alert_threshold_requests" {
  description = "Threshold for high request volume alert"
  type        = number
  default     = 1000
  
  validation {
    condition     = var.alert_threshold_requests >= 100 && var.alert_threshold_requests <= 100000
    error_message = "Alert threshold must be between 100 and 100,000."
  }
}

variable "alert_window_size" {
  description = "Window size for alerts (in minutes)"
  type        = number
  default     = 5
  
  validation {
    condition     = contains([1, 5, 15, 30, 60], var.alert_window_size)
    error_message = "Alert window size must be one of: 1, 5, 15, 30, 60 minutes."
  }
}

variable "alert_frequency" {
  description = "Frequency of alert evaluation (in minutes)"
  type        = number
  default     = 1
  
  validation {
    condition     = contains([1, 5, 15, 30, 60], var.alert_frequency)
    error_message = "Alert frequency must be one of: 1, 5, 15, 30, 60 minutes."
  }
}

# ==============================================================================
# CONFIDENTIAL LEDGER CONFIGURATION
# ==============================================================================

variable "confidential_ledger_type" {
  description = "The type of Confidential Ledger"
  type        = string
  default     = "Public"
  
  validation {
    condition     = contains(["Public", "Private"], var.confidential_ledger_type)
    error_message = "Confidential Ledger type must be either Public or Private."
  }
}

# ==============================================================================
# SECURITY CONFIGURATION
# ==============================================================================

variable "enable_private_endpoints" {
  description = "Enable private endpoints for services"
  type        = bool
  default     = false
}

variable "allowed_ip_ranges" {
  description = "List of IP ranges allowed to access resources"
  type        = list(string)
  default     = []
}

variable "enable_defender_for_cloud" {
  description = "Enable Microsoft Defender for Cloud"
  type        = bool
  default     = false
}

# ==============================================================================
# NETWORKING CONFIGURATION
# ==============================================================================

variable "virtual_network_name" {
  description = "Name of the virtual network (if using private endpoints)"
  type        = string
  default     = "vnet-supply-chain"
}

variable "virtual_network_address_space" {
  description = "Address space for the virtual network"
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "subnet_name" {
  description = "Name of the subnet for private endpoints"
  type        = string
  default     = "subnet-private-endpoints"
}

variable "subnet_address_prefixes" {
  description = "Address prefixes for the subnet"
  type        = list(string)
  default     = ["10.0.1.0/24"]
}

# ==============================================================================
# COST OPTIMIZATION
# ==============================================================================

variable "enable_cost_optimization" {
  description = "Enable cost optimization features"
  type        = bool
  default     = true
}

variable "auto_shutdown_enabled" {
  description = "Enable auto-shutdown for development resources"
  type        = bool
  default     = false
}

variable "auto_shutdown_time" {
  description = "Time for auto-shutdown (HH:MM format)"
  type        = string
  default     = "18:00"
  
  validation {
    condition     = can(regex("^([0-1][0-9]|2[0-3]):[0-5][0-9]$", var.auto_shutdown_time))
    error_message = "Auto shutdown time must be in HH:MM format (24-hour)."
  }
}

# ==============================================================================
# BACKUP AND DISASTER RECOVERY
# ==============================================================================

variable "enable_backup" {
  description = "Enable backup for resources"
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

variable "enable_geo_backup" {
  description = "Enable geo-redundant backup"
  type        = bool
  default     = false
}

# ==============================================================================
# COMPLIANCE AND GOVERNANCE
# ==============================================================================

variable "enable_policy_compliance" {
  description = "Enable Azure Policy compliance"
  type        = bool
  default     = false
}

variable "required_compliance_tags" {
  description = "Required tags for compliance"
  type        = map(string)
  default     = {}
}

variable "enable_resource_locks" {
  description = "Enable resource locks for critical resources"
  type        = bool
  default     = false
}

variable "resource_lock_level" {
  description = "Level of resource lock (CanNotDelete or ReadOnly)"
  type        = string
  default     = "CanNotDelete"
  
  validation {
    condition     = contains(["CanNotDelete", "ReadOnly"], var.resource_lock_level)
    error_message = "Resource lock level must be either CanNotDelete or ReadOnly."
  }
}