# Variables for Azure resource organization with resource groups and tags
# This file defines all configurable parameters for the infrastructure deployment

# Location configuration
variable "location" {
  type        = string
  description = "The Azure region where resources will be created"
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "North Central US", "South Central US", "West Central US",
      "Canada Central", "Canada East", "Brazil South", "UK South", "UK West",
      "West Europe", "North Europe", "France Central", "Germany West Central",
      "Switzerland North", "Norway East", "Sweden Central", "Poland Central",
      "Italy North", "Spain Central", "Australia East", "Australia Southeast",
      "East Asia", "Southeast Asia", "Japan East", "Japan West",
      "Korea Central", "Korea South", "Central India", "South India", "West India"
    ], var.location)
    error_message = "Location must be a valid Azure region."
  }
}

# Project configuration
variable "project_name" {
  type        = string
  description = "Name of the project for resource naming and tagging"
  default     = "resource-organization"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment_prefix" {
  type        = string
  description = "Prefix for environment-specific resource naming"
  default     = "demo"
  
  validation {
    condition     = can(regex("^[a-z0-9]+$", var.environment_prefix))
    error_message = "Environment prefix must contain only lowercase letters and numbers."
  }
}

# Organizational tagging variables
variable "department" {
  type        = string
  description = "Department responsible for the resources"
  default     = "engineering"
}

variable "cost_center_dev" {
  type        = string
  description = "Cost center code for development environment"
  default     = "dev001"
}

variable "cost_center_prod" {
  type        = string
  description = "Cost center code for production environment"
  default     = "prod001"
}

variable "cost_center_shared" {
  type        = string
  description = "Cost center code for shared resources"
  default     = "shared001"
}

variable "owner_dev" {
  type        = string
  description = "Owner team for development resources"
  default     = "devteam"
}

variable "owner_prod" {
  type        = string
  description = "Owner team for production resources"
  default     = "opsTeam"
}

variable "owner_shared" {
  type        = string
  description = "Owner team for shared resources"
  default     = "platformTeam"
}

# Resource configuration variables
variable "storage_account_tier" {
  type        = string
  description = "Storage account performance tier"
  default     = "Standard"
  
  validation {
    condition     = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be either Standard or Premium."
  }
}

variable "storage_replication_type_dev" {
  type        = string
  description = "Storage replication type for development environment"
  default     = "LRS"
  
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_replication_type_dev)
    error_message = "Storage replication type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

variable "storage_replication_type_prod" {
  type        = string
  description = "Storage replication type for production environment"
  default     = "GRS"
  
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_replication_type_prod)
    error_message = "Storage replication type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

variable "app_service_plan_sku_dev" {
  type        = string
  description = "App Service Plan SKU for development environment"
  default     = "B1"
  
  validation {
    condition     = contains(["F1", "D1", "B1", "B2", "B3", "S1", "S2", "S3", "P1V2", "P2V2", "P3V2"], var.app_service_plan_sku_dev)
    error_message = "App Service Plan SKU must be a valid Azure App Service Plan tier."
  }
}

variable "app_service_plan_sku_prod" {
  type        = string
  description = "App Service Plan SKU for production environment"  
  default     = "P1V2"
  
  validation {
    condition     = contains(["F1", "D1", "B1", "B2", "B3", "S1", "S2", "S3", "P1V2", "P2V2", "P3V2"], var.app_service_plan_sku_prod)
    error_message = "App Service Plan SKU must be a valid Azure App Service Plan tier."
  }
}

# Compliance and governance variables
variable "enable_production_compliance" {
  type        = bool
  description = "Enable additional compliance tags for production resources"
  default     = true
}

variable "backup_retention_days" {
  type        = number
  description = "Number of days to retain backups for production resources"
  default     = 30
  
  validation {
    condition     = var.backup_retention_days >= 7 && var.backup_retention_days <= 365
    error_message = "Backup retention days must be between 7 and 365."
  }
}

variable "sla_tier" {
  type        = string
  description = "SLA tier for production resources"
  default     = "high"
  
  validation {
    condition     = contains(["basic", "standard", "high", "premium"], var.sla_tier)
    error_message = "SLA tier must be one of: basic, standard, high, premium."
  }
}

variable "compliance_framework" {
  type        = string
  description = "Compliance framework for production resources"
  default     = "sox"
  
  validation {
    condition     = contains(["sox", "pci", "hipaa", "iso27001", "gdpr", "none"], var.compliance_framework)
    error_message = "Compliance framework must be one of: sox, pci, hipaa, iso27001, gdpr, none."
  }
}

# Additional tagging variables
variable "additional_tags" {
  type        = map(string)
  description = "Additional tags to apply to all resources"
  default     = {}
}

variable "managed_by" {
  type        = string
  description = "Tool or system managing these resources"
  default     = "terraform"
}