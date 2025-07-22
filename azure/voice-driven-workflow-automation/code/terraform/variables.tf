# Variables for Azure Voice-Enabled Business Process Automation Infrastructure
# This file defines all configurable parameters for the deployment

variable "resource_group_name" {
  description = "Name of the Azure Resource Group"
  type        = string
  default     = null
  validation {
    condition     = var.resource_group_name == null || can(regex("^[a-zA-Z0-9._-]+$", var.resource_group_name))
    error_message = "Resource group name must contain only letters, numbers, periods, underscores, and hyphens."
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
      "Canada Central", "Canada East", "Brazil South", "UK South", "UK West",
      "West Europe", "North Europe", "France Central", "Germany West Central",
      "Switzerland North", "Norway East", "Australia East", "Australia Southeast",
      "East Asia", "Southeast Asia", "Japan East", "Japan West",
      "Korea Central", "India Central", "South Africa North"
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
  description = "Name of the project used for resource naming"
  type        = string
  default     = "voice-automation"
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.project_name))
    error_message = "Project name must contain only letters, numbers, and hyphens."
  }
}

variable "speech_service_sku" {
  description = "SKU for Azure Speech Service (F0 for free tier, S0 for standard)"
  type        = string
  default     = "S0"
  validation {
    condition     = contains(["F0", "S0"], var.speech_service_sku)
    error_message = "Speech service SKU must be F0 (free) or S0 (standard)."
  }
}

variable "storage_account_tier" {
  description = "Storage account performance tier"
  type        = string
  default     = "Standard"
  validation {
    condition     = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be Standard or Premium."
  }
}

variable "storage_account_replication_type" {
  description = "Storage account replication type"
  type        = string
  default     = "LRS"
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_account_replication_type)
    error_message = "Storage account replication type must be LRS, GRS, RAGRS, ZRS, GZRS, or RAGZRS."
  }
}

variable "logic_app_name" {
  description = "Name for the Logic App (will be suffixed with random string)"
  type        = string
  default     = "logic-voice-processor"
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.logic_app_name))
    error_message = "Logic app name must contain only letters, numbers, and hyphens."
  }
}

variable "enable_diagnostic_logs" {
  description = "Enable diagnostic logging for resources"
  type        = bool
  default     = true
}

variable "log_analytics_retention_days" {
  description = "Retention period for Log Analytics workspace logs"
  type        = number
  default     = 30
  validation {
    condition     = var.log_analytics_retention_days >= 30 && var.log_analytics_retention_days <= 730
    error_message = "Log retention must be between 30 and 730 days."
  }
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Purpose     = "Voice Automation"
    Environment = "Demo"
    CreatedBy   = "Terraform"
  }
}

variable "allowed_ip_ranges" {
  description = "List of allowed IP ranges for network access"
  type        = list(string)
  default     = []
  validation {
    condition     = alltrue([for ip in var.allowed_ip_ranges : can(cidrhost(ip, 0))])
    error_message = "All IP ranges must be valid CIDR blocks."
  }
}

variable "enable_private_endpoints" {
  description = "Enable private endpoints for enhanced security"
  type        = bool
  default     = false
}

variable "speech_custom_domain_enabled" {
  description = "Enable custom domain for Speech Service"
  type        = bool
  default     = false
}

variable "backup_retention_days" {
  description = "Backup retention period in days"
  type        = number
  default     = 7
  validation {
    condition     = var.backup_retention_days >= 1 && var.backup_retention_days <= 35
    error_message = "Backup retention must be between 1 and 35 days."
  }
}