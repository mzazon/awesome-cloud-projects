# Variables for Azure Accessible AI-Powered Customer Service Bot Infrastructure
# This file defines all input variables for the Terraform configuration

# Basic Configuration Variables
variable "resource_group_name" {
  description = "Name of the Azure Resource Group to create all resources in"
  type        = string
  default     = "rg-accessible-bot"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9._-]{0,89}[a-zA-Z0-9]$", var.resource_group_name))
    error_message = "Resource group name must be 1-90 characters, start and end with alphanumeric, and contain only alphanumeric, hyphens, underscores, and periods."
  }
}

variable "location" {
  description = "Azure region where resources will be deployed"
  type        = string
  default     = "eastus"
  
  validation {
    condition = contains([
      "eastus", "eastus2", "westus", "westus2", "westus3", "centralus", "northcentralus", "southcentralus",
      "westcentralus", "canadacentral", "canadaeast", "brazilsouth", "northeurope", "westeurope",
      "francesouth", "francecentral", "uksouth", "ukwest", "switzerlandnorth", "switzerlandwest",
      "germanynorth", "germanywestcentral", "norwayeast", "norwaywest", "southafricanorth",
      "southafricawest", "uaenorth", "uaecentral", "australiaeast", "australiasoutheast",
      "australiacentral", "australiacentral2", "eastasia", "southeastasia", "japaneast",
      "japanwest", "koreacentral", "koreasouth", "southindia", "westindia", "centralindia"
    ], var.location)
    error_message = "Location must be a valid Azure region."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9]{0,9}$", var.environment))
    error_message = "Environment must be 1-10 characters, start with a letter, and contain only alphanumeric characters."
  }
}

# Bot Framework Configuration
variable "bot_name" {
  description = "Name for the Azure Bot Framework registration"
  type        = string
  default     = "accessible-customer-bot"
  
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]{0,63}$", var.bot_name))
    error_message = "Bot name must be 1-64 characters, start with a letter, and contain only alphanumeric characters and hyphens."
  }
}

variable "bot_display_name" {
  description = "Display name for the Azure Bot Framework registration"
  type        = string
  default     = "Accessible Customer Service Bot"
  
  validation {
    condition     = length(var.bot_display_name) >= 1 && length(var.bot_display_name) <= 100
    error_message = "Bot display name must be between 1 and 100 characters."
  }
}

variable "bot_description" {
  description = "Description for the Azure Bot Framework registration"
  type        = string
  default     = "AI-powered customer service bot with accessibility features using Azure Immersive Reader"
  
  validation {
    condition     = length(var.bot_description) <= 500
    error_message = "Bot description must be 500 characters or less."
  }
}

# App Service Configuration
variable "app_service_plan_sku" {
  description = "SKU for the App Service Plan hosting the bot application"
  type        = string
  default     = "B1"
  
  validation {
    condition = contains([
      "F1", "D1", "B1", "B2", "B3", "S1", "S2", "S3", "P1", "P2", "P3", "P1v2", "P2v2", "P3v2", "P1v3", "P2v3", "P3v3"
    ], var.app_service_plan_sku)
    error_message = "App Service Plan SKU must be a valid Azure App Service Plan tier."
  }
}

variable "app_service_plan_kind" {
  description = "Kind of App Service Plan (Windows or Linux)"
  type        = string
  default     = "Linux"
  
  validation {
    condition     = contains(["Windows", "Linux"], var.app_service_plan_kind)
    error_message = "App Service Plan kind must be either 'Windows' or 'Linux'."
  }
}

variable "node_version" {
  description = "Node.js version for the App Service"
  type        = string
  default     = "18-lts"
  
  validation {
    condition     = can(regex("^[0-9]+-lts$", var.node_version))
    error_message = "Node version must be in format 'XX-lts' (e.g., '18-lts')."
  }
}

# Cognitive Services Configuration
variable "cognitive_services_sku" {
  description = "SKU for Cognitive Services resources (Immersive Reader and LUIS)"
  type        = string
  default     = "S0"
  
  validation {
    condition     = contains(["F0", "S0", "S1", "S2", "S3", "S4"], var.cognitive_services_sku)
    error_message = "Cognitive Services SKU must be a valid pricing tier."
  }
}

variable "luis_authoring_sku" {
  description = "SKU for LUIS authoring resource"
  type        = string
  default     = "F0"
  
  validation {
    condition     = contains(["F0", "S0"], var.luis_authoring_sku)
    error_message = "LUIS authoring SKU must be either 'F0' (free) or 'S0' (standard)."
  }
}

