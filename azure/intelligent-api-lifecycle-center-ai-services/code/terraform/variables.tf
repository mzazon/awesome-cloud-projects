# General Configuration
variable "location" {
  description = "The Azure region where resources will be created"
  type        = string
  default     = "East US"
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "South Central US", "North Central US",
      "West Europe", "North Europe", "UK South", "UK West",
      "Southeast Asia", "East Asia", "Japan East", "Japan West",
      "Australia East", "Australia Southeast", "Canada Central",
      "Canada East", "Brazil South", "South Africa North"
    ], var.location)
    error_message = "Location must be a valid Azure region."
  }
}

variable "resource_group_name" {
  description = "Name of the Azure resource group"
  type        = string
  default     = null
  validation {
    condition     = var.resource_group_name == null || can(regex("^[a-zA-Z0-9._-]+$", var.resource_group_name))
    error_message = "Resource group name must contain only alphanumeric characters, periods, underscores, and hyphens."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "api-lifecycle"
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

# API Center Configuration
variable "api_center_name" {
  description = "Name of the Azure API Center instance"
  type        = string
  default     = null
  validation {
    condition     = var.api_center_name == null || can(regex("^[a-zA-Z0-9-]+$", var.api_center_name))
    error_message = "API Center name must contain only alphanumeric characters and hyphens."
  }
}

variable "api_center_sku" {
  description = "SKU for the API Center (Free or Standard)"
  type        = string
  default     = "Free"
  validation {
    condition     = contains(["Free", "Standard"], var.api_center_sku)
    error_message = "API Center SKU must be either Free or Standard."
  }
}

# Azure OpenAI Configuration
variable "openai_name" {
  description = "Name of the Azure OpenAI service"
  type        = string
  default     = null
  validation {
    condition     = var.openai_name == null || can(regex("^[a-zA-Z0-9-]+$", var.openai_name))
    error_message = "OpenAI service name must contain only alphanumeric characters and hyphens."
  }
}

variable "openai_sku" {
  description = "SKU for the Azure OpenAI service"
  type        = string
  default     = "S0"
  validation {
    condition     = contains(["F0", "S0"], var.openai_sku)
    error_message = "OpenAI SKU must be either F0 (Free) or S0 (Standard)."
  }
}

variable "openai_model_deployments" {
  description = "List of OpenAI model deployments to create"
  type = list(object({
    name         = string
    model_name   = string
    model_version = string
    scale_type   = string
    scale_capacity = optional(number, 1)
  }))
  default = [
    {
      name           = "gpt-4"
      model_name     = "gpt-4"
      model_version  = "0613"
      scale_type     = "Standard"
      scale_capacity = 1
    }
  ]
}

# API Management Configuration
variable "create_api_management" {
  description = "Whether to create an API Management instance"
  type        = bool
  default     = true
}

variable "api_management_name" {
  description = "Name of the Azure API Management instance"
  type        = string
  default     = null
  validation {
    condition     = var.api_management_name == null || can(regex("^[a-zA-Z0-9-]+$", var.api_management_name))
    error_message = "API Management name must contain only alphanumeric characters and hyphens."
  }
}

variable "api_management_sku" {
  description = "SKU for the API Management instance"
  type        = string
  default     = "Consumption"
  validation {
    condition     = contains(["Consumption", "Developer", "Basic", "Standard", "Premium"], var.api_management_sku)
    error_message = "API Management SKU must be one of: Consumption, Developer, Basic, Standard, Premium."
  }
}

variable "api_management_publisher_name" {
  description = "Publisher name for API Management"
  type        = string
  default     = "API Lifecycle Management"
}

variable "api_management_publisher_email" {
  description = "Publisher email for API Management"
  type        = string
  default     = "admin@example.com"
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.api_management_publisher_email))
    error_message = "Publisher email must be a valid email address."
  }
}

# Monitoring Configuration
variable "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  type        = string
  default     = null
  validation {
    condition     = var.log_analytics_workspace_name == null || can(regex("^[a-zA-Z0-9-]+$", var.log_analytics_workspace_name))
    error_message = "Log Analytics workspace name must contain only alphanumeric characters and hyphens."
  }
}

