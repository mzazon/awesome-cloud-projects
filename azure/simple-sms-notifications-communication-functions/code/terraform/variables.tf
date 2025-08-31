# Variables for SMS notifications with Azure Communication Services and Functions
# This file defines all configurable parameters for the infrastructure deployment

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
      "Switzerland North", "Norway East", "Sweden Central", "Australia East",
      "Australia Southeast", "Southeast Asia", "East Asia", "Japan East",
      "Japan West", "Korea Central", "India Central", "South Africa North"
    ], var.location)
    error_message = "The location must be a valid Azure region where Communication Services are supported."
  }
}

variable "environment" {
  description = "The deployment environment (e.g., dev, test, prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "test", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, test, staging, prod."
  }
}

variable "project_name" {
  description = "The name of the project, used as a prefix for resource naming"
  type        = string
  default     = "sms-notifications"

  validation {
    condition     = can(regex("^[a-z0-9-]{3,20}$", var.project_name))
    error_message = "Project name must be 3-20 characters long and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "communication_data_location" {
  description = "The data residency location for Azure Communication Services"
  type        = string
  default     = "United States"

  validation {
    condition = contains([
      "United States", "Europe", "Asia Pacific", "Australia", "United Kingdom",
      "France", "Germany", "Switzerland", "Norway", "UAE", "India", "Japan",
      "Korea", "Canada", "Brazil", "Africa"
    ], var.communication_data_location)
    error_message = "Communication data location must be a valid Azure Communication Services data residency region."
  }
}

variable "function_runtime_version" {
  description = "The Azure Functions runtime version"
  type        = string
  default     = "~4"

  validation {
    condition     = contains(["~1", "~2", "~3", "~4"], var.function_runtime_version)
    error_message = "Function runtime version must be ~1, ~2, ~3, or ~4."
  }
}

variable "node_version" {
  description = "The Node.js version for the Function App"
  type        = string
  default     = "20"

  validation {
    condition     = contains(["12", "14", "16", "18", "20", "22"], var.node_version)
    error_message = "Node version must be one of: 12, 14, 16, 18, 20, 22."
  }
}

variable "storage_account_replication_type" {
  description = "The replication type for the storage account"
  type        = string
  default     = "LRS"

  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_account_replication_type)
    error_message = "Storage replication type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

variable "service_plan_sku_name" {
  description = "The SKU name for the App Service Plan (use Y1 for Consumption plan)"
  type        = string
  default     = "Y1"

  validation {
    condition = contains([
      "Y1", "EP1", "EP2", "EP3", "P1v2", "P2v2", "P3v2", "P1v3", "P2v3", "P3v3",
      "S1", "S2", "S3", "B1", "B2", "B3", "F1", "D1", "SHARED"
    ], var.service_plan_sku_name)
    error_message = "Service plan SKU must be a valid Azure App Service Plan SKU."
  }
}

variable "enable_https_only" {
  description = "Whether to enforce HTTPS-only access for the Function App"
  type        = bool
  default     = true
}

variable "enable_builtin_logging" {
  description = "Whether to enable built-in logging for the Function App"
  type        = bool
  default     = true
}

variable "daily_memory_time_quota" {
  description = "The daily memory time quota in GB-seconds for Consumption plan (0 = no limit)"
  type        = number
  default     = 0

  validation {
    condition     = var.daily_memory_time_quota >= 0
    error_message = "Daily memory time quota must be 0 or greater."
  }
}

variable "tags" {
  description = "A map of tags to assign to all resources"
  type        = map(string)
  default = {
    Environment = "Development"
    Project     = "SMS Notifications"
    ManagedBy   = "Terraform"
  }
}

variable "enable_application_insights" {
  description = "Whether to create and configure Application Insights for monitoring"
  type        = bool
  default     = true
}

variable "application_insights_retention_days" {
  description = "The retention period in days for Application Insights data"
  type        = number
  default     = 90

  validation {
    condition     = contains([30, 60, 90, 120, 180, 270, 365, 550, 730], var.application_insights_retention_days)
    error_message = "Application Insights retention must be one of: 30, 60, 90, 120, 180, 270, 365, 550, 730 days."
  }
}

variable "minimum_tls_version" {
  description = "The minimum TLS version for the Function App"
  type        = string
  default     = "1.2"

  validation {
    condition     = contains(["1.0", "1.1", "1.2", "1.3"], var.minimum_tls_version)
    error_message = "Minimum TLS version must be 1.0, 1.1, 1.2, or 1.3."
  }
}

variable "cors_allowed_origins" {
  description = "List of allowed origins for CORS configuration"
  type        = list(string)
  default     = ["*"]
}

variable "ip_restrictions" {
  description = "List of IP restrictions for the Function App"
  type = list(object({
    name       = string
    ip_address = string
    priority   = number
    action     = string
  }))
  default = []
}