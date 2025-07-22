# Common variables
variable "location" {
  description = "The Azure region where resources will be created"
  type        = string
  default     = "East US"
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = "rg-pushnotif-demo"
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

variable "tags" {
  description = "Tags to be applied to all resources"
  type        = map(string)
  default = {
    purpose     = "demo"
    environment = "dev"
  }
}

# Notification Hub variables
variable "notification_hub_namespace_name" {
  description = "Name of the Notification Hub namespace"
  type        = string
  default     = ""
}

variable "notification_hub_name" {
  description = "Name of the Notification Hub"
  type        = string
  default     = "nh-multiplatform"
}

variable "notification_hub_sku" {
  description = "SKU for the Notification Hub namespace"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Free", "Basic", "Standard"], var.notification_hub_sku)
    error_message = "SKU must be one of: Free, Basic, Standard."
  }
}

# Azure Spring Apps variables
variable "spring_apps_name" {
  description = "Name of the Azure Spring Apps instance"
  type        = string
  default     = ""
}

variable "spring_apps_sku" {
  description = "SKU for Azure Spring Apps"
  type        = string
  default     = "S0"
  
  validation {
    condition     = contains(["S0", "E0"], var.spring_apps_sku)
    error_message = "SKU must be one of: S0, E0."
  }
}

variable "spring_app_name" {
  description = "Name of the Spring application"
  type        = string
  default     = "notification-api"
}

# Key Vault variables
variable "key_vault_name" {
  description = "Name of the Key Vault"
  type        = string
  default     = ""
}

variable "key_vault_sku" {
  description = "SKU for the Key Vault"
  type        = string
  default     = "standard"
  
  validation {
    condition     = contains(["standard", "premium"], var.key_vault_sku)
    error_message = "SKU must be one of: standard, premium."
  }
}

# Application Insights variables
variable "application_insights_name" {
  description = "Name of the Application Insights instance"
  type        = string
  default     = "ai-pushnotif"
}

variable "application_insights_type" {
  description = "Type of Application Insights instance"
  type        = string
  default     = "web"
  
  validation {
    condition     = contains(["web", "other"], var.application_insights_type)
    error_message = "Type must be one of: web, other."
  }
}

# Log Analytics variables
variable "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  type        = string
  default     = "law-notifications"
}

variable "log_analytics_sku" {
  description = "SKU for the Log Analytics workspace"
  type        = string
  default     = "PerGB2018"
  
  validation {
    condition     = contains(["Free", "PerNode", "PerGB2018", "Standalone"], var.log_analytics_sku)
    error_message = "SKU must be one of: Free, PerNode, PerGB2018, Standalone."
  }
}

# Platform credentials (will be stored securely in Key Vault)
variable "fcm_server_key" {
  description = "Firebase Cloud Messaging server key"
  type        = string
  default     = "your-fcm-server-key"
  sensitive   = true
}

variable "apns_key_id" {
  description = "Apple Push Notification Service key ID"
  type        = string
  default     = "your-apns-key-id"
  sensitive   = true
}

variable "vapid_public_key" {
  description = "VAPID public key for web push notifications"
  type        = string
  default     = "your-vapid-public-key"
  sensitive   = true
}

variable "vapid_private_key" {
  description = "VAPID private key for web push notifications"
  type        = string
  default     = "your-vapid-private-key"
  sensitive   = true
}

# Monitoring and alerting
variable "enable_monitoring" {
  description = "Enable monitoring and alerting"
  type        = bool
  default     = true
}

variable "retention_in_days" {
  description = "Log retention period in days"
  type        = number
  default     = 30
  
  validation {
    condition     = var.retention_in_days >= 30 && var.retention_in_days <= 730
    error_message = "Retention period must be between 30 and 730 days."
  }
}