# Variables for the simple file compression Azure solution
# This file defines all configurable parameters for the infrastructure deployment

# Basic Configuration Variables
variable "project_name" {
  description = "Name of the project used for resource naming"
  type        = string
  default     = "filecompress"
  validation {
    condition     = can(regex("^[a-z0-9]{3,12}$", var.project_name))
    error_message = "Project name must be 3-12 characters, lowercase letters and numbers only."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "location" {
  description = "Azure region for resource deployment"
  type        = string
  default     = "East US"
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "North Central US", "South Central US", "West Central US",
      "Canada Central", "Canada East", "Brazil South", "North Europe", "West Europe",
      "UK South", "UK West", "France Central", "Germany West Central",
      "Switzerland North", "Norway East", "Sweden Central", "Australia East",
      "Australia Southeast", "Southeast Asia", "East Asia", "Japan East",
      "Japan West", "Korea Central", "South India", "Central India", "West India"
    ], var.location)
    error_message = "Location must be a valid Azure region."
  }
}

# Resource Tagging Variables
variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Environment = "dev"
    Purpose     = "recipe"
    Solution    = "file-compression"
    ManagedBy   = "terraform"
  }
}

# Storage Account Configuration
variable "storage_account_tier" {
  description = "Storage account performance tier"
  type        = string
  default     = "Standard"
  validation {
    condition     = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be either Standard or Premium."
  }
}

variable "storage_replication_type" {
  description = "Storage account replication type"
  type        = string
  default     = "LRS"
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_replication_type)
    error_message = "Storage replication type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

variable "storage_access_tier" {
  description = "Default access tier for blob storage"
  type        = string
  default     = "Hot"
  validation {
    condition     = contains(["Hot", "Cool"], var.storage_access_tier)
    error_message = "Storage access tier must be either Hot or Cool."
  }
}

variable "blob_cors_allowed_origins" {
  description = "Allowed origins for CORS on blob storage"
  type        = list(string)
  default     = ["*"]
}

variable "blob_cors_allowed_methods" {
  description = "Allowed HTTP methods for CORS on blob storage"
  type        = list(string)
  default     = ["GET", "POST", "PUT", "DELETE", "HEAD", "OPTIONS"]
}

# Function App Configuration
variable "function_app_service_plan_sku" {
  description = "SKU for the Function App Service Plan (use Y1 for Consumption)"
  type        = string
  default     = "Y1"
  validation {
    condition = contains([
      "Y1",       # Consumption
      "EP1", "EP2", "EP3",  # Elastic Premium
      "P1v2", "P2v2", "P3v2"  # Premium v2
    ], var.function_app_service_plan_sku)
    error_message = "Function App SKU must be a valid Azure Functions SKU."
  }
}

variable "function_app_os_type" {
  description = "Operating system type for Function App"
  type        = string
  default     = "Linux"
  validation {
    condition     = contains(["Windows", "Linux"], var.function_app_os_type)
    error_message = "Function App OS type must be either Windows or Linux."
  }
}

variable "function_runtime" {
  description = "Runtime for the Function App"
  type        = string
  default     = "python"
  validation {
    condition     = contains(["python", "node", "dotnet", "java"], var.function_runtime)
    error_message = "Function runtime must be one of: python, node, dotnet, java."
  }
}

variable "function_runtime_version" {
  description = "Runtime version for the Function App"
  type        = string
  default     = "3.11"
}

variable "functions_extension_version" {
  description = "Azure Functions runtime version"
  type        = string
  default     = "~4"
  validation {
    condition     = contains(["~4", "~3"], var.functions_extension_version)
    error_message = "Functions extension version must be ~4 or ~3."
  }
}

# Application Insights Configuration
variable "application_insights_retention_days" {
  description = "Data retention period for Application Insights in days"
  type        = number
  default     = 30
  validation {
    condition     = var.application_insights_retention_days >= 30 && var.application_insights_retention_days <= 730
    error_message = "Application Insights retention must be between 30 and 730 days."
  }
}

