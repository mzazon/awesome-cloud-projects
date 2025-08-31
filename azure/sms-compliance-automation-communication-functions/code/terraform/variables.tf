# Variables for SMS Compliance Automation Infrastructure
# These variables allow customization of the deployment for different environments

# Basic Configuration Variables
variable "location" {
  description = "The Azure region where resources will be deployed"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "North Central US", "South Central US", "West Central US",
      "Canada Central", "Canada East",
      "Brazil South",
      "North Europe", "West Europe", "UK South", "UK West",
      "France Central", "Germany West Central", "Norway East",
      "Switzerland North", "Sweden Central",
      "Australia East", "Australia Southeast",
      "Japan East", "Japan West",
      "Korea Central", "Korea South",
      "Southeast Asia", "East Asia",
      "India Central", "India South", "India West",
      "UAE North", "South Africa North"
    ], var.location)
    error_message = "The location must be a valid Azure region."
  }
}

variable "data_location" {
  description = "The data residency location for Azure Communication Services"
  type        = string
  default     = "United States"
  
  validation {
    condition = contains([
      "United States", "Europe", "Australia", "United Kingdom", "France", "Germany", "Switzerland", "Norway", "UAE"
    ], var.data_location)
    error_message = "The data_location must be a valid Azure Communication Services data location."
  }
}

# Resource Naming Variables
variable "resource_prefix" {
  description = "Prefix for resource names to ensure uniqueness"
  type        = string
  default     = "sms-compliance"
  
  validation {
    condition     = length(var.resource_prefix) <= 20 && can(regex("^[a-z0-9-]+$", var.resource_prefix))
    error_message = "Resource prefix must be 20 characters or less and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "Environment name (dev, test, staging, prod)"
  type        = string
  default     = "demo"
  
  validation {
    condition     = contains(["dev", "test", "staging", "prod", "demo"], var.environment)
    error_message = "Environment must be one of: dev, test, staging, prod, demo."
  }
}

# Storage Account Configuration
variable "storage_account_tier" {
  description = "The performance tier of the storage account"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be either Standard or Premium."
  }
}

variable "storage_replication_type" {
  description = "The replication type for the storage account"
  type        = string
  default     = "LRS"
  
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_replication_type)
    error_message = "Storage replication type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

# Application Insights Configuration
variable "application_insights_retention_days" {
  description = "Number of days to retain Application Insights data"
  type        = number
  default     = 90
  
  validation {
    condition     = var.application_insights_retention_days >= 30 && var.application_insights_retention_days <= 730
    error_message = "Application Insights retention must be between 30 and 730 days."
  }
}

# Function App Configuration
variable "function_app_runtime_version" {
  description = "The runtime version for the Function App"
  type        = string
  default     = "~4"
  
  validation {
    condition     = contains(["~3", "~4"], var.function_app_runtime_version)
    error_message = "Function App runtime version must be ~3 or ~4."
  }
}

variable "node_version" {
  description = "Node.js version for the Function App"
  type        = string
  default     = "20"
  
  validation {
    condition     = contains(["18", "20"], var.node_version)
    error_message = "Node version must be 18 or 20."
  }
}

# Security Configuration
variable "allowed_cors_origins" {
  description = "List of allowed CORS origins for the Function App"
  type        = list(string)
  default     = ["*"]
  
  validation {
    condition     = length(var.allowed_cors_origins) > 0
    error_message = "At least one CORS origin must be specified."
  }
}

variable "enable_key_vault" {
  description = "Enable Azure Key Vault for storing sensitive configuration"
  type        = bool
  default     = false
}

variable "key_vault_soft_delete_retention_days" {
  description = "Number of days to retain soft-deleted Key Vault items"
  type        = number
  default     = 7
  
  validation {
    condition     = var.key_vault_soft_delete_retention_days >= 7 && var.key_vault_soft_delete_retention_days <= 90
    error_message = "Key Vault soft delete retention must be between 7 and 90 days."
  }
}

# Monitoring Configuration
variable "enable_log_analytics" {
  description = "Enable Log Analytics workspace for enhanced monitoring"
  type        = bool
  default     = false
}

