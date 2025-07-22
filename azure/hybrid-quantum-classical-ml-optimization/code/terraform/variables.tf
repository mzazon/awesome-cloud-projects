# Variables for Azure Quantum-Enhanced Machine Learning Infrastructure

variable "resource_prefix" {
  description = "Prefix for all resource names to ensure uniqueness"
  type        = string
  default     = "quantum-ml"
  
  validation {
    condition     = length(var.resource_prefix) <= 10 && can(regex("^[a-z0-9-]+$", var.resource_prefix))
    error_message = "Resource prefix must be 10 characters or less and contain only lowercase letters, numbers, and hyphens."
  }
}

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
      "Switzerland North", "Norway East", "Sweden Central", "UAE North",
      "South Africa North", "Australia East", "Australia Southeast",
      "Central India", "South India", "Japan East", "Japan West",
      "Korea Central", "Southeast Asia", "East Asia"
    ], var.location)
    error_message = "Location must be a valid Azure region."
  }
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
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Project     = "quantum-enhanced-ml"
    Environment = "development"
    Purpose     = "quantum-ml-demo"
    ManagedBy   = "terraform"
  }
}

# Azure Quantum Configuration
variable "quantum_workspace_name" {
  description = "Name for the Azure Quantum workspace"
  type        = string
  default     = ""
}

variable "quantum_providers" {
  description = "Quantum hardware providers to enable"
  type = list(object({
    provider_id = string
    sku        = string
  }))
  default = [
    {
      provider_id = "ionq"
      sku        = "free"
    },
    {
      provider_id = "quantinuum"
      sku        = "free"
    },
    {
      provider_id = "microsoft"
      sku        = "free"
    }
  ]
}

# Azure Machine Learning Configuration
variable "ml_workspace_name" {
  description = "Name for the Azure Machine Learning workspace"
  type        = string
  default     = ""
}

variable "ml_compute_instance_size" {
  description = "Size of the ML compute instance"
  type        = string
  default     = "Standard_DS3_v2"
  
  validation {
    condition = contains([
      "Standard_DS3_v2", "Standard_DS4_v2", "Standard_DS5_v2",
      "Standard_DS11_v2", "Standard_DS12_v2", "Standard_DS13_v2",
      "Standard_NC6", "Standard_NC12", "Standard_NC24"
    ], var.ml_compute_instance_size)
    error_message = "Compute instance size must be a valid Azure VM size."
  }
}

variable "ml_compute_cluster_min_nodes" {
  description = "Minimum number of nodes in the ML compute cluster"
  type        = number
  default     = 0
  
  validation {
    condition     = var.ml_compute_cluster_min_nodes >= 0 && var.ml_compute_cluster_min_nodes <= 10
    error_message = "Minimum nodes must be between 0 and 10."
  }
}

variable "ml_compute_cluster_max_nodes" {
  description = "Maximum number of nodes in the ML compute cluster"
  type        = number
  default     = 4
  
  validation {
    condition     = var.ml_compute_cluster_max_nodes >= 1 && var.ml_compute_cluster_max_nodes <= 100
    error_message = "Maximum nodes must be between 1 and 100."
  }
}

# Storage Configuration
variable "storage_account_name" {
  description = "Name for the storage account"
  type        = string
  default     = ""
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

variable "enable_data_lake" {
  description = "Enable hierarchical namespace for Data Lake Storage Gen2"
  type        = bool
  default     = true
}

# Azure Batch Configuration
variable "batch_account_name" {
  description = "Name for the Azure Batch account"
  type        = string
  default     = ""
}

variable "batch_pool_allocation_mode" {
  description = "Allocation mode for Batch account"
  type        = string
  default     = "BatchService"
  
  validation {
    condition     = contains(["BatchService", "UserSubscription"], var.batch_pool_allocation_mode)
    error_message = "Batch pool allocation mode must be either 'BatchService' or 'UserSubscription'."
  }
}

# Key Vault Configuration
variable "key_vault_name" {
  description = "Name for the Key Vault"
  type        = string
  default     = ""
}

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
  description = "Number of days to retain soft deleted keys"
  type        = number
  default     = 7
  
  validation {
    condition     = var.key_vault_soft_delete_retention_days >= 7 && var.key_vault_soft_delete_retention_days <= 90
    error_message = "Soft delete retention days must be between 7 and 90."
  }
}

# Application Insights Configuration
variable "enable_application_insights" {
  description = "Enable Application Insights for monitoring"
  type        = bool
  default     = true
}

variable "application_insights_type" {
  description = "Application type for Application Insights"
  type        = string
  default     = "web"
  
  validation {
    condition     = contains(["web", "other"], var.application_insights_type)
    error_message = "Application Insights type must be either 'web' or 'other'."
  }
}

# Container Registry Configuration
variable "enable_container_registry" {
  description = "Enable Azure Container Registry for custom ML environments"
  type        = bool
  default     = true
}

variable "container_registry_sku" {
  description = "SKU for the Container Registry"
  type        = string
  default     = "Basic"
  
  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.container_registry_sku)
    error_message = "Container Registry SKU must be one of: Basic, Standard, Premium."
  }
}

# Networking Configuration
variable "enable_private_endpoints" {
  description = "Enable private endpoints for enhanced security"
  type        = bool
  default     = false
}

variable "virtual_network_address_space" {
  description = "Address space for the virtual network"
  type        = list(string)
  default     = ["10.0.0.0/16"]
  
  validation {
    condition     = length(var.virtual_network_address_space) > 0
    error_message = "Virtual network address space must contain at least one CIDR block."
  }
}

variable "private_subnet_address_prefix" {
  description = "Address prefix for the private subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "public_subnet_address_prefix" {
  description = "Address prefix for the public subnet"
  type        = string
  default     = "10.0.2.0/24"
}

# Security Configuration
variable "enable_rbac" {
  description = "Enable Role-Based Access Control"
  type        = bool
  default     = true
}

variable "allowed_ip_ranges" {
  description = "IP ranges allowed to access resources (when applicable)"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# Cost Management
variable "auto_shutdown_time" {
  description = "Auto-shutdown time for compute instances (HH:MM format in UTC)"
  type        = string
  default     = "19:00"
  
  validation {
    condition     = can(regex("^([0-1]?[0-9]|2[0-3]):[0-5][0-9]$", var.auto_shutdown_time))
    error_message = "Auto shutdown time must be in HH:MM format (24-hour)."
  }
}

variable "enable_auto_shutdown" {
  description = "Enable auto-shutdown for compute instances to control costs"
  type        = bool
  default     = true
}