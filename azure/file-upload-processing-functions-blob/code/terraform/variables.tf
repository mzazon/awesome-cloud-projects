# Variable definitions for Azure file upload processing infrastructure
# These variables allow customization of the deployment for different environments

variable "project_name" {
  description = "Name of the project used for resource naming"
  type        = string
  default     = "fileprocessing"

  validation {
    condition     = can(regex("^[a-z0-9]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters and numbers."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "demo"

  validation {
    condition     = contains(["dev", "staging", "prod", "demo"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod, demo."
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
      "Switzerland North", "Norway East", "UAE North", "South Africa North",
      "Australia East", "Australia Southeast", "Southeast Asia", "East Asia",
      "Japan East", "Japan West", "Korea Central", "India Central"
    ], var.location)
    error_message = "Location must be a valid Azure region."
  }
}

variable "storage_account_tier" {
  description = "Storage account performance tier (Standard or Premium)"
  type        = string
  default     = "Standard"

  validation {
    condition     = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be either Standard or Premium."
  }
}

variable "storage_replication_type" {
  description = "Storage account replication type (LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS)"
  type        = string
  default     = "LRS"

  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_replication_type)
    error_message = "Storage replication type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

variable "storage_access_tier" {
  description = "Storage account access tier for blob storage (Hot, Cool)"
  type        = string
  default     = "Hot"

  validation {
    condition     = contains(["Hot", "Cool"], var.storage_access_tier)
    error_message = "Storage access tier must be either Hot or Cool."
  }
}

variable "function_app_runtime" {
  description = "Runtime stack for the Azure Function App"
  type        = string
  default     = "node"

  validation {
    condition     = contains(["node", "dotnet", "java", "python", "powershell"], var.function_app_runtime)
    error_message = "Function app runtime must be one of: node, dotnet, java, python, powershell."
  }
}

variable "function_app_runtime_version" {
  description = "Runtime version for the Azure Function App"
  type        = string
  default     = "18"
}

variable "function_app_version" {
  description = "Azure Functions runtime version"
  type        = string
  default     = "~4"

  validation {
    condition     = contains(["~4", "~3"], var.function_app_version)
    error_message = "Function app version must be either ~4 or ~3."
  }
}

variable "blob_container_name" {
  description = "Name of the blob container for file uploads"
  type        = string
  default     = "uploads"

  validation {
    condition     = can(regex("^[a-z0-9](?:[a-z0-9]|(-(?!-))){1,61}[a-z0-9]$", var.blob_container_name))
    error_message = "Container name must be 3-63 characters long, contain only lowercase letters, numbers, and hyphens, and cannot start or end with a hyphen."
  }
}

variable "blob_container_access_type" {
  description = "Access level for the blob container (private, blob, container)"
  type        = string
  default     = "private"

  validation {
    condition     = contains(["private", "blob", "container"], var.blob_container_access_type)
    error_message = "Container access type must be one of: private, blob, container."
  }
}

variable "enable_application_insights" {
  description = "Enable Application Insights for function monitoring"
  type        = bool
  default     = true
}

variable "application_insights_type" {
  description = "Application Insights application type"
  type        = string
  default     = "web"

  validation {
    condition     = contains(["web", "other"], var.application_insights_type)
    error_message = "Application Insights type must be either web or other."
  }
}

variable "retention_in_days" {
  description = "Application Insights data retention in days"
  type        = number
  default     = 30

  validation {
    condition     = var.retention_in_days >= 30 && var.retention_in_days <= 730
    error_message = "Retention period must be between 30 and 730 days."
  }
}

variable "tags" {
  description = "Resource tags to apply to all resources"
  type        = map(string)
  default = {
    Purpose     = "file-processing"
    Environment = "demo"
    ManagedBy   = "terraform"
  }
}

variable "create_resource_group" {
  description = "Whether to create a new resource group or use an existing one"
  type        = bool
  default     = true
}

variable "existing_resource_group_name" {
  description = "Name of existing resource group (required if create_resource_group is false)"
  type        = string
  default     = ""
}

variable "enable_storage_encryption" {
  description = "Enable storage account encryption using Microsoft-managed keys"
  type        = bool
  default     = true
}

variable "enable_https_traffic_only" {
  description = "Force HTTPS traffic only for storage account"
  type        = bool
  default     = true
}

variable "min_tls_version" {
  description = "Minimum TLS version for storage account"
  type        = string
  default     = "TLS1_2"

  validation {
    condition     = contains(["TLS1_0", "TLS1_1", "TLS1_2"], var.min_tls_version)
    error_message = "Minimum TLS version must be one of: TLS1_0, TLS1_1, TLS1_2."
  }
}