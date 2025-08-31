# Variables for Real-time Status Notifications with SignalR and Functions
# These variables allow customization of the deployed infrastructure

variable "resource_group_name" {
  description = "The name of the resource group where all resources will be created"
  type        = string
  default     = "rg-signalr-functions"
  
  validation {
    condition     = length(var.resource_group_name) >= 1 && length(var.resource_group_name) <= 90
    error_message = "Resource group name must be between 1 and 90 characters."
  }
}

variable "location" {
  description = "The Azure region where resources will be deployed"
  type        = string
  default     = "East US"
}

variable "signalr_name" {
  description = "The name of the Azure SignalR Service (will have random suffix appended)"
  type        = string
  default     = "signalr"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]*[a-zA-Z0-9]$", var.signalr_name))
    error_message = "SignalR name must start and end with alphanumeric characters and can contain hyphens."
  }
}

variable "function_app_name" {
  description = "The name of the Azure Function App (will have random suffix appended)"
  type        = string
  default     = "func"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]*[a-zA-Z0-9]$", var.function_app_name))
    error_message = "Function App name must start and end with alphanumeric characters and can contain hyphens."
  }
}

variable "storage_account_name" {
  description = "The name of the storage account for the Function App (will have random suffix appended)"
  type        = string
  default     = "storage"
  
  validation {
    condition     = can(regex("^[a-z0-9]+$", var.storage_account_name))
    error_message = "Storage account name must contain only lowercase letters and numbers."
  }
}

variable "signalr_sku_name" {
  description = "The SKU name for the SignalR Service"
  type        = string
  default     = "Free_F1"
  
  validation {
    condition     = contains(["Free_F1", "Standard_S1", "Premium_P1", "Premium_P2"], var.signalr_sku_name)
    error_message = "SignalR SKU must be one of: Free_F1, Standard_S1, Premium_P1, Premium_P2."
  }
}

variable "signalr_capacity" {
  description = "The capacity (number of units) for the SignalR Service"
  type        = number
  default     = 1
  
  validation {
    condition     = var.signalr_capacity >= 1 && var.signalr_capacity <= 1000
    error_message = "SignalR capacity must be between 1 and 1000."
  }
}

variable "function_app_service_plan_sku_name" {
  description = "The SKU name for the Function App Service Plan (Y1 for Consumption plan)"
  type        = string
  default     = "Y1"
  
  validation {
    condition = contains([
      "Y1",         # Consumption plan
      "EP1", "EP2", "EP3", # Elastic Premium plans
      "P1v2", "P2v2", "P3v2", "P1v3", "P2v3", "P3v3" # Premium plans
    ], var.function_app_service_plan_sku_name)
    error_message = "Function App Service Plan SKU must be a valid consumption, elastic premium, or premium plan SKU."
  }
}

variable "node_version" {
  description = "The Node.js version for the Function App"
  type        = string
  default     = "~18"
  
  validation {
    condition     = contains(["~12", "~14", "~16", "~18", "~20", "~22"], var.node_version)
    error_message = "Node version must be one of: ~12, ~14, ~16, ~18, ~20, ~22."
  }
}

variable "functions_extension_version" {
  description = "The Azure Functions runtime version"
  type        = string
  default     = "~4"
  
  validation {
    condition     = contains(["~1", "~2", "~3", "~4"], var.functions_extension_version)
    error_message = "Functions extension version must be one of: ~1, ~2, ~3, ~4."
  }
}

variable "enable_cors_for_all_origins" {
  description = "Whether to enable CORS for all origins (*). Set to false for production environments"
  type        = bool
  default     = true
}

variable "cors_allowed_origins" {
  description = "List of allowed origins for CORS. Used when enable_cors_for_all_origins is false"
  type        = list(string)
  default     = ["https://localhost:3000"]
}

variable "enable_application_insights" {
  description = "Whether to enable Application Insights for monitoring"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Number of days to retain logs in Application Insights"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_retention_days >= 30 && var.log_retention_days <= 730
    error_message = "Log retention days must be between 30 and 730."
  }
}

variable "signalr_service_mode" {
  description = "The service mode for SignalR Service (Classic, Default, or Serverless)"
  type        = string
  default     = "Serverless"
  
  validation {
    condition     = contains(["Classic", "Default", "Serverless"], var.signalr_service_mode)
    error_message = "SignalR service mode must be one of: Classic, Default, Serverless."
  }
}

variable "enable_signalr_logs" {
  description = "Whether to enable SignalR connectivity and messaging logs"
  type        = bool
  default     = true
}

variable "tags" {
  description = "A map of tags to assign to all resources"
  type        = map(string)
  default = {
    purpose     = "recipe"
    environment = "demo"
    recipe      = "realtime-status-notifications"
  }
}