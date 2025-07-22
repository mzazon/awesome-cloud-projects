# Core infrastructure variables
variable "resource_group_name" {
  description = "Name of the resource group for automation infrastructure"
  type        = string
  default     = "rg-automation-demo"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-_.()]+$", var.resource_group_name))
    error_message = "Resource group name must contain only alphanumeric characters, hyphens, underscores, periods, and parentheses."
  }
}

variable "target_resource_group_name" {
  description = "Name of the target resource group for deployments"
  type        = string
  default     = "rg-deployed-infrastructure"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-_.()]+$", var.target_resource_group_name))
    error_message = "Target resource group name must contain only alphanumeric characters, hyphens, underscores, periods, and parentheses."
  }
}

variable "location" {
  description = "Azure region for resource deployment"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "South Central US", "North Central US", "West Central US",
      "Canada Central", "Canada East", "Brazil South", "UK South", "UK West",
      "West Europe", "North Europe", "France Central", "Germany West Central",
      "Norway East", "Switzerland North", "UAE North", "South Africa North",
      "Australia East", "Australia Southeast", "Central India", "South India",
      "Japan East", "Japan West", "Korea Central", "Southeast Asia", "East Asia"
    ], var.location)
    error_message = "Location must be a valid Azure region."
  }
}

# Automation Account configuration
variable "automation_account_name" {
  description = "Name of the Azure Automation Account"
  type        = string
  default     = "aa-infra-provisioning"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{6,50}$", var.automation_account_name))
    error_message = "Automation account name must be 6-50 characters long and contain only alphanumeric characters and hyphens."
  }
}

variable "automation_account_sku" {
  description = "SKU for the Azure Automation Account"
  type        = string
  default     = "Basic"
  
  validation {
    condition     = contains(["Basic", "Standard"], var.automation_account_sku)
    error_message = "Automation account SKU must be either 'Basic' or 'Standard'."
  }
}

# Storage Account configuration
variable "storage_account_name_prefix" {
  description = "Prefix for the storage account name (will be appended with random suffix)"
  type        = string
  default     = "stautoarmtemplates"
  
  validation {
    condition     = can(regex("^[a-z0-9]{3,18}$", var.storage_account_name_prefix))
    error_message = "Storage account name prefix must be 3-18 characters long and contain only lowercase letters and numbers."
  }
}

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
    error_message = "Storage account replication type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

variable "storage_file_share_name" {
  description = "Name of the file share for ARM templates"
  type        = string
  default     = "arm-templates"
  
  validation {
    condition     = can(regex("^[a-z0-9-]{3,63}$", var.storage_file_share_name))
    error_message = "File share name must be 3-63 characters long and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "storage_file_share_quota" {
  description = "Quota for the file share in GB"
  type        = number
  default     = 5
  
  validation {
    condition     = var.storage_file_share_quota >= 1 && var.storage_file_share_quota <= 102400
    error_message = "File share quota must be between 1 and 102400 GB."
  }
}

# Log Analytics configuration
variable "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  type        = string
  default     = "law-automation-monitoring"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{4,63}$", var.log_analytics_workspace_name))
    error_message = "Log Analytics workspace name must be 4-63 characters long and contain only alphanumeric characters and hyphens."
  }
}

variable "log_analytics_sku" {
  description = "SKU for the Log Analytics workspace"
  type        = string
  default     = "PerGB2018"
  
  validation {
    condition     = contains(["Free", "Standard", "Premium", "PerNode", "PerGB2018", "Standalone"], var.log_analytics_sku)
    error_message = "Log Analytics SKU must be one of: Free, Standard, Premium, PerNode, PerGB2018, Standalone."
  }
}

variable "log_analytics_retention_days" {
  description = "Data retention period for Log Analytics workspace in days"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_analytics_retention_days >= 7 && var.log_analytics_retention_days <= 730
    error_message = "Log Analytics retention days must be between 7 and 730."
  }
}

# Runbook configuration
variable "runbook_name" {
  description = "Name of the PowerShell runbook"
  type        = string
  default     = "Deploy-Infrastructure"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]{1,64}$", var.runbook_name))
    error_message = "Runbook name must be 1-64 characters long and contain only alphanumeric characters, hyphens, and underscores."
  }
}