variable "application_insights_sampling_percentage" {
  description = "Sampling percentage for Application Insights telemetry"
  type        = number
  default     = 100
  validation {
    condition     = var.application_insights_sampling_percentage >= 0 && var.application_insights_sampling_percentage <= 100
    error_message = "Application Insights sampling percentage must be between 0 and 100."
  }
}

# Event Grid Configuration
variable "event_grid_event_types" {
  description = "Event types to subscribe to for blob storage events"
  type        = list(string)
  default     = ["Microsoft.Storage.BlobCreated"]
  validation {
    condition = alltrue([
      for event_type in var.event_grid_event_types :
      contains([
        "Microsoft.Storage.BlobCreated",
        "Microsoft.Storage.BlobDeleted",
        "Microsoft.Storage.BlobRenamed"
      ], event_type)
    ])
    error_message = "Event types must be valid Microsoft.Storage event types."
  }
}

variable "event_grid_subject_filter_begins_with" {
  description = "Subject filter for Event Grid subscription (begins with)"
  type        = string
  default     = "/blobServices/default/containers/raw-files/"
}

variable "event_grid_subject_filter_ends_with" {
  description = "Subject filter for Event Grid subscription (ends with)"
  type        = string
  default     = ""
}

# Container Configuration
variable "input_container_name" {
  description = "Name of the input blob container"
  type        = string
  default     = "raw-files"
  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.input_container_name))
    error_message = "Container name must be lowercase, start/end with alphanumeric, and can contain hyphens."
  }
}

variable "output_container_name" {
  description = "Name of the output blob container"
  type        = string
  default     = "compressed-files"
  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.output_container_name))
    error_message = "Container name must be lowercase, start/end with alphanumeric, and can contain hyphens."
  }
}

variable "container_access_type" {
  description = "Access type for blob containers"
  type        = string
  default     = "private"
  validation {
    condition     = contains(["private", "blob", "container"], var.container_access_type)
    error_message = "Container access type must be private, blob, or container."
  }
}

# Security Configuration
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
    error_message = "Minimum TLS version must be TLS1_0, TLS1_1, or TLS1_2."
  }
}

variable "allow_nested_items_to_be_public" {
  description = "Allow nested items to be public in storage account"
  type        = bool
  default     = false
}

# Network Configuration
variable "storage_network_default_action" {
  description = "Default network access rule for storage account"
  type        = string
  default     = "Allow"
  validation {
    condition     = contains(["Allow", "Deny"], var.storage_network_default_action)
    error_message = "Storage network default action must be Allow or Deny."
  }
}

variable "bypass_network_rules" {
  description = "Services that can bypass network rules"
  type        = list(string)
  default     = ["AzureServices", "Logging", "Metrics"]
}

# Function App Configuration
variable "function_app_settings" {
  description = "Additional application settings for the Function App"
  type        = map(string)
  default     = {}
}

variable "enable_builtin_logging" {
  description = "Enable built-in logging for Function App"
  type        = bool
  default     = true
}

# Monitoring and Alerting
variable "enable_monitoring" {
  description = "Enable Application Insights monitoring"
  type        = bool
  default     = true
}

variable "log_analytics_workspace_sku" {
  description = "SKU for Log Analytics workspace"
  type        = string
  default     = "PerGB2018"
  validation {
    condition = contains([
      "Free", "Standalone", "PerNode", "PerGB2018", "Premium"
    ], var.log_analytics_workspace_sku)
    error_message = "Log Analytics workspace SKU must be a valid SKU."
  }
}

variable "log_analytics_retention_days" {
  description = "Data retention period for Log Analytics workspace in days"
  type        = number
  default     = 30
  validation {
    condition     = var.log_analytics_retention_days >= 30 && var.log_analytics_retention_days <= 730
    error_message = "Log Analytics retention must be between 30 and 730 days."
  }
}