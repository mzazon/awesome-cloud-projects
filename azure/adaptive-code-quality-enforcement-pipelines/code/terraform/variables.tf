# Core configuration variables
variable "location" {
  description = "Azure region for resource deployment"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "North Central US", "South Central US", "West Central US",
      "Canada Central", "Canada East", "Brazil South", "UK South", "UK West",
      "West Europe", "North Europe", "France Central", "Germany West Central",
      "Switzerland North", "Norway East", "Sweden Central", "Australia East",
      "Australia Southeast", "East Asia", "Southeast Asia", "Japan East",
      "Japan West", "Korea Central", "India Central", "UAE North"
    ], var.location)
    error_message = "Location must be a valid Azure region."
  }
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = "rg-code-quality-pipeline"
}

variable "project_name" {
  description = "Name of the project (used for resource naming)"
  type        = string
  default     = "quality-pipeline"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.project_name))
    error_message = "Project name must contain only alphanumeric characters and hyphens."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "demo"
  
  validation {
    condition     = contains(["dev", "staging", "prod", "demo"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod, demo."
  }
}

# Application Insights configuration
variable "application_insights_type" {
  description = "Application type for Application Insights"
  type        = string
  default     = "web"
  
  validation {
    condition     = contains(["web", "other"], var.application_insights_type)
    error_message = "Application Insights type must be 'web' or 'other'."
  }
}

variable "application_insights_retention_days" {
  description = "Data retention period in days for Application Insights"
  type        = number
  default     = 90
  
  validation {
    condition     = var.application_insights_retention_days >= 30 && var.application_insights_retention_days <= 730
    error_message = "Retention days must be between 30 and 730."
  }
}

# Logic App configuration
variable "logic_app_state" {
  description = "State of the Logic App workflow"
  type        = string
  default     = "Enabled"
  
  validation {
    condition     = contains(["Enabled", "Disabled"], var.logic_app_state)
    error_message = "Logic App state must be 'Enabled' or 'Disabled'."
  }
}

variable "quality_threshold" {
  description = "Quality score threshold for pipeline decisions"
  type        = number
  default     = 80
  
  validation {
    condition     = var.quality_threshold >= 0 && var.quality_threshold <= 100
    error_message = "Quality threshold must be between 0 and 100."
  }
}

# Storage account configuration
variable "storage_account_tier" {
  description = "Storage account tier"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be 'Standard' or 'Premium'."
  }
}

variable "storage_account_replication_type" {
  description = "Storage account replication type"
  type        = string
  default     = "LRS"
  
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_account_replication_type)
    error_message = "Storage account replication type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

# Azure DevOps configuration
variable "devops_organization_name" {
  description = "Azure DevOps organization name"
  type        = string
  default     = "your-devops-organization"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.devops_organization_name))
    error_message = "DevOps organization name must contain only alphanumeric characters and hyphens."
  }
}

variable "devops_project_name" {
  description = "Azure DevOps project name"
  type        = string
  default     = "quality-pipeline-demo"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-\\s]+$", var.devops_project_name))
    error_message = "DevOps project name must contain only alphanumeric characters, hyphens, and spaces."
  }
}

variable "devops_project_visibility" {
  description = "Azure DevOps project visibility"
  type        = string
  default     = "private"
  
  validation {
    condition     = contains(["private", "public"], var.devops_project_visibility)
    error_message = "DevOps project visibility must be 'private' or 'public'."
  }
}

# Tagging configuration
variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Purpose     = "recipe"
    Environment = "demo"
    ManagedBy   = "terraform"
    Recipe      = "orchestrating-intelligent-code-quality-pipelines"
  }
}

# Monitoring and alerting configuration
variable "enable_monitoring" {
  description = "Enable monitoring and alerting"
  type        = bool
  default     = true
}

variable "alert_email" {
  description = "Email address for monitoring alerts"
  type        = string
  default     = "admin@example.com"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.alert_email))
    error_message = "Alert email must be a valid email address."
  }
}

# Security configuration
variable "enable_https_only" {
  description = "Enable HTTPS-only for web applications"
  type        = bool
  default     = true
}

variable "min_tls_version" {
  description = "Minimum TLS version for secure connections"
  type        = string
  default     = "1.2"
  
  validation {
    condition     = contains(["1.0", "1.1", "1.2", "1.3"], var.min_tls_version)
    error_message = "TLS version must be one of: 1.0, 1.1, 1.2, 1.3."
  }
}

# Cost optimization configuration
variable "enable_auto_scaling" {
  description = "Enable auto-scaling for applicable resources"
  type        = bool
  default     = true
}

variable "backup_retention_days" {
  description = "Number of days to retain backups"
  type        = number
  default     = 30
  
  validation {
    condition     = var.backup_retention_days >= 1 && var.backup_retention_days <= 365
    error_message = "Backup retention days must be between 1 and 365."
  }
}