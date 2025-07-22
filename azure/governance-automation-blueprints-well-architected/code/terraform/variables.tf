# Variables for Azure Governance Automation with Blueprints

variable "location" {
  description = "The Azure region where resources will be deployed"
  type        = string
  default     = "East US"
  
  validation {
    condition = can(regex("^[a-zA-Z0-9\\s]+$", var.location))
    error_message = "Location must be a valid Azure region name."
  }
}

variable "resource_group_name" {
  description = "Name of the resource group for governance resources"
  type        = string
  default     = "rg-governance"
  
  validation {
    condition = can(regex("^[a-zA-Z0-9-_]{1,90}$", var.resource_group_name))
    error_message = "Resource group name must be 1-90 characters long and can contain alphanumeric characters, hyphens, and underscores."
  }
}

variable "blueprint_name" {
  description = "Name of the Azure Blueprint definition"
  type        = string
  default     = "enterprise-governance-blueprint"
  
  validation {
    condition = can(regex("^[a-zA-Z0-9-_]{1,90}$", var.blueprint_name))
    error_message = "Blueprint name must be 1-90 characters long and can contain alphanumeric characters, hyphens, and underscores."
  }
}

variable "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace for governance monitoring"
  type        = string
  default     = "law-governance"
  
  validation {
    condition = can(regex("^[a-zA-Z0-9-_]{4,63}$", var.log_analytics_workspace_name))
    error_message = "Log Analytics workspace name must be 4-63 characters long and can contain alphanumeric characters, hyphens, and underscores."
  }
}

variable "log_analytics_retention_days" {
  description = "Number of days to retain logs in Log Analytics workspace"
  type        = number
  default     = 30
  
  validation {
    condition = var.log_analytics_retention_days >= 30 && var.log_analytics_retention_days <= 730
    error_message = "Log Analytics retention must be between 30 and 730 days."
  }
}

variable "log_analytics_sku" {
  description = "SKU for Log Analytics workspace"
  type        = string
  default     = "Standard"
  
  validation {
    condition = contains(["Free", "Standard", "Premium", "Unlimited", "PerNode", "PerGB2018"], var.log_analytics_sku)
    error_message = "Log Analytics SKU must be one of: Free, Standard, Premium, Unlimited, PerNode, PerGB2018."
  }
}

variable "blueprint_version" {
  description = "Version of the blueprint to publish"
  type        = string
  default     = "1.0"
  
  validation {
    condition = can(regex("^[0-9]+\\.[0-9]+$", var.blueprint_version))
    error_message = "Blueprint version must be in format x.y (e.g., 1.0)."
  }
}

variable "required_tags" {
  description = "List of required tags for resources"
  type        = list(string)
  default     = ["Environment", "CostCenter", "Owner"]
  
  validation {
    condition = length(var.required_tags) > 0
    error_message = "At least one required tag must be specified."
  }
}

variable "environment" {
  description = "Environment designation for resources"
  type        = string
  default     = "production"
  
  validation {
    condition = contains(["development", "staging", "production"], var.environment)
    error_message = "Environment must be one of: development, staging, production."
  }
}

variable "cost_center" {
  description = "Cost center for resource billing"
  type        = string
  default     = "IT"
  
  validation {
    condition = can(regex("^[a-zA-Z0-9-_]{1,50}$", var.cost_center))
    error_message = "Cost center must be 1-50 characters long and can contain alphanumeric characters, hyphens, and underscores."
  }
}

variable "owner" {
  description = "Owner of the resources"
  type        = string
  default     = "CloudTeam"
  
  validation {
    condition = can(regex("^[a-zA-Z0-9-_]{1,50}$", var.owner))
    error_message = "Owner must be 1-50 characters long and can contain alphanumeric characters, hyphens, and underscores."
  }
}

variable "governance_email" {
  description = "Email address for governance team notifications"
  type        = string
  default     = "governance@company.com"
  
  validation {
    condition = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.governance_email))
    error_message = "Governance email must be a valid email address."
  }
}

variable "enable_advisor_alerts" {
  description = "Whether to enable Azure Advisor alerts"
  type        = bool
  default     = true
}

variable "enable_governance_dashboard" {
  description = "Whether to create governance monitoring dashboard"
  type        = bool
  default     = true
}

variable "storage_account_name_prefix" {
  description = "Prefix for storage account names in templates"
  type        = string
  default     = "stgovern"
  
  validation {
    condition = can(regex("^[a-z0-9]{3,11}$", var.storage_account_name_prefix))
    error_message = "Storage account name prefix must be 3-11 characters long and contain only lowercase alphanumeric characters."
  }
}

variable "minimum_tls_version" {
  description = "Minimum TLS version for storage accounts"
  type        = string
  default     = "TLS1_2"
  
  validation {
    condition = contains(["TLS1_0", "TLS1_1", "TLS1_2"], var.minimum_tls_version)
    error_message = "Minimum TLS version must be one of: TLS1_0, TLS1_1, TLS1_2."
  }
}

variable "enable_https_traffic_only" {
  description = "Whether to enable HTTPS traffic only for storage accounts"
  type        = bool
  default     = true
}

variable "storage_account_tier" {
  description = "Access tier for storage accounts"
  type        = string
  default     = "Hot"
  
  validation {
    condition = contains(["Hot", "Cool"], var.storage_account_tier)
    error_message = "Storage account tier must be either Hot or Cool."
  }
}

variable "governance_tags" {
  description = "Common tags to apply to all governance resources"
  type        = map(string)
  default = {
    Purpose     = "governance"
    Framework   = "well-architected"
    ManagedBy   = "terraform"
  }
}