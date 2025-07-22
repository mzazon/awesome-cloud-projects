# Variables configuration for Azure document validation workflow infrastructure
# These variables enable customization of the deployment while maintaining
# enterprise-grade security and compliance standards

# Basic deployment configuration
variable "resource_group_name" {
  description = "Name of the Azure resource group for document validation resources"
  type        = string
  default     = null
  
  validation {
    condition     = var.resource_group_name == null || can(regex("^[a-zA-Z0-9._\\-()]+$", var.resource_group_name))
    error_message = "Resource group name must contain only alphanumeric characters, periods, underscores, hyphens, and parentheses."
  }
}

variable "location" {
  description = "Azure region for deploying resources. Must support Cognitive Services and Logic Apps"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "North Central US", "South Central US", "West Central US",
      "Canada Central", "Canada East", "Brazil South",
      "North Europe", "West Europe", "UK South", "UK West",
      "France Central", "Germany West Central", "Norway East",
      "Switzerland North", "Sweden Central",
      "Australia East", "Australia Southeast", "Japan East", "Japan West",
      "Korea Central", "Southeast Asia", "East Asia", "South India",
      "Central India", "West India", "UAE North", "South Africa North"
    ], var.location)
    error_message = "Location must be a valid Azure region that supports Cognitive Services."
  }
}

