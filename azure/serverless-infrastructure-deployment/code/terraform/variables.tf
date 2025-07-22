# Input Variables for Azure Container Apps Jobs Deployment Automation
# This file defines all configurable parameters for the infrastructure deployment

# Resource Naming and Location Configuration
variable "location" {
  description = "Azure region where all resources will be deployed"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "North Central US", "South Central US", "West Central US",
      "Canada Central", "Canada East", "Brazil South", "UK South", "UK West",
      "West Europe", "North Europe", "France Central", "Germany West Central",
      "Norway East", "Switzerland North", "Sweden Central", "Poland Central",
      "Australia East", "Australia Southeast", "East Asia", "Southeast Asia",
      "Japan East", "Japan West", "Korea Central", "India Central", "UAE North"
    ], var.location)
    error_message = "Location must be a valid Azure region."
  }
}

variable "resource_group_name" {
  description = "Name of the resource group for deployment automation resources"
  type        = string
  default     = "rg-deployment-automation"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._()-]{1,90}$", var.resource_group_name))
    error_message = "Resource group name must be 1-90 characters and contain only alphanumeric, underscore, parentheses, hyphen, and period characters."
  }
}

variable "environment" {
  description = "Environment designation for resource tagging and naming"
  type        = string
  default     = "demo"
  
  validation {
    condition     = contains(["dev", "test", "staging", "prod", "demo"], var.environment)
    error_message = "Environment must be one of: dev, test, staging, prod, demo."
  }
}

variable "project_name" {
  description = "Project name used for resource naming and tagging"
  type        = string
  default     = "deployment-automation"
  
  validation {
    condition     = can(regex("^[a-z0-9-]{3,20}$", var.project_name))
    error_message = "Project name must be 3-20 characters, lowercase letters, numbers, and hyphens only."
  }
}

# Container Apps Configuration
variable "container_apps_environment_name" {
  description = "Name of the Container Apps environment"
  type        = string
  default     = "cae-deployment-env"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]{0,31}$", var.container_apps_environment_name))
    error_message = "Container Apps environment name must be 1-32 characters, start with alphanumeric, and contain only alphanumeric and hyphens."
  }
}

variable "deployment_job_name" {
  description = "Name of the manual deployment job"
  type        = string
  default     = "deployment-job"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]{0,31}$", var.deployment_job_name))
    error_message = "Job name must be 1-32 characters, start with alphanumeric, and contain only alphanumeric and hyphens."
  }
}

variable "scheduled_job_name" {
  description = "Name of the scheduled deployment job"
  type        = string
  default     = "deployment-job-scheduled"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]{0,31}$", var.scheduled_job_name))
    error_message = "Scheduled job name must be 1-32 characters, start with alphanumeric, and contain only alphanumeric and hyphens."
  }
}

variable "job_replica_timeout" {
  description = "Timeout in seconds for job replica execution"
  type        = number
  default     = 1800
  
  validation {
    condition     = var.job_replica_timeout >= 60 && var.job_replica_timeout <= 7200
    error_message = "Job replica timeout must be between 60 and 7200 seconds."
  }
}

variable "job_replica_retry_limit" {
  description = "Maximum number of retry attempts for failed job replicas"
  type        = number
  default     = 3
  
  validation {
    condition     = var.job_replica_retry_limit >= 0 && var.job_replica_retry_limit <= 10
    error_message = "Job replica retry limit must be between 0 and 10."
  }
}

variable "job_cpu_allocation" {
  description = "CPU allocation for Container Apps Job (in cores)"
  type        = string
  default     = "0.5"
  
  validation {
    condition     = contains(["0.25", "0.5", "0.75", "1", "1.25", "1.5", "1.75", "2"], var.job_cpu_allocation)
    error_message = "CPU allocation must be one of: 0.25, 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2."
  }
}

variable "job_memory_allocation" {
  description = "Memory allocation for Container Apps Job (in Gi)"
  type        = string
  default     = "1.0Gi"
  
  validation {
    condition     = contains(["0.5Gi", "1.0Gi", "1.5Gi", "2.0Gi", "3.0Gi", "4.0Gi"], var.job_memory_allocation)
    error_message = "Memory allocation must be one of: 0.5Gi, 1.0Gi, 1.5Gi, 2.0Gi, 3.0Gi, 4.0Gi."
  }
}

