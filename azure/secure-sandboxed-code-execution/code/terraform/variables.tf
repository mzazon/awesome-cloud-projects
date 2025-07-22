# Variables for Azure secure code execution workflow infrastructure
# Configurable parameters for deployment customization

variable "location" {
  description = "The Azure region where resources will be deployed"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "North Central US", "South Central US",
      "West Central US", "Canada Central", "Canada East",
      "North Europe", "West Europe", "UK South", "UK West",
      "France Central", "Germany West Central", "Switzerland North",
      "Norway East", "Sweden Central", "Australia East",
      "Australia Southeast", "Japan East", "Japan West",
      "Korea Central", "South India", "Central India",
      "Southeast Asia", "East Asia"
    ], var.location)
    error_message = "Location must be a valid Azure region."
  }
}

variable "environment" {
  description = "Environment name for resource tagging and naming"
  type        = string
  default     = "demo"
  
  validation {
    condition     = can(regex("^[a-z0-9]+$", var.environment))
    error_message = "Environment must contain only lowercase letters and numbers."
  }
}

variable "project_name" {
  description = "Project name used as prefix for resource naming"
  type        = string
  default     = "secure-code-exec"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "resource_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default = {
    Purpose     = "recipe"
    Environment = "demo"
    ManagedBy   = "terraform"
    Project     = "secure-code-execution"
  }
}

# Container Apps Session Pool Configuration
variable "session_pool_config" {
  description = "Configuration for Azure Container Apps session pool"
  type = object({
    container_type        = string
    max_sessions         = number
    ready_sessions       = number
    cooldown_period_seconds = number
    network_status       = string
  })
  default = {
    container_type        = "PythonLTS"
    max_sessions         = 20
    ready_sessions       = 5
    cooldown_period_seconds = 300
    network_status       = "EgressDisabled"
  }
  
  validation {
    condition = contains([
      "PythonLTS", "NodeLTS", "DotNet", "CustomContainer"
    ], var.session_pool_config.container_type)
    error_message = "Container type must be one of: PythonLTS, NodeLTS, DotNet, CustomContainer."
  }
  
  validation {
    condition = var.session_pool_config.max_sessions >= 1 && var.session_pool_config.max_sessions <= 100
    error_message = "Max sessions must be between 1 and 100."
  }
  
  validation {
    condition = var.session_pool_config.ready_sessions >= 0 && var.session_pool_config.ready_sessions <= var.session_pool_config.max_sessions
    error_message = "Ready sessions must be between 0 and max_sessions."
  }
  
  validation {
    condition = contains(["EgressEnabled", "EgressDisabled"], var.session_pool_config.network_status)
    error_message = "Network status must be either EgressEnabled or EgressDisabled."
  }
}

# Storage Account Configuration
variable "storage_config" {
  description = "Configuration for Azure Storage Account"
  type = object({
    account_tier             = string
    account_replication_type = string
    access_tier             = string
    min_tls_version         = string
    https_traffic_only      = bool
  })
  default = {
    account_tier             = "Standard"
    account_replication_type = "LRS"
    access_tier             = "Hot"
    min_tls_version         = "TLS1_2"
    https_traffic_only      = true
  }
  
  validation {
    condition = contains(["Standard", "Premium"], var.storage_config.account_tier)
    error_message = "Account tier must be either Standard or Premium."
  }
  
  validation {
    condition = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_config.account_replication_type)
    error_message = "Replication type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

# Function App Configuration
variable "function_app_config" {
  description = "Configuration for Azure Function App"
  type = object({
    runtime_version = string
    runtime_stack   = string
    os_type        = string
  })
  default = {
    runtime_version = "~4"
    runtime_stack   = "python"
    os_type        = "Linux"
  }
  
  validation {
    condition = contains(["python", "node", "dotnet", "java"], var.function_app_config.runtime_stack)
    error_message = "Runtime stack must be one of: python, node, dotnet, java."
  }
  
  validation {
    condition = contains(["Linux", "Windows"], var.function_app_config.os_type)
    error_message = "OS type must be either Linux or Windows."
  }
}

# Key Vault Configuration
variable "key_vault_config" {
  description = "Configuration for Azure Key Vault"
  type = object({
    sku_name                        = string
    enabled_for_disk_encryption     = bool
    enabled_for_deployment          = bool
    enabled_for_template_deployment = bool
    enable_rbac_authorization       = bool
    purge_protection_enabled        = bool
    soft_delete_retention_days      = number
  })
  default = {
    sku_name                        = "standard"
    enabled_for_disk_encryption     = false
    enabled_for_deployment          = false
    enabled_for_template_deployment = false
    enable_rbac_authorization       = true
    purge_protection_enabled        = false
    soft_delete_retention_days      = 7
  }
  
  validation {
    condition = contains(["standard", "premium"], var.key_vault_config.sku_name)
    error_message = "Key Vault SKU must be either standard or premium."
  }
  
  validation {
    condition = var.key_vault_config.soft_delete_retention_days >= 7 && var.key_vault_config.soft_delete_retention_days <= 90
    error_message = "Soft delete retention days must be between 7 and 90."
  }
}

# Log Analytics Configuration
variable "log_analytics_config" {
  description = "Configuration for Log Analytics Workspace"
  type = object({
    sku               = string
    retention_in_days = number
    daily_quota_gb    = number
  })
  default = {
    sku               = "PerGB2018"
    retention_in_days = 30
    daily_quota_gb    = 10
  }
  
  validation {
    condition = contains(["Free", "PerNode", "PerGB2018", "Premium", "Standalone"], var.log_analytics_config.sku)
    error_message = "Log Analytics SKU must be one of: Free, PerNode, PerGB2018, Premium, Standalone."
  }
  
  validation {
    condition = var.log_analytics_config.retention_in_days >= 30 && var.log_analytics_config.retention_in_days <= 730
    error_message = "Retention period must be between 30 and 730 days."
  }
}

# Event Grid Configuration
variable "event_grid_config" {
  description = "Configuration for Event Grid Topic"
  type = object({
    input_schema                 = string
    public_network_access_enabled = bool
    local_auth_enabled           = bool
  })
  default = {
    input_schema                 = "EventGridSchema"
    public_network_access_enabled = true
    local_auth_enabled           = true
  }
  
  validation {
    condition = contains(["EventGridSchema", "CloudEventSchemaV1_0", "CustomInputSchema"], var.event_grid_config.input_schema)
    error_message = "Input schema must be one of: EventGridSchema, CloudEventSchemaV1_0, CustomInputSchema."
  }
}

# Random suffix length for unique resource naming
variable "random_suffix_length" {
  description = "Length of random suffix for unique resource naming"
  type        = number
  default     = 6
  
  validation {
    condition     = var.random_suffix_length >= 4 && var.random_suffix_length <= 10
    error_message = "Random suffix length must be between 4 and 10 characters."
  }
}