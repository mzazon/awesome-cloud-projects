# Variables for Azure Sustainability Manager and Power BI Infrastructure
# These variables allow customization of the sustainability dashboard solution

variable "location" {
  description = "Azure region where resources will be deployed"
  type        = string
  default     = "East US"
  
  validation {
    condition = can(regex("^[A-Za-z0-9 ]+$", var.location))
    error_message = "Location must be a valid Azure region name."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "prod"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "organization_name" {
  description = "Organization name for resource naming and tagging"
  type        = string
  default     = "sustainability"
  
  validation {
    condition     = can(regex("^[a-z0-9]+$", var.organization_name))
    error_message = "Organization name must contain only lowercase letters and numbers."
  }
}

variable "resource_group_name" {
  description = "Name of the resource group (will be prefixed with rg-)"
  type        = string
  default     = ""
}

variable "storage_account_tier" {
  description = "Performance tier for storage account"
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

variable "log_analytics_sku" {
  description = "SKU for Log Analytics workspace"
  type        = string
  default     = "PerGB2018"
  
  validation {
    condition     = contains(["Free", "PerNode", "PerGB2018", "Standalone", "Standard", "Premium"], var.log_analytics_sku)
    error_message = "Log Analytics SKU must be one of: Free, PerNode, PerGB2018, Standalone, Standard, Premium."
  }
}

variable "app_service_plan_sku" {
  description = "SKU for App Service Plan used by Function Apps"
  type        = string
  default     = "Y1"
  
  validation {
    condition     = can(regex("^[A-Z][0-9]+$", var.app_service_plan_sku))
    error_message = "App Service Plan SKU must be in format like Y1, B1, S1, P1v2, etc."
  }
}

variable "function_app_runtime" {
  description = "Runtime for Function App"
  type        = string
  default     = "python"
  
  validation {
    condition     = contains(["dotnet", "java", "node", "python", "powershell"], var.function_app_runtime)
    error_message = "Function App runtime must be one of: dotnet, java, node, python, powershell."
  }
}

variable "function_app_runtime_version" {
  description = "Runtime version for Function App"
  type        = string
  default     = "3.11"
}

variable "key_vault_sku" {
  description = "SKU for Key Vault"
  type        = string
  default     = "standard"
  
  validation {
    condition     = contains(["standard", "premium"], var.key_vault_sku)
    error_message = "Key Vault SKU must be either standard or premium."
  }
}

variable "data_factory_location" {
  description = "Location for Data Factory (if different from main location)"
  type        = string
  default     = ""
}

variable "enable_public_access" {
  description = "Enable public access to resources (disable for production)"
  type        = bool
  default     = false
}

variable "enable_monitoring" {
  description = "Enable comprehensive monitoring and alerting"
  type        = bool
  default     = true
}

variable "enable_backup" {
  description = "Enable backup for supported resources"
  type        = bool
  default     = true
}

variable "retention_days" {
  description = "Retention period in days for logs and backups"
  type        = number
  default     = 30
  
  validation {
    condition     = var.retention_days >= 7 && var.retention_days <= 730
    error_message = "Retention days must be between 7 and 730."
  }
}

variable "emissions_calculation_method" {
  description = "Method for calculating emissions (GHG_PROTOCOL, ISO14064, CUSTOM)"
  type        = string
  default     = "GHG_PROTOCOL"
  
  validation {
    condition     = contains(["GHG_PROTOCOL", "ISO14064", "CUSTOM"], var.emissions_calculation_method)
    error_message = "Emissions calculation method must be one of: GHG_PROTOCOL, ISO14064, CUSTOM."
  }
}

variable "emissions_factor_source" {
  description = "Source for emissions factors (EPA, DEFRA, IEA, CUSTOM)"
  type        = string
  default     = "EPA"
  
  validation {
    condition     = contains(["EPA", "DEFRA", "IEA", "CUSTOM"], var.emissions_factor_source)
    error_message = "Emissions factor source must be one of: EPA, DEFRA, IEA, CUSTOM."
  }
}

variable "sustainability_scopes" {
  description = "Sustainability scopes to track (scope1, scope2, scope3)"
  type        = list(string)
  default     = ["scope1", "scope2", "scope3"]
  
  validation {
    condition = alltrue([
      for scope in var.sustainability_scopes : contains(["scope1", "scope2", "scope3"], scope)
    ])
    error_message = "Sustainability scopes must be a list containing only: scope1, scope2, scope3."
  }
}

variable "data_refresh_schedule" {
  description = "Cron expression for automated data refresh schedule"
  type        = string
  default     = "0 6 * * *"  # Daily at 6 AM UTC
}

variable "alert_email_recipients" {
  description = "Email addresses to receive monitoring alerts"
  type        = list(string)
  default     = []
  
  validation {
    condition = alltrue([
      for email in var.alert_email_recipients : can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", email))
    ])
    error_message = "All email addresses must be valid email format."
  }
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}