variable "environment" {
  description = "Environment designation for resource tagging and naming (dev, test, staging, prod)"
  type        = string
  default     = "prod"
  
  validation {
    condition     = contains(["dev", "test", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, test, staging, prod."
  }
}

variable "project_name" {
  description = "Project name used for resource naming and tagging"
  type        = string
  default     = "docvalidation"
  
  validation {
    condition     = can(regex("^[a-z0-9]{3,15}$", var.project_name))
    error_message = "Project name must be 3-15 characters, lowercase alphanumeric only."
  }
}

# Azure AI Document Intelligence configuration
variable "document_intelligence_sku" {
  description = "SKU for Azure AI Document Intelligence service (F0 for free tier, S0 for standard)"
  type        = string
  default     = "S0"
  
  validation {
    condition     = contains(["F0", "S0"], var.document_intelligence_sku)
    error_message = "Document Intelligence SKU must be F0 (free) or S0 (standard)."
  }
}

variable "document_intelligence_custom_subdomain" {
  description = "Custom subdomain for Document Intelligence service. If null, will be auto-generated"
  type        = string
  default     = null
  
  validation {
    condition     = var.document_intelligence_custom_subdomain == null || can(regex("^[a-z0-9][a-z0-9-]{1,62}[a-z0-9]$", var.document_intelligence_custom_subdomain))
    error_message = "Custom subdomain must be 3-64 characters, lowercase alphanumeric and hyphens only, cannot start or end with hyphen."
  }
}

# Storage account configuration
variable "storage_account_tier" {
  description = "Performance tier for storage account (Standard or Premium)"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be Standard or Premium."
  }
}

variable "storage_account_replication" {
  description = "Replication type for storage account (LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS)"
  type        = string
  default     = "LRS"
  
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_account_replication)
    error_message = "Storage replication must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

variable "storage_containers" {
  description = "List of storage containers to create for document processing"
  type        = list(string)
  default     = ["training-data", "processed-documents", "temp-storage"]
  
  validation {
    condition     = alltrue([for container in var.storage_containers : can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", container))])
    error_message = "Storage container names must be lowercase alphanumeric and hyphens only, 3-63 characters."
  }
}

# Key Vault configuration
variable "key_vault_sku" {
  description = "SKU for Azure Key Vault (standard or premium)"
  type        = string
  default     = "standard"
  
  validation {
    condition     = contains(["standard", "premium"], var.key_vault_sku)
    error_message = "Key Vault SKU must be standard or premium."
  }
}

variable "key_vault_soft_delete_retention_days" {
  description = "Number of days to retain soft-deleted Key Vault (7-90 days)"
  type        = number
  default     = 7
  
  validation {
    condition     = var.key_vault_soft_delete_retention_days >= 7 && var.key_vault_soft_delete_retention_days <= 90
    error_message = "Key Vault soft delete retention must be between 7 and 90 days."
  }
}

# Logic Apps configuration
variable "logic_app_plan_sku" {
  description = "SKU for Logic Apps Standard plan (WS1, WS2, WS3)"
  type        = string
  default     = "WS1"
  
  validation {
    condition     = contains(["WS1", "WS2", "WS3"], var.logic_app_plan_sku)
    error_message = "Logic App plan SKU must be WS1, WS2, or WS3."
  }
}

variable "logic_app_always_on" {
  description = "Enable always on for Logic Apps Standard"
  type        = bool
  default     = true
}

# Power Platform and Dataverse configuration
variable "power_platform_environment_display_name" {
  description = "Display name for Power Platform environment"
  type        = string
  default     = "Document Validation Production"
  
  validation {
    condition     = length(var.power_platform_environment_display_name) >= 3 && length(var.power_platform_environment_display_name) <= 64
    error_message = "Power Platform environment display name must be between 3 and 64 characters."
  }
}

variable "power_platform_environment_type" {
  description = "Type of Power Platform environment (Trial, Developer, Production)"
  type        = string
  default     = "Production"
  
  validation {
    condition     = contains(["Trial", "Developer", "Production"], var.power_platform_environment_type)
    error_message = "Power Platform environment type must be Trial, Developer, or Production."
  }
}

variable "dataverse_language_code" {
  description = "Language code for Dataverse environment (e.g., 1033 for English)"
  type        = number
  default     = 1033
  
  validation {
    condition     = var.dataverse_language_code > 0
    error_message = "Dataverse language code must be a positive integer."
  }
}

variable "dataverse_currency_code" {
  description = "Currency code for Dataverse environment (e.g., USD, EUR, GBP)"
  type        = string
  default     = "USD"
  
  validation {
    condition     = can(regex("^[A-Z]{3}$", var.dataverse_currency_code))
    error_message = "Currency code must be a 3-letter uppercase currency code."
  }
}

# Monitoring and logging configuration
variable "log_analytics_sku" {
  description = "SKU for Log Analytics workspace (PerGB2018, PerNode, Premium, Standalone, Unlimited, CapacityReservation)"
  type        = string
  default     = "PerGB2018"
  
  validation {
    condition     = contains(["PerGB2018", "PerNode", "Premium", "Standalone", "Unlimited", "CapacityReservation"], var.log_analytics_sku)
    error_message = "Log Analytics SKU must be a valid option."
  }
}

variable "log_retention_in_days" {
  description = "Number of days to retain logs in Log Analytics (30-730 days)"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_retention_in_days >= 30 && var.log_retention_in_days <= 730
    error_message = "Log retention must be between 30 and 730 days."
  }
}

variable "application_insights_application_type" {
  description = "Application type for Application Insights (web, other)"
  type        = string
  default     = "web"
  
  validation {
    condition     = contains(["web", "other"], var.application_insights_application_type)
    error_message = "Application Insights type must be web or other."
  }
}

# Security and access control
variable "allowed_ip_ranges" {
  description = "List of IP ranges allowed to access Key Vault and storage account"
  type        = list(string)
  default     = []
  
  validation {
    condition     = alltrue([for ip in var.allowed_ip_ranges : can(cidrhost(ip, 0))])
    error_message = "All IP ranges must be valid CIDR notation."
  }
}

variable "enable_private_endpoints" {
  description = "Enable private endpoints for services (requires VNET)"
  type        = bool
  default     = false
}

variable "virtual_network_address_space" {
  description = "Address space for virtual network when using private endpoints"
  type        = list(string)
  default     = ["10.0.0.0/16"]
  
  validation {
    condition     = alltrue([for cidr in var.virtual_network_address_space : can(cidrhost(cidr, 0))])
    error_message = "All address spaces must be valid CIDR notation."
  }
}

# Resource tagging
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
  
  validation {
    condition     = alltrue([for key in keys(var.additional_tags) : can(regex("^[a-zA-Z0-9_.-]+$", key))])
    error_message = "Tag keys must contain only alphanumeric characters, underscores, periods, and hyphens."
  }
}

# Automation and DevOps
variable "enable_diagnostic_settings" {
  description = "Enable diagnostic settings for all supported resources"
  type        = bool
  default     = true
}

variable "enable_backup" {
  description = "Enable backup for applicable resources"
  type        = bool
  default     = true
}

variable "backup_retention_days" {
  description = "Number of days to retain backups"
  type        = number
  default     = 30
  
  validation {
    condition     = var.backup_retention_days >= 1 && var.backup_retention_days <= 9999
    error_message = "Backup retention must be between 1 and 9999 days."
  }
}

# Scaling and performance
variable "auto_scale_enabled" {
  description = "Enable auto-scaling for applicable resources"
  type        = bool
  default     = true
}

variable "max_concurrent_requests" {
  description = "Maximum number of concurrent requests for Logic Apps"
  type        = number
  default     = 25
  
  validation {
    condition     = var.max_concurrent_requests >= 1 && var.max_concurrent_requests <= 100
    error_message = "Max concurrent requests must be between 1 and 100."
  }
}

# Business rules and validation
variable "document_validation_rules" {
  description = "Configuration for document validation rules"
  type = object({
    approval_threshold_amount = number
    required_confidence_score = number
    auto_approve_under_amount = number
  })
  default = {
    approval_threshold_amount = 1000
    required_confidence_score = 0.8
    auto_approve_under_amount = 100
  }
  
  validation {
    condition = (
      var.document_validation_rules.approval_threshold_amount >= 0 &&
      var.document_validation_rules.required_confidence_score >= 0.1 &&
      var.document_validation_rules.required_confidence_score <= 1.0 &&
      var.document_validation_rules.auto_approve_under_amount >= 0
    )
    error_message = "Validation rules must have valid threshold amounts and confidence score between 0.1 and 1.0."
  }
}