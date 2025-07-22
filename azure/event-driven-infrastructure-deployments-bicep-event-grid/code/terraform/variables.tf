# Core configuration variables
variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "demo"
  
  validation {
    condition     = contains(["dev", "staging", "prod", "demo"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod, demo."
  }
}

variable "location" {
  description = "Azure region for all resources"
  type        = string
  default     = "East US"
  
  validation {
    condition = can(regex("^[A-Za-z0-9\\s]+$", var.location))
    error_message = "Location must be a valid Azure region name."
  }
}

variable "resource_group_name" {
  description = "Name of the resource group (will be created if it doesn't exist)"
  type        = string
  default     = ""
}

# Naming and tagging variables
variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "bicep-eventgrid"
  
  validation {
    condition     = can(regex("^[a-z0-9\\-]{3,20}$", var.project_name))
    error_message = "Project name must be 3-20 characters, lowercase letters, numbers, and hyphens only."
  }
}

variable "tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default = {
    Purpose     = "recipe"
    Environment = "demo"
    ManagedBy   = "terraform"
  }
}

# Storage configuration
variable "storage_account_tier" {
  description = "Performance tier for storage accounts"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be either Standard or Premium."
  }
}

variable "storage_replication_type" {
  description = "Replication type for storage accounts"
  type        = string
  default     = "LRS"
  
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_replication_type)
    error_message = "Replication type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

# Event Grid configuration
variable "event_grid_topic_input_schema" {
  description = "Schema for Event Grid topic events"
  type        = string
  default     = "EventGridSchema"
  
  validation {
    condition     = contains(["EventGridSchema", "CustomInputSchema", "CloudEventSchemaV1_0"], var.event_grid_topic_input_schema)
    error_message = "Input schema must be one of: EventGridSchema, CustomInputSchema, CloudEventSchemaV1_0."
  }
}

# Container Registry configuration
variable "container_registry_sku" {
  description = "SKU for Azure Container Registry"
  type        = string
  default     = "Basic"
  
  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.container_registry_sku)
    error_message = "Container Registry SKU must be one of: Basic, Standard, Premium."
  }
}

variable "container_registry_admin_enabled" {
  description = "Enable admin user for Container Registry"
  type        = bool
  default     = true
}

# Key Vault configuration
variable "key_vault_sku" {
  description = "SKU for Azure Key Vault"
  type        = string
  default     = "standard"
  
  validation {
    condition     = contains(["standard", "premium"], var.key_vault_sku)
    error_message = "Key Vault SKU must be either standard or premium."
  }
}

variable "key_vault_enabled_for_deployment" {
  description = "Enable Key Vault for Azure Resource Manager deployment"
  type        = bool
  default     = true
}

variable "key_vault_enabled_for_template_deployment" {
  description = "Enable Key Vault for Azure Resource Manager template deployment"
  type        = bool
  default     = true
}

variable "key_vault_purge_protection_enabled" {
  description = "Enable purge protection for Key Vault"
  type        = bool
  default     = false
}

# Function App configuration
variable "function_app_service_plan_sku" {
  description = "SKU for Function App Service Plan"
  type        = string
  default     = "Y1"
  
  validation {
    condition     = contains(["Y1", "EP1", "EP2", "EP3", "P1v2", "P2v2", "P3v2"], var.function_app_service_plan_sku)
    error_message = "Function App SKU must be a valid consumption or premium plan SKU."
  }
}

variable "function_app_runtime_version" {
  description = "Runtime version for Function App"
  type        = string
  default     = "~4"
}

variable "function_app_dotnet_version" {
  description = ".NET version for Function App"
  type        = string
  default     = "6"
  
  validation {
    condition     = contains(["6", "7", "8"], var.function_app_dotnet_version)
    error_message = ".NET version must be one of: 6, 7, 8."
  }
}

# Log Analytics configuration
variable "log_analytics_sku" {
  description = "SKU for Log Analytics workspace"
  type        = string
  default     = "PerGB2018"
  
  validation {
    condition     = contains(["Free", "PerNode", "PerGB2018", "Standalone", "Standard", "Premium"], var.log_analytics_sku)
    error_message = "Log Analytics SKU must be a valid pricing tier."
  }
}

variable "log_analytics_retention_days" {
  description = "Retention period in days for Log Analytics"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_analytics_retention_days >= 30 && var.log_analytics_retention_days <= 730
    error_message = "Log Analytics retention must be between 30 and 730 days."
  }
}

# Application Insights configuration
variable "application_insights_type" {
  description = "Application type for Application Insights"
  type        = string
  default     = "web"
  
  validation {
    condition     = contains(["web", "other"], var.application_insights_type)
    error_message = "Application Insights type must be either web or other."
  }
}

# Security and access configuration
variable "allowed_ip_ranges" {
  description = "List of IP ranges allowed to access resources (CIDR format)"
  type        = list(string)
  default     = []
}

variable "enable_private_endpoints" {
  description = "Enable private endpoints for supported services"
  type        = bool
  default     = false
}

# Deployment configuration
variable "deploy_sample_bicep_template" {
  description = "Deploy sample Bicep template to storage"
  type        = bool
  default     = true
}

variable "create_deployment_container" {
  description = "Build and push deployment container to ACR"
  type        = bool
  default     = true
}