# Storage Configuration
variable "storage_account_tier" {
  description = "Performance tier for the storage account"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be either 'Standard' or 'Premium'."
  }
}

variable "storage_account_replication_type" {
  description = "Replication type for the storage account"
  type        = string
  default     = "LRS"
  
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_account_replication_type)
    error_message = "Storage account replication type must be a valid Azure storage replication option."
  }
}

# Key Vault Configuration
variable "key_vault_sku" {
  description = "SKU for the Key Vault"
  type        = string
  default     = "standard"
  
  validation {
    condition     = contains(["standard", "premium"], var.key_vault_sku)
    error_message = "Key Vault SKU must be either 'standard' or 'premium'."
  }
}

variable "key_vault_soft_delete_retention_days" {
  description = "Number of days to retain soft-deleted Key Vault items"
  type        = number
  default     = 7
  
  validation {
    condition     = var.key_vault_soft_delete_retention_days >= 7 && var.key_vault_soft_delete_retention_days <= 90
    error_message = "Key Vault soft delete retention days must be between 7 and 90."
  }
}

# Application Insights Configuration
variable "application_insights_type" {
  description = "Application type for Application Insights"
  type        = string
  default     = "web"
  
  validation {
    condition     = contains(["web", "java", "MobileCenter", "Node.JS", "other"], var.application_insights_type)
    error_message = "Application Insights type must be a valid application type."
  }
}

variable "application_insights_retention_days" {
  description = "Data retention period in days for Application Insights"
  type        = number
  default     = 30
  
  validation {
    condition     = contains([30, 60, 90, 120, 180, 270, 365, 550, 730], var.application_insights_retention_days)
    error_message = "Application Insights retention days must be one of: 30, 60, 90, 120, 180, 270, 365, 550, or 730."
  }
}

# Security Configuration
variable "enable_rbac_authorization" {
  description = "Enable RBAC authorization for Key Vault (recommended for production)"
  type        = bool
  default     = false
}

variable "enable_public_network_access" {
  description = "Enable public network access to Key Vault"
  type        = bool
  default     = true
}

variable "allowed_ip_addresses" {
  description = "List of IP addresses allowed to access Key Vault (empty list allows all)"
  type        = list(string)
  default     = []
  
  validation {
    condition = alltrue([
      for ip in var.allowed_ip_addresses : can(regex("^(?:[0-9]{1,3}\\.){3}[0-9]{1,3}(?:/[0-9]{1,2})?$", ip))
    ])
    error_message = "All IP addresses must be valid IPv4 addresses or CIDR blocks."
  }
}

# Resource Naming Configuration
variable "resource_name_prefix" {
  description = "Prefix for resource names to ensure uniqueness"
  type        = string
  default     = ""
  
  validation {
    condition     = var.resource_name_prefix == "" || can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]*$", var.resource_name_prefix))
    error_message = "Resource name prefix must be empty or start with alphanumeric character and contain only alphanumeric characters and hyphens."
  }
}

variable "use_random_suffix" {
  description = "Add random suffix to resource names to ensure global uniqueness"
  type        = bool
  default     = true
}

# Tagging Configuration
variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default = {
    Purpose     = "accessibility-demo"
    Environment = "development"
    Compliance  = "accessibility"
    Service     = "customer-service-bot"
  }
}

variable "additional_tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}

# Feature Flags
variable "enable_diagnostic_logs" {
  description = "Enable diagnostic logging for supported resources"
  type        = bool
  default     = true
}

variable "enable_backup" {
  description = "Enable backup for supported resources"
  type        = bool
  default     = false
}

variable "enable_monitoring_alerts" {
  description = "Enable monitoring alerts for the bot service"
  type        = bool
  default     = true
}

# Advanced Configuration
variable "custom_domain_name" {
  description = "Custom domain name for the bot service (optional)"
  type        = string
  default     = ""
  
  validation {
    condition = var.custom_domain_name == "" || can(regex("^[a-zA-Z0-9][a-zA-Z0-9.-]*[a-zA-Z0-9]$", var.custom_domain_name))
    error_message = "Custom domain name must be a valid domain name or empty."
  }
}

variable "ssl_certificate_thumbprint" {
  description = "SSL certificate thumbprint for custom domain (required if custom_domain_name is provided)"
  type        = string
  default     = ""
  
  validation {
    condition = var.custom_domain_name == "" || (var.custom_domain_name != "" && var.ssl_certificate_thumbprint != "")
    error_message = "SSL certificate thumbprint is required when custom domain name is provided."
  }
}