variable "runbook_type" {
  description = "Type of the runbook"
  type        = string
  default     = "PowerShell"
  
  validation {
    condition     = contains(["PowerShell", "PowerShellWorkflow", "GraphPowerShell", "GraphPowerShellWorkflow"], var.runbook_type)
    error_message = "Runbook type must be one of: PowerShell, PowerShellWorkflow, GraphPowerShell, GraphPowerShellWorkflow."
  }
}

variable "runbook_description" {
  description = "Description of the runbook"
  type        = string
  default     = "Automated infrastructure deployment using ARM templates with Azure Automation"
}

# PowerShell modules configuration
variable "powershell_modules" {
  description = "List of PowerShell modules to install in the Automation Account"
  type = list(object({
    name    = string
    version = string
  }))
  default = [
    {
      name    = "Az.Accounts"
      version = "latest"
    },
    {
      name    = "Az.Resources"
      version = "latest"
    },
    {
      name    = "Az.Storage"
      version = "latest"
    },
    {
      name    = "Az.Profile"
      version = "latest"
    }
  ]
}

# Role assignments configuration
variable "automation_account_roles" {
  description = "List of roles to assign to the Automation Account managed identity"
  type = list(object({
    role_name = string
    scope     = string
  }))
  default = [
    {
      role_name = "Contributor"
      scope     = "resource_group"
    },
    {
      role_name = "Storage Blob Data Contributor"
      scope     = "storage_account"
    }
  ]
}

# ARM Template configuration
variable "arm_template_storage_account_type" {
  description = "Default storage account type for ARM template deployments"
  type        = string
  default     = "Standard_LRS"
  
  validation {
    condition     = contains(["Standard_LRS", "Standard_GRS", "Standard_ZRS", "Premium_LRS"], var.arm_template_storage_account_type)
    error_message = "ARM template storage account type must be one of: Standard_LRS, Standard_GRS, Standard_ZRS, Premium_LRS."
  }
}

variable "arm_template_environment" {
  description = "Default environment tag for ARM template deployments"
  type        = string
  default     = "demo"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]{1,10}$", var.arm_template_environment))
    error_message = "Environment tag must be 1-10 characters long and contain only alphanumeric characters, hyphens, and underscores."
  }
}

# Common tags
variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default = {
    environment = "demo"
    purpose     = "automation"
    managed_by  = "terraform"
    project     = "infrastructure-automation"
  }
  
  validation {
    condition     = length(var.common_tags) <= 50
    error_message = "Maximum of 50 tags are allowed."
  }
}

# Security configuration
variable "enable_managed_identity" {
  description = "Enable system-assigned managed identity for the Automation Account"
  type        = bool
  default     = true
}

variable "enable_public_network_access" {
  description = "Enable public network access for the Automation Account"
  type        = bool
  default     = true
}

variable "enable_storage_https_only" {
  description = "Force HTTPS only traffic for the storage account"
  type        = bool
  default     = true
}

variable "enable_storage_blob_public_access" {
  description = "Allow public access to storage account blobs"
  type        = bool
  default     = false
}

# Backup and disaster recovery
variable "enable_backup" {
  description = "Enable backup for critical resources"
  type        = bool
  default     = false
}

variable "backup_retention_days" {
  description = "Number of days to retain backups"
  type        = number
  default     = 30
  
  validation {
    condition     = var.backup_retention_days >= 1 && var.backup_retention_days <= 9999
    error_message = "Backup retention days must be between 1 and 9999."
  }
}

# Monitoring and alerting
variable "enable_diagnostics" {
  description = "Enable diagnostic settings for resources"
  type        = bool
  default     = true
}

variable "diagnostic_retention_days" {
  description = "Number of days to retain diagnostic logs"
  type        = number
  default     = 30
  
  validation {
    condition     = var.diagnostic_retention_days >= 1 && var.diagnostic_retention_days <= 365
    error_message = "Diagnostic retention days must be between 1 and 365."
  }
}

# Cost optimization
variable "enable_cost_optimization" {
  description = "Enable cost optimization features"
  type        = bool
  default     = true
}

variable "storage_access_tier" {
  description = "Access tier for the storage account"
  type        = string
  default     = "Hot"
  
  validation {
    condition     = contains(["Hot", "Cool"], var.storage_access_tier)
    error_message = "Storage access tier must be either 'Hot' or 'Cool'."
  }
}