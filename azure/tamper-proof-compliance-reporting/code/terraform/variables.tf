# General Configuration Variables
variable "resource_group_name" {
  description = "Name of the Azure Resource Group"
  type        = string
  default     = "rg-compliance"
}

variable "location" {
  description = "Azure region for deploying resources"
  type        = string
  default     = "East US"
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "Central US",
      "North Europe", "West Europe", "UK South", "UK West",
      "Southeast Asia", "East Asia", "Australia East", "Australia Southeast"
    ], var.location)
    error_message = "Location must be a valid Azure region that supports Confidential Ledger."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "demo"
  validation {
    condition     = can(regex("^(dev|staging|prod|demo)$", var.environment))
    error_message = "Environment must be dev, staging, prod, or demo."
  }
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "compliance"
  validation {
    condition     = can(regex("^[a-z0-9-]{3,15}$", var.project_name))
    error_message = "Project name must be 3-15 characters, lowercase letters, numbers, and hyphens only."
  }
}

# Confidential Ledger Configuration
variable "confidential_ledger_name" {
  description = "Name of the Azure Confidential Ledger instance"
  type        = string
  default     = ""
}

variable "ledger_type" {
  description = "Type of Confidential Ledger (Private or Public)"
  type        = string
  default     = "Private"
  validation {
    condition     = contains(["Private", "Public"], var.ledger_type)
    error_message = "Ledger type must be either Private or Public."
  }
}

# Storage Account Configuration
variable "storage_account_name" {
  description = "Name of the storage account for compliance reports"
  type        = string
  default     = ""
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

variable "storage_replication_type" {
  description = "Storage account replication type"
  type        = string
  default     = "LRS"
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_replication_type)
    error_message = "Invalid storage replication type."
  }
}

# Logic App Configuration
variable "logic_app_name" {
  description = "Name of the Logic App for compliance automation"
  type        = string
  default     = ""
}

# Log Analytics Configuration
variable "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  type        = string
  default     = ""
}

variable "log_analytics_sku" {
  description = "SKU for Log Analytics workspace"
  type        = string
  default     = "PerGB2018"
  validation {
    condition     = contains(["Free", "PerNode", "PerGB2018", "Standalone", "Premium"], var.log_analytics_sku)
    error_message = "Invalid Log Analytics SKU."
  }
}

variable "log_retention_days" {
  description = "Number of days to retain logs"
  type        = number
  default     = 30
  validation {
    condition     = var.log_retention_days >= 7 && var.log_retention_days <= 730
    error_message = "Log retention must be between 7 and 730 days."
  }
}

# Monitoring and Alerting Configuration
variable "action_group_name" {
  description = "Name of the action group for alerts"
  type        = string
  default     = "ag-compliance"
}

variable "action_group_short_name" {
  description = "Short name for the action group (max 12 characters)"
  type        = string
  default     = "compliance"
  validation {
    condition     = can(regex("^[a-zA-Z0-9]{1,12}$", var.action_group_short_name))
    error_message = "Action group short name must be 1-12 alphanumeric characters."
  }
}

# Alert Rule Configuration
variable "cpu_threshold" {
  description = "CPU threshold percentage for compliance alerts"
  type        = number
  default     = 90
  validation {
    condition     = var.cpu_threshold > 0 && var.cpu_threshold <= 100
    error_message = "CPU threshold must be between 1 and 100."
  }
}

variable "alert_window_size" {
  description = "Time window for alert evaluation (in minutes)"
  type        = string
  default     = "PT5M"
  validation {
    condition     = can(regex("^PT[0-9]+M$", var.alert_window_size))
    error_message = "Alert window size must be in ISO 8601 duration format (e.g., PT5M for 5 minutes)."
  }
}

variable "alert_frequency" {
  description = "Alert evaluation frequency (in minutes)"
  type        = string
  default     = "PT1M"
  validation {
    condition     = can(regex("^PT[0-9]+M$", var.alert_frequency))
    error_message = "Alert frequency must be in ISO 8601 duration format (e.g., PT1M for 1 minute)."
  }
}

# Security Configuration
variable "enable_https_only" {
  description = "Enable HTTPS-only traffic for storage account"
  type        = bool
  default     = true
}

variable "minimum_tls_version" {
  description = "Minimum TLS version for storage account"
  type        = string
  default     = "TLS1_2"
  validation {
    condition     = contains(["TLS1_0", "TLS1_1", "TLS1_2"], var.minimum_tls_version)
    error_message = "Minimum TLS version must be TLS1_0, TLS1_1, or TLS1_2."
  }
}

variable "enable_blob_versioning" {
  description = "Enable blob versioning for audit trail"
  type        = bool
  default     = true
}

variable "enable_blob_soft_delete" {
  description = "Enable blob soft delete for data protection"
  type        = bool
  default     = true
}

variable "blob_soft_delete_retention_days" {
  description = "Number of days to retain soft-deleted blobs"
  type        = number
  default     = 7
  validation {
    condition     = var.blob_soft_delete_retention_days >= 1 && var.blob_soft_delete_retention_days <= 365
    error_message = "Blob soft delete retention must be between 1 and 365 days."
  }
}

# Compliance Configuration
variable "compliance_container_name" {
  description = "Name of the container for compliance reports"
  type        = string
  default     = "compliance-reports"
  validation {
    condition     = can(regex("^[a-z0-9-]{3,63}$", var.compliance_container_name))
    error_message = "Container name must be 3-63 characters, lowercase letters, numbers, and hyphens only."
  }
}

# Tagging Configuration
variable "tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default = {
    Purpose     = "compliance"
    Environment = "demo"
    CreatedBy   = "terraform"
  }
}

variable "additional_tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}