variable "log_analytics_retention_days" {
  description = "Number of days to retain logs in Log Analytics"
  type        = number
  default     = 30
  validation {
    condition     = var.log_analytics_retention_days >= 30 && var.log_analytics_retention_days <= 730
    error_message = "Log Analytics retention days must be between 30 and 730."
  }
}

variable "application_insights_name" {
  description = "Name of the Application Insights instance"
  type        = string
  default     = null
  validation {
    condition     = var.application_insights_name == null || can(regex("^[a-zA-Z0-9-]+$", var.application_insights_name))
    error_message = "Application Insights name must contain only alphanumeric characters and hyphens."
  }
}

# Anomaly Detector Configuration
variable "anomaly_detector_name" {
  description = "Name of the Anomaly Detector service"
  type        = string
  default     = null
  validation {
    condition     = var.anomaly_detector_name == null || can(regex("^[a-zA-Z0-9-]+$", var.anomaly_detector_name))
    error_message = "Anomaly Detector name must contain only alphanumeric characters and hyphens."
  }
}

variable "anomaly_detector_sku" {
  description = "SKU for the Anomaly Detector service"
  type        = string
  default     = "F0"
  validation {
    condition     = contains(["F0", "S0"], var.anomaly_detector_sku)
    error_message = "Anomaly Detector SKU must be either F0 (Free) or S0 (Standard)."
  }
}

# Storage Configuration
variable "storage_account_name" {
  description = "Name of the storage account for portal assets"
  type        = string
  default     = null
  validation {
    condition     = var.storage_account_name == null || can(regex("^[a-z0-9]+$", var.storage_account_name))
    error_message = "Storage account name must contain only lowercase letters and numbers."
  }
}

variable "storage_account_tier" {
  description = "Performance tier of the storage account"
  type        = string
  default     = "Standard"
  validation {
    condition     = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be either Standard or Premium."
  }
}

variable "storage_account_replication_type" {
  description = "Replication type for the storage account"
  type        = string
  default     = "LRS"
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_account_replication_type)
    error_message = "Storage account replication type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

# Logic App Configuration
variable "logic_app_name" {
  description = "Name of the Logic App for automation"
  type        = string
  default     = null
  validation {
    condition     = var.logic_app_name == null || can(regex("^[a-zA-Z0-9-]+$", var.logic_app_name))
    error_message = "Logic App name must contain only alphanumeric characters and hyphens."
  }
}

# Tags Configuration
variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Environment = "dev"
    Project     = "api-lifecycle"
    ManagedBy   = "terraform"
  }
}

# Sample API Configuration
variable "sample_apis" {
  description = "List of sample APIs to register in API Center"
  type = list(object({
    id          = string
    title       = string
    description = string
    type        = string
    versions = list(object({
      id             = string
      title          = string
      lifecycle_stage = string
    }))
  }))
  default = [
    {
      id          = "customer-api"
      title       = "Customer Management API"
      description = "API for managing customer data and operations"
      type        = "REST"
      versions = [
        {
          id              = "v1"
          title           = "Version 1.0"
          lifecycle_stage = "production"
        }
      ]
    },
    {
      id          = "product-api"
      title       = "Product Catalog API"
      description = "API for managing product catalog and inventory"
      type        = "REST"
      versions = [
        {
          id              = "v1"
          title           = "Version 1.0"
          lifecycle_stage = "production"
        },
        {
          id              = "v2"
          title           = "Version 2.0"
          lifecycle_stage = "development"
        }
      ]
    }
  ]
}

# Alert Configuration
variable "enable_alerts" {
  description = "Whether to enable monitoring alerts"
  type        = bool
  default     = true
}

variable "alert_email_receivers" {
  description = "List of email addresses to receive alerts"
  type        = list(string)
  default     = []
  validation {
    condition = alltrue([
      for email in var.alert_email_receivers : can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", email))
    ])
    error_message = "All email addresses must be valid email addresses."
  }
}