variable "container_image" {
  description = "Container image for deployment jobs"
  type        = string
  default     = "mcr.microsoft.com/azure-cli:latest"
  
  validation {
    condition     = can(regex("^[a-z0-9]+(\\.[a-z0-9]+)*(\\/[a-z0-9-._]+)*:[a-zA-Z0-9-._]+$", var.container_image))
    error_message = "Container image must be a valid Docker image reference."
  }
}

# Scheduled Job Configuration
variable "schedule_cron_expression" {
  description = "Cron expression for scheduled deployments (UTC timezone)"
  type        = string
  default     = "0 2 * * *"
  
  validation {
    condition     = can(regex("^[0-9*,-/]+ +[0-9*,-/]+ +[0-9*,-/]+ +[0-9*,-/]+ +[0-9*,-/]+$", var.schedule_cron_expression))
    error_message = "Cron expression must be in valid format: 'minute hour day month dayofweek'."
  }
}

# Storage Account Configuration
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
    error_message = "Storage replication type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

variable "storage_account_access_tier" {
  description = "Access tier for blob storage"
  type        = string
  default     = "Hot"
  
  validation {
    condition     = contains(["Hot", "Cool"], var.storage_account_access_tier)
    error_message = "Storage access tier must be either 'Hot' or 'Cool'."
  }
}

# Key Vault Configuration
variable "key_vault_sku_name" {
  description = "SKU name for the Key Vault"
  type        = string
  default     = "standard"
  
  validation {
    condition     = contains(["standard", "premium"], var.key_vault_sku_name)
    error_message = "Key Vault SKU must be either 'standard' or 'premium'."
  }
}

variable "key_vault_soft_delete_retention_days" {
  description = "Number of days to retain soft-deleted Key Vault and its objects"
  type        = number
  default     = 7
  
  validation {
    condition     = var.key_vault_soft_delete_retention_days >= 7 && var.key_vault_soft_delete_retention_days <= 90
    error_message = "Key Vault soft delete retention days must be between 7 and 90."
  }
}

# RBAC and Security Configuration
variable "enable_key_vault_rbac" {
  description = "Enable RBAC authorization for Key Vault instead of access policies"
  type        = bool
  default     = true
}

variable "enable_storage_public_access" {
  description = "Allow public access to storage account blobs"
  type        = bool
  default     = false
}

variable "enable_container_apps_logs" {
  description = "Enable Container Apps environment logs (requires Log Analytics workspace)"
  type        = bool
  default     = false
}

# Resource Tagging Configuration
variable "tags" {
  description = "Map of tags to apply to all resources"
  type        = map(string)
  default = {
    Purpose     = "deployment-automation"
    ManagedBy   = "terraform"
    Environment = "demo"
  }
  
  validation {
    condition     = length(var.tags) <= 50
    error_message = "Maximum of 50 tags can be applied to Azure resources."
  }
}

# Advanced Configuration
variable "managed_identity_name" {
  description = "Name of the user-assigned managed identity for deployment jobs"
  type        = string
  default     = "id-deployment-job"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{3,128}$", var.managed_identity_name))
    error_message = "Managed identity name must be 3-128 characters and contain only alphanumeric, underscore, and hyphen characters."
  }
}

variable "deployment_script_timeout" {
  description = "Timeout in seconds for deployment script execution within the container"
  type        = number
  default     = 1200
  
  validation {
    condition     = var.deployment_script_timeout >= 300 && var.deployment_script_timeout <= 3600
    error_message = "Deployment script timeout must be between 300 and 3600 seconds."
  }
}

# Network Configuration (for future use)
variable "enable_private_endpoints" {
  description = "Enable private endpoints for storage account and key vault"
  type        = bool
  default     = false
}

variable "virtual_network_integration" {
  description = "Enable virtual network integration for Container Apps environment"
  type        = bool
  default     = false
}