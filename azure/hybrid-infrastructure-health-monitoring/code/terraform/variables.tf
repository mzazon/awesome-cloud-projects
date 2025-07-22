# Variable definitions for Azure Infrastructure Health Monitoring solution
# These variables allow customization of the deployment for different environments

variable "resource_group_name" {
  description = "Name of the Azure resource group for all infrastructure health monitoring resources"
  type        = string
  default     = "rg-infra-health-monitor"
  
  validation {
    condition     = length(var.resource_group_name) >= 1 && length(var.resource_group_name) <= 90
    error_message = "Resource group name must be between 1 and 90 characters."
  }
}

variable "location" {
  description = "Azure region where all resources will be deployed"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3", "Central US",
      "North Central US", "South Central US", "West Central US", "Canada Central",
      "Canada East", "Brazil South", "North Europe", "West Europe", "UK South",
      "UK West", "France Central", "Germany West Central", "Switzerland North",
      "Norway East", "Sweden Central", "Australia East", "Australia Southeast",
      "East Asia", "Southeast Asia", "Japan East", "Japan West", "Korea Central",
      "India Central", "South Africa North", "UAE North"
    ], var.location)
    error_message = "Location must be a valid Azure region."
  }
}

variable "environment" {
  description = "Environment tag for resource organization (dev, staging, prod)"
  type        = string
  default     = "demo"
  
  validation {
    condition     = contains(["dev", "staging", "prod", "demo"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod, demo."
  }
}

variable "project_name" {
  description = "Project name for resource naming and tagging"
  type        = string
  default     = "health-monitor"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "function_app_name_prefix" {
  description = "Prefix for the Azure Function App name (will be suffixed with random string)"
  type        = string
  default     = "func-health-monitor"
  
  validation {
    condition     = length(var.function_app_name_prefix) <= 40
    error_message = "Function app name prefix must be 40 characters or less."
  }
}

variable "storage_account_name_prefix" {
  description = "Prefix for the storage account name (will be suffixed with random string)"
  type        = string
  default     = "sthealth"
  
  validation {
    condition     = can(regex("^[a-z0-9]+$", var.storage_account_name_prefix))
    error_message = "Storage account prefix must contain only lowercase letters and numbers."
  }
}

variable "log_analytics_sku" {
  description = "SKU for the Log Analytics workspace"
  type        = string
  default     = "PerGB2018"
  
  validation {
    condition     = contains(["Free", "Standard", "Premium", "PerNode", "PerGB2018", "Standalone"], var.log_analytics_sku)
    error_message = "Log Analytics SKU must be one of: Free, Standard, Premium, PerNode, PerGB2018, Standalone."
  }
}

variable "log_analytics_retention_days" {
  description = "Number of days to retain logs in Log Analytics workspace"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_analytics_retention_days >= 7 && var.log_analytics_retention_days <= 730
    error_message = "Log Analytics retention must be between 7 and 730 days."
  }
}

variable "vnet_address_space" {
  description = "Address space for the virtual network (CIDR notation)"
  type        = string
  default     = "10.0.0.0/16"
  
  validation {
    condition     = can(cidrhost(var.vnet_address_space, 0))
    error_message = "VNet address space must be a valid CIDR block."
  }
}

variable "function_subnet_address_prefix" {
  description = "Address prefix for the Function App subnet (CIDR notation)"
  type        = string
  default     = "10.0.1.0/24"
  
  validation {
    condition     = can(cidrhost(var.function_subnet_address_prefix, 0))
    error_message = "Function subnet address prefix must be a valid CIDR block."
  }
}

variable "function_runtime_version" {
  description = "Runtime version for the Azure Function App"
  type        = string
  default     = "~4"
  
  validation {
    condition     = contains(["~4", "~3"], var.function_runtime_version)
    error_message = "Function runtime version must be ~3 or ~4."
  }
}

variable "function_python_version" {
  description = "Python version for the Azure Function App"
  type        = string
  default     = "3.11"
  
  validation {
    condition     = contains(["3.8", "3.9", "3.10", "3.11"], var.function_python_version)
    error_message = "Python version must be 3.8, 3.9, 3.10, or 3.11."
  }
}

variable "key_vault_sku" {
  description = "SKU for the Azure Key Vault"
  type        = string
  default     = "standard"
  
  validation {
    condition     = contains(["standard", "premium"], var.key_vault_sku)
    error_message = "Key Vault SKU must be either 'standard' or 'premium'."
  }
}

variable "storage_account_tier" {
  description = "Storage account performance tier"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be either 'Standard' or 'Premium'."
  }
}

variable "storage_account_replication_type" {
  description = "Storage account replication type"
  type        = string
  default     = "LRS"
  
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_account_replication_type)
    error_message = "Storage replication type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

variable "enable_application_insights" {
  description = "Whether to enable Application Insights for the Function App"
  type        = bool
  default     = true
}

variable "enable_system_assigned_identity" {
  description = "Whether to enable system-assigned managed identity for the Function App"
  type        = bool
  default     = true
}

variable "enable_vnet_integration" {
  description = "Whether to enable virtual network integration for the Function App"
  type        = bool
  default     = true
}

variable "health_check_schedule" {
  description = "CRON expression for the health check timer trigger"
  type        = string
  default     = "0 */15 * * * *"  # Every 15 minutes
  
  validation {
    condition     = can(regex("^[0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+$", var.health_check_schedule))
    error_message = "Health check schedule must be a valid CRON expression with 6 fields."
  }
}

variable "notification_channels" {
  description = "List of notification channels for alerts (teams, email, sms)"
  type        = list(string)
  default     = ["teams", "email"]
  
  validation {
    condition = alltrue([
      for channel in var.notification_channels : contains(["teams", "email", "sms"], channel)
    ])
    error_message = "Notification channels must be from: teams, email, sms."
  }
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default = {
    Purpose     = "Infrastructure Health Monitoring"
    Solution    = "Azure Functions + Update Manager"
    ManagedBy   = "Terraform"
  }
}