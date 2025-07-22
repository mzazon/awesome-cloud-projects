# =============================================================================
# Variables for Azure Deployment Environments Infrastructure
# Self-Service Infrastructure Lifecycle Configuration
# =============================================================================

# =============================================================================
# Core Configuration Variables
# =============================================================================

variable "resource_group_name" {
  description = "Name of the resource group where resources will be created. Leave empty for auto-generated name."
  type        = string
  default     = ""
  
  validation {
    condition     = var.resource_group_name == "" || can(regex("^[a-zA-Z0-9][a-zA-Z0-9._-]*[a-zA-Z0-9]$", var.resource_group_name))
    error_message = "Resource group name must start and end with alphanumeric characters and can contain dots, dashes, and underscores."
  }
}

variable "location" {
  description = "Azure region where resources will be deployed"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "South Central US", "North Central US", "West Central US",
      "Canada Central", "Canada East", "UK South", "UK West",
      "North Europe", "West Europe", "France Central", "Germany West Central",
      "Switzerland North", "Norway East", "Sweden Central",
      "Australia East", "Australia Southeast", "Japan East", "Japan West",
      "Korea Central", "Southeast Asia", "East Asia", "South Africa North",
      "UAE North", "Brazil South", "India Central", "India South"
    ], var.location)
    error_message = "Location must be a valid Azure region."
  }
}

variable "environment" {
  description = "Environment name for resource tagging and configuration"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming and organization"
  type        = string
  default     = "selfservice"
  
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]*$", var.project_name)) && length(var.project_name) <= 10
    error_message = "Project name must start with a letter, contain only letters, numbers, and hyphens, and be 10 characters or less."
  }
}

# =============================================================================
# DevCenter Configuration Variables
# =============================================================================

variable "devcenter_name" {
  description = "Name of the Azure DevCenter instance. Leave empty for auto-generated name."
  type        = string
  default     = ""
  
  validation {
    condition     = var.devcenter_name == "" || (can(regex("^[a-zA-Z][a-zA-Z0-9-]*$", var.devcenter_name)) && length(var.devcenter_name) <= 26)
    error_message = "DevCenter name must start with a letter, contain only letters, numbers, and hyphens, and be 26 characters or less."
  }
}

variable "devcenter_project_name" {
  description = "Name of the DevCenter project. Leave empty for auto-generated name."
  type        = string
  default     = ""
  
  validation {
    condition     = var.devcenter_project_name == "" || (can(regex("^[a-zA-Z][a-zA-Z0-9-]*$", var.devcenter_project_name)) && length(var.devcenter_project_name) <= 63)
    error_message = "DevCenter project name must start with a letter, contain only letters, numbers, and hyphens, and be 63 characters or less."
  }
}

variable "catalog_name" {
  description = "Name of the environment catalog for storing infrastructure templates"
  type        = string
  default     = "catalog-templates"
  
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]*$", var.catalog_name)) && length(var.catalog_name) <= 63
    error_message = "Catalog name must start with a letter, contain only letters, numbers, and hyphens, and be 63 characters or less."
  }
}

# =============================================================================
# Storage Account Configuration Variables
# =============================================================================

variable "storage_account_name" {
  description = "Name of the storage account for templates (must be globally unique). Leave empty for auto-generated name."
  type        = string
  default     = ""
  
  validation {
    condition     = var.storage_account_name == "" || can(regex("^[a-z0-9]{3,24}$", var.storage_account_name))
    error_message = "Storage account name must be 3-24 characters long and contain only lowercase letters and numbers."
  }
}

variable "storage_account_tier" {
  description = "Storage account performance tier"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be either Standard or Premium."
  }
}

variable "storage_account_replication" {
  description = "Storage account replication type"
  type        = string
  default     = "LRS"
  
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_account_replication)
    error_message = "Storage account replication must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

variable "enable_https_traffic_only" {
  description = "Force HTTPS traffic only for storage account"
  type        = bool
  default     = true
}

