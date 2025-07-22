# General Configuration
variable "location" {
  description = "The Azure region where resources will be created"
  type        = string
  default     = "East US"
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "North Central US", "South Central US",
      "West Central US", "Canada Central", "Canada East",
      "Brazil South", "North Europe", "West Europe", "UK South",
      "UK West", "France Central", "Germany West Central",
      "Switzerland North", "Norway East", "Sweden Central",
      "Australia East", "Australia Southeast", "Japan East",
      "Japan West", "Korea Central", "Southeast Asia", "East Asia",
      "South India", "Central India", "West India"
    ], var.location)
    error_message = "The location must be a valid Azure region."
  }
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = null
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "demo"
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.environment))
    error_message = "Environment must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "carbon-tracking"
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

# AI Foundry Configuration
variable "ai_foundry_project_name" {
  description = "Name of the AI Foundry project"
  type        = string
  default     = null
}

variable "ai_foundry_description" {
  description = "Description of the AI Foundry project"
  type        = string
  default     = "AI Foundry project for intelligent supply chain carbon tracking"
}

variable "ai_foundry_friendly_name" {
  description = "Friendly name for the AI Foundry project"
  type        = string
  default     = "Carbon Tracking AI Foundry"
}

# Service Bus Configuration
variable "service_bus_namespace_name" {
  description = "Name of the Service Bus namespace"
  type        = string
  default     = null
}

variable "service_bus_sku" {
  description = "SKU for the Service Bus namespace"
  type        = string
  default     = "Standard"
  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.service_bus_sku)
    error_message = "Service Bus SKU must be Basic, Standard, or Premium."
  }
}

variable "service_bus_capacity" {
  description = "Capacity units for Premium Service Bus namespace"
  type        = number
  default     = 1
  validation {
    condition     = var.service_bus_capacity >= 1 && var.service_bus_capacity <= 16
    error_message = "Service Bus capacity must be between 1 and 16."
  }
}

variable "carbon_data_queue_settings" {
  description = "Configuration for carbon data queue"
  type = object({
    max_size_in_megabytes                = number
    default_message_ttl                  = string
    dead_lettering_on_message_expiration = bool
    duplicate_detection_history_time_window = string
    enable_batched_operations            = bool
    enable_express                       = bool
    enable_partitioning                  = bool
    lock_duration                        = string
    max_delivery_count                   = number
    requires_duplicate_detection         = bool
    requires_session                     = bool
  })
  default = {
    max_size_in_megabytes                = 1024
    default_message_ttl                  = "P14D"
    dead_lettering_on_message_expiration = true
    duplicate_detection_history_time_window = "PT10M"
    enable_batched_operations            = true
    enable_express                       = false
    enable_partitioning                  = false
    lock_duration                        = "PT1M"
    max_delivery_count                   = 10
    requires_duplicate_detection         = false
    requires_session                     = false
  }
}

variable "analysis_results_queue_settings" {
  description = "Configuration for analysis results queue"
  type = object({
    max_size_in_megabytes                = number
    default_message_ttl                  = string
    dead_lettering_on_message_expiration = bool
    duplicate_detection_history_time_window = string
    enable_batched_operations            = bool
    enable_express                       = bool
    enable_partitioning                  = bool
    lock_duration                        = string
    max_delivery_count                   = number
    requires_duplicate_detection         = bool
    requires_session                     = bool
  })
  default = {
    max_size_in_megabytes                = 1024
    default_message_ttl                  = "P14D"
    dead_lettering_on_message_expiration = true
    duplicate_detection_history_time_window = "PT10M"
    enable_batched_operations            = true
    enable_express                       = false
    enable_partitioning                  = false
    lock_duration                        = "PT1M"
    max_delivery_count                   = 10
    requires_duplicate_detection         = false
    requires_session                     = false
  }
}

# Function App Configuration
variable "function_app_name" {
  description = "Name of the Function App"
  type        = string
  default     = null
}

variable "function_app_service_plan_sku" {
  description = "SKU for the Function App service plan"
  type        = string
  default     = "Y1"
  validation {
    condition = contains([
      "Y1", "EP1", "EP2", "EP3", "P1", "P2", "P3", "P1v2", "P2v2", "P3v2", "P1v3", "P2v3", "P3v3"
    ], var.function_app_service_plan_sku)
    error_message = "Function App service plan SKU must be a valid Azure Functions SKU."
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
  default     = "3.11"
}

variable "function_app_storage_account_tier" {
  description = "Performance tier for Function App storage account"
  type        = string
  default     = "Standard"
  validation {
    condition     = contains(["Standard", "Premium"], var.function_app_storage_account_tier)
    error_message = "Storage account tier must be Standard or Premium."
  }
}

variable "function_app_storage_account_replication_type" {
  description = "Replication type for Function App storage account"
  type        = string
  default     = "LRS"
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.function_app_storage_account_replication_type)
    error_message = "Storage account replication type must be LRS, GRS, RAGRS, ZRS, GZRS, or RAGZRS."
  }
}

# Storage Account Configuration
variable "storage_account_name" {
  description = "Name of the storage account"
  type        = string
  default     = null
}

variable "storage_account_tier" {
  description = "Performance tier for the storage account"
  type        = string
  default     = "Standard"
  validation {
    condition     = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be Standard or Premium."
  }
}

variable "storage_account_replication_type" {
  description = "Replication type for the storage account"
  type        = string
  default     = "LRS"
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_account_replication_type)
    error_message = "Storage account replication type must be LRS, GRS, RAGRS, ZRS, GZRS, or RAGZRS."
  }
}

variable "storage_containers" {
  description = "List of storage containers to create"
  type = list(object({
    name                  = string
    container_access_type = string
  }))
  default = [
    {
      name                  = "carbon-data"
      container_access_type = "private"
    },
    {
      name                  = "analysis-results"
      container_access_type = "private"
    },
    {
      name                  = "agent-configurations"
      container_access_type = "private"
    }
  ]
}

