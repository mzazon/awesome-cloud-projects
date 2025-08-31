# Input Variables for Smart Model Selection Infrastructure
# These variables allow customization of the deployment

variable "location" {
  type        = string
  description = "The Azure region where resources will be deployed"
  default     = "eastus2"
  
  validation {
    condition = contains([
      "eastus2", 
      "swedencentral"
    ], var.location)
    error_message = "Location must be eastus2 or swedencentral (Model Router preview regions)."
  }
}

variable "resource_group_name" {
  type        = string
  description = "Name of the resource group to create"
  default     = null
  
  validation {
    condition     = var.resource_group_name == null || can(regex("^[a-zA-Z0-9._-]+$", var.resource_group_name))
    error_message = "Resource group name must contain only alphanumeric characters, periods, underscores, and hyphens."
  }
}

variable "project_name" {
  type        = string
  description = "Project name used as prefix for resource naming"
  default     = "smart-model"
  
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]*$", var.project_name))
    error_message = "Project name must start with a letter and contain only alphanumeric characters and hyphens."
  }
}

variable "environment" {
  type        = string
  description = "Environment name (dev, test, prod)"
  default     = "demo"
  
  validation {
    condition     = contains(["dev", "test", "staging", "prod", "demo"], var.environment)
    error_message = "Environment must be one of: dev, test, staging, prod, demo."
  }
}

variable "ai_services_sku" {
  type        = string
  description = "The SKU for Azure AI Services"
  default     = "S0"
  
  validation {
    condition     = contains(["F0", "S0"], var.ai_services_sku)
    error_message = "AI Services SKU must be F0 (free) or S0 (standard)."
  }
}

variable "storage_account_tier" {
  type        = string
  description = "The performance tier of the storage account"
  default     = "Standard"
  
  validation {
    condition     = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be Standard or Premium."
  }
}

variable "storage_account_replication_type" {
  type        = string
  description = "The replication type for the storage account"
  default     = "LRS"
  
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS"], var.storage_account_replication_type)
    error_message = "Storage replication type must be LRS, GRS, RAGRS, or ZRS."
  }
}

variable "function_app_plan_sku" {
  type        = string
  description = "The SKU for the Function App Service Plan"
  default     = "Y1"
  
  validation {
    condition     = contains(["Y1", "EP1", "EP2", "EP3"], var.function_app_plan_sku)
    error_message = "Function App plan SKU must be Y1 (consumption) or EP1/EP2/EP3 (premium)."
  }
}

variable "model_router_capacity" {
  type        = number
  description = "The capacity (TPM in thousands) for the Model Router deployment"
  default     = 10
  
  validation {
    condition     = var.model_router_capacity >= 1 && var.model_router_capacity <= 1000
    error_message = "Model Router capacity must be between 1 and 1000."
  }
}

variable "enable_application_insights" {
  type        = bool
  description = "Whether to enable Application Insights for monitoring"
  default     = true
}

variable "enable_private_endpoints" {
  type        = bool
  description = "Whether to enable private endpoints for enhanced security"
  default     = false
}

variable "allowed_origins" {
  type        = list(string)
  description = "List of allowed origins for CORS configuration"
  default     = ["*"]
}

variable "function_app_always_on" {
  type        = bool
  description = "Whether to keep the Function App always on (not applicable for consumption plan)"
  default     = false
}

variable "log_retention_days" {
  type        = number
  description = "Number of days to retain logs in Application Insights"
  default     = 30
  
  validation {
    condition     = var.log_retention_days >= 30 && var.log_retention_days <= 730
    error_message = "Log retention days must be between 30 and 730."
  }
}

variable "tags" {
  type        = map(string)
  description = "A map of tags to assign to all resources"
  default = {
    project     = "smart-model-selection"
    environment = "demo"
    purpose     = "ai-routing"
    managed_by  = "terraform"
  }
}

variable "custom_domain_name" {
  type        = string
  description = "Custom domain name for AI services (must be globally unique)"
  default     = null
}

variable "enable_system_assigned_identity" {
  type        = bool
  description = "Whether to enable system-assigned managed identity for Function App"
  default     = true
}

variable "subnet_id" {
  type        = string
  description = "Subnet ID for VNet integration (optional)"
  default     = null
}

variable "enable_backup" {
  type        = bool
  description = "Whether to enable backup for the Function App"
  default     = false
}

variable "backup_retention_days" {
  type        = number
  description = "Number of days to retain backups"
  default     = 7
  
  validation {
    condition     = var.backup_retention_days >= 1 && var.backup_retention_days <= 30
    error_message = "Backup retention days must be between 1 and 30."
  }
}