variable "log_analytics_retention_days" {
  description = "Number of days to retain Log Analytics data"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_analytics_retention_days >= 30 && var.log_analytics_retention_days <= 730
    error_message = "Log Analytics retention must be between 30 and 730 days."
  }
}

# SMS Compliance Configuration
variable "default_from_number" {
  description = "Default phone number for SMS communications (optional)"
  type        = string
  default     = ""
  
  validation {
    condition     = var.default_from_number == "" || can(regex("^\\+[1-9]\\d{1,14}$", var.default_from_number))
    error_message = "Default from number must be empty or a valid E.164 format phone number."
  }
}

variable "compliance_audit_retention_days" {
  description = "Number of days to retain compliance audit records"
  type        = number
  default     = 2555  # 7 years for compliance requirements
  
  validation {
    condition     = var.compliance_audit_retention_days >= 365
    error_message = "Compliance audit retention must be at least 365 days for regulatory requirements."
  }
}

variable "enable_compliance_monitoring" {
  description = "Enable automated compliance monitoring functions"
  type        = bool
  default     = true
}

# Timer Function Configuration
variable "compliance_check_schedule" {
  description = "CRON expression for compliance monitoring schedule (default: daily at 9 AM UTC)"
  type        = string
  default     = "0 0 9 * * *"
  
  validation {
    condition     = can(regex("^[0-5]?[0-9] [0-5]?[0-9] ([0-1]?[0-9]|2[0-3]) \\* \\* \\*$", var.compliance_check_schedule))
    error_message = "Compliance check schedule must be a valid CRON expression (e.g., '0 0 9 * * *')."
  }
}

# Performance Configuration
variable "function_app_always_on" {
  description = "Keep Function App always on (not applicable for Consumption plan)"
  type        = bool
  default     = false
}

variable "function_app_timeout" {
  description = "Function execution timeout in seconds (max 600 for Consumption plan)"
  type        = number
  default     = 300
  
  validation {
    condition     = var.function_app_timeout >= 1 && var.function_app_timeout <= 600
    error_message = "Function timeout must be between 1 and 600 seconds for Consumption plan."
  }
}

# Cost Management Configuration
variable "enable_cost_alerts" {
  description = "Enable cost monitoring and alerts"
  type        = bool
  default     = false
}

variable "monthly_budget_limit" {
  description = "Monthly budget limit in USD for cost alerts"
  type        = number
  default     = 100
  
  validation {
    condition     = var.monthly_budget_limit > 0
    error_message = "Monthly budget limit must be greater than 0."
  }
}

# Tags Configuration
variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default = {
    Project     = "SMS Compliance Automation"
    ManagedBy   = "Terraform"
    Purpose     = "Recipe Implementation"
    CostCenter  = "IT"
  }
  
  validation {
    condition     = length(var.common_tags) <= 50
    error_message = "Maximum of 50 tags are allowed per resource."
  }
}

# Feature Flags
variable "enable_diagnostic_settings" {
  description = "Enable diagnostic settings for all resources"
  type        = bool
  default     = true
}

variable "enable_private_endpoints" {
  description = "Enable private endpoints for secure connectivity (requires VNet)"
  type        = bool
  default     = false
}

variable "enable_managed_identity" {
  description = "Enable system-assigned managed identity for Function App"
  type        = bool
  default     = true
}

# Development and Testing Configuration
variable "enable_development_features" {
  description = "Enable features for development and testing environments"
  type        = bool
  default     = false
}

variable "allow_public_access" {
  description = "Allow public access to resources (disable for production)"
  type        = bool
  default     = true
  
  validation {
    condition = var.environment != "prod" || var.allow_public_access == false
    error_message = "Public access must be disabled for production environments."
  }
}

# Backup and Recovery Configuration
variable "enable_backup" {
  description = "Enable backup for critical resources"
  type        = bool
  default     = false
}

variable "backup_retention_days" {
  description = "Number of days to retain backups"
  type        = number
  default     = 30
  
  validation {
    condition     = var.backup_retention_days >= 7 && var.backup_retention_days <= 365
    error_message = "Backup retention must be between 7 and 365 days."
  }
}