# Application Insights Configuration
variable "application_insights_type" {
  description = "Application type for Application Insights"
  type        = string
  default     = "web"
  validation {
    condition     = contains(["web", "java", "MobileCenter", "Node.JS", "other"], var.application_insights_type)
    error_message = "Application Insights type must be web, java, MobileCenter, Node.JS, or other."
  }
}

variable "application_insights_retention_in_days" {
  description = "Data retention period for Application Insights"
  type        = number
  default     = 90
  validation {
    condition     = var.application_insights_retention_in_days >= 30 && var.application_insights_retention_in_days <= 730
    error_message = "Application Insights retention must be between 30 and 730 days."
  }
}

# Log Analytics Configuration
variable "log_analytics_retention_in_days" {
  description = "Data retention period for Log Analytics workspace"
  type        = number
  default     = 30
  validation {
    condition     = var.log_analytics_retention_in_days >= 7 && var.log_analytics_retention_in_days <= 730
    error_message = "Log Analytics retention must be between 7 and 730 days."
  }
}

variable "log_analytics_sku" {
  description = "SKU for Log Analytics workspace"
  type        = string
  default     = "PerGB2018"
  validation {
    condition     = contains(["Free", "PerNode", "Premium", "Standard", "Standalone", "Unlimited", "CapacityReservation", "PerGB2018"], var.log_analytics_sku)
    error_message = "Log Analytics SKU must be a valid pricing tier."
  }
}

# Key Vault Configuration
variable "key_vault_name" {
  description = "Name of the Key Vault"
  type        = string
  default     = null
}

variable "key_vault_sku" {
  description = "SKU for the Key Vault"
  type        = string
  default     = "standard"
  validation {
    condition     = contains(["standard", "premium"], var.key_vault_sku)
    error_message = "Key Vault SKU must be standard or premium."
  }
}

variable "key_vault_soft_delete_retention_days" {
  description = "Soft delete retention period for Key Vault"
  type        = number
  default     = 7
  validation {
    condition     = var.key_vault_soft_delete_retention_days >= 7 && var.key_vault_soft_delete_retention_days <= 90
    error_message = "Key Vault soft delete retention must be between 7 and 90 days."
  }
}

# Cognitive Services Configuration
variable "cognitive_services_name" {
  description = "Name of the Cognitive Services account"
  type        = string
  default     = null
}

variable "cognitive_services_kind" {
  description = "Kind of Cognitive Services account"
  type        = string
  default     = "CognitiveServices"
  validation {
    condition = contains([
      "CognitiveServices", "OpenAI", "TextAnalytics", "ComputerVision", "Face", "LUIS"
    ], var.cognitive_services_kind)
    error_message = "Cognitive Services kind must be a valid service type."
  }
}

variable "cognitive_services_sku" {
  description = "SKU for Cognitive Services account"
  type        = string
  default     = "S0"
  validation {
    condition     = contains(["F0", "S0", "S1", "S2", "S3", "S4"], var.cognitive_services_sku)
    error_message = "Cognitive Services SKU must be F0, S0, S1, S2, S3, or S4."
  }
}

# Power Platform Configuration
variable "power_platform_environment_name" {
  description = "Name of the Power Platform environment for Sustainability Manager"
  type        = string
  default     = null
}

variable "power_platform_environment_type" {
  description = "Type of Power Platform environment"
  type        = string
  default     = "Sandbox"
  validation {
    condition     = contains(["Sandbox", "Production", "Trial", "Developer"], var.power_platform_environment_type)
    error_message = "Power Platform environment type must be Sandbox, Production, Trial, or Developer."
  }
}

# Tagging Configuration
variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Purpose     = "carbon-tracking"
    Environment = "demo"
    Project     = "supply-chain-sustainability"
    ManagedBy   = "terraform"
  }
}

# Network Configuration
variable "virtual_network_address_space" {
  description = "Address space for the virtual network"
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "subnet_address_prefixes" {
  description = "Address prefixes for subnets"
  type = object({
    functions = list(string)
    ai        = list(string)
    data      = list(string)
  })
  default = {
    functions = ["10.0.1.0/24"]
    ai        = ["10.0.2.0/24"]
    data      = ["10.0.3.0/24"]
  }
}

# Security Configuration
variable "enable_private_endpoints" {
  description = "Enable private endpoints for enhanced security"
  type        = bool
  default     = false
}

variable "allowed_ip_ranges" {
  description = "IP ranges allowed to access resources"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# Monitoring Configuration
variable "enable_monitoring" {
  description = "Enable comprehensive monitoring and alerting"
  type        = bool
  default     = true
}

variable "alert_email_addresses" {
  description = "Email addresses for alert notifications"
  type        = list(string)
  default     = []
}

# Backup Configuration
variable "backup_retention_days" {
  description = "Number of days to retain backups"
  type        = number
  default     = 7
  validation {
    condition     = var.backup_retention_days >= 1 && var.backup_retention_days <= 365
    error_message = "Backup retention must be between 1 and 365 days."
  }
}

# Cost Management Configuration
variable "monthly_budget_amount" {
  description = "Monthly budget amount for cost management"
  type        = number
  default     = 500
  validation {
    condition     = var.monthly_budget_amount > 0
    error_message = "Monthly budget amount must be greater than 0."
  }
}

variable "budget_alert_threshold" {
  description = "Budget alert threshold percentage"
  type        = number
  default     = 80
  validation {
    condition     = var.budget_alert_threshold >= 50 && var.budget_alert_threshold <= 100
    error_message = "Budget alert threshold must be between 50 and 100 percent."
  }
}