variable "enable_public_access" {
  description = "Allow public access to storage account blobs"
  type        = bool
  default     = false
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

# =============================================================================
# Environment Configuration Variables
# =============================================================================

variable "environment_types" {
  description = "List of environment types to create with their configurations"
  type = list(object({
    name        = string
    description = string
    tags        = map(string)
  }))
  default = [
    {
      name        = "development"
      description = "Development environment with cost controls and auto-deletion"
      tags = {
        tier         = "development"
        cost-center  = "engineering"
        auto-delete  = "true"
        max-duration = "72h"
      }
    },
    {
      name        = "staging"
      description = "Staging environment with enhanced monitoring and longer retention"
      tags = {
        tier         = "staging"
        cost-center  = "engineering"
        monitoring   = "enhanced"
        auto-delete  = "false"
        max-duration = "168h"
      }
    },
    {
      name        = "production"
      description = "Production environment with full monitoring and no auto-deletion"
      tags = {
        tier         = "production"
        cost-center  = "engineering"
        monitoring   = "full"
        auto-delete  = "false"
        backup       = "enabled"
      }
    }
  ]
  
  validation {
    condition = alltrue([
      for env in var.environment_types : can(regex("^[a-zA-Z][a-zA-Z0-9-]*$", env.name))
    ])
    error_message = "All environment type names must start with a letter and contain only letters, numbers, and hyphens."
  }
}

variable "environment_definitions" {
  description = "List of environment definitions (infrastructure templates) to create"
  type = list(object({
    name         = string
    description  = string
    template_path = string
  }))
  default = [
    {
      name         = "webapp-env"
      description  = "Standard web application environment with Azure App Service"
      template_path = "webapp-environment.json"
    },
    {
      name         = "api-env"
      description  = "API environment with Azure Functions and API Management"
      template_path = "api-environment.json"
    },
    {
      name         = "data-env"
      description  = "Data processing environment with Azure Data Factory"
      template_path = "data-environment.json"
    }
  ]
  
  validation {
    condition = alltrue([
      for def in var.environment_definitions : can(regex("^[a-zA-Z][a-zA-Z0-9-]*$", def.name))
    ])
    error_message = "All environment definition names must start with a letter and contain only letters, numbers, and hyphens."
  }
}

# =============================================================================
# Security and Access Control Variables
# =============================================================================

variable "enable_rbac_assignments" {
  description = "Create RBAC assignments for current user and service principals"
  type        = bool
  default     = true
}

variable "allowed_locations" {
  description = "List of allowed Azure regions for environment deployment"
  type        = list(string)
  default     = ["East US", "East US 2", "West US 2", "Central US"]
  
  validation {
    condition     = length(var.allowed_locations) > 0
    error_message = "At least one allowed location must be specified."
  }
}

# =============================================================================
# Monitoring and Observability Variables
# =============================================================================

variable "enable_monitoring" {
  description = "Enable Azure Monitor integration with Log Analytics and Application Insights"
  type        = bool
  default     = true
}

variable "log_analytics_retention_days" {
  description = "Number of days to retain log data in Log Analytics workspace"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_analytics_retention_days >= 30 && var.log_analytics_retention_days <= 730
    error_message = "Log Analytics retention must be between 30 and 730 days."
  }
}

# =============================================================================
# Cost Management Variables
# =============================================================================

variable "cost_management_budget" {
  description = "Monthly budget limit for cost management (in USD)"
  type        = number
  default     = 500
  
  validation {
    condition     = var.cost_management_budget > 0
    error_message = "Cost management budget must be greater than 0."
  }
}

variable "budget_alert_threshold_actual" {
  description = "Threshold percentage for actual cost budget alerts"
  type        = number
  default     = 80
  
  validation {
    condition     = var.budget_alert_threshold_actual > 0 && var.budget_alert_threshold_actual <= 100
    error_message = "Budget alert threshold must be between 1 and 100 percent."
  }
}

variable "budget_alert_threshold_forecast" {
  description = "Threshold percentage for forecasted cost budget alerts"
  type        = number
  default     = 90
  
  validation {
    condition     = var.budget_alert_threshold_forecast > 0 && var.budget_alert_threshold_forecast <= 100
    error_message = "Budget alert threshold must be between 1 and 100 percent."
  }
}

variable "notification_emails" {
  description = "List of email addresses for budget notifications and alerts"
  type        = list(string)
  default     = []
  
  validation {
    condition = alltrue([
      for email in var.notification_emails : can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", email))
    ])
    error_message = "All notification emails must be valid email addresses."
  }
}

# =============================================================================
# Lifecycle Management Variables
# =============================================================================

variable "auto_delete_environments" {
  description = "Automatically delete environments after specified hours (for development environments)"
  type        = number
  default     = 72
  
  validation {
    condition     = var.auto_delete_environments > 0
    error_message = "Auto delete time must be greater than 0 hours."
  }
}

variable "max_environments_per_user" {
  description = "Maximum number of environments each user can create"
  type        = number
  default     = 5
  
  validation {
    condition     = var.max_environments_per_user > 0 && var.max_environments_per_user <= 10
    error_message = "Maximum environments per user must be between 1 and 10."
  }
}

# =============================================================================
# Tagging Variables
# =============================================================================

variable "tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default = {
    purpose     = "infrastructure-lifecycle"
    managed-by  = "terraform"
    team        = "platform-engineering"
    solution    = "azure-deployment-environments"
  }
}

variable "additional_tags" {
  description = "Additional tags to apply to specific resources"
  type        = map(string)
  default     = {}
}