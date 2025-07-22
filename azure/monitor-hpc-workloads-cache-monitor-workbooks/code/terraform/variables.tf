# Variables for Azure HPC Cache and Monitor Workbooks deployment

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = "rg-hpc-monitoring"
}

variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = "East US"
  
  validation {
    condition = can(regex("^[A-Za-z0-9 ]+$", var.location))
    error_message = "Location must be a valid Azure region name."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, prod, test)"
  type        = string
  default     = "demo"
  
  validation {
    condition     = length(var.environment) > 0 && length(var.environment) <= 10
    error_message = "Environment must be between 1 and 10 characters."
  }
}

variable "hpc_cache_name" {
  description = "Name of the HPC Cache"
  type        = string
  default     = "hpc-cache"
}

variable "hpc_cache_size_gb" {
  description = "Size of the HPC Cache in GB"
  type        = number
  default     = 3072
  
  validation {
    condition = contains([3072, 6144, 12288, 24576, 49152], var.hpc_cache_size_gb)
    error_message = "HPC Cache size must be one of: 3072, 6144, 12288, 24576, 49152 GB."
  }
}

variable "hpc_cache_sku" {
  description = "SKU for the HPC Cache"
  type        = string
  default     = "Standard_2G"
  
  validation {
    condition = contains(["Standard_2G", "Standard_4G", "Standard_8G"], var.hpc_cache_sku)
    error_message = "HPC Cache SKU must be one of: Standard_2G, Standard_4G, Standard_8G."
  }
}

variable "batch_account_name" {
  description = "Name of the Batch Account"
  type        = string
  default     = "batch"
}

variable "batch_pool_name" {
  description = "Name of the Batch Pool"
  type        = string
  default     = "hpc-pool"
}

variable "batch_vm_size" {
  description = "VM size for Batch nodes"
  type        = string
  default     = "Standard_HC44rs"
}

variable "batch_node_count" {
  description = "Number of nodes in the Batch pool"
  type        = number
  default     = 2
  
  validation {
    condition     = var.batch_node_count > 0 && var.batch_node_count <= 100
    error_message = "Batch node count must be between 1 and 100."
  }
}

variable "storage_account_name" {
  description = "Name of the storage account"
  type        = string
  default     = "hpcstorage"
}

variable "storage_account_tier" {
  description = "Storage account tier"
  type        = string
  default     = "Standard"
  
  validation {
    condition = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be either Standard or Premium."
  }
}

variable "storage_replication_type" {
  description = "Storage account replication type"
  type        = string
  default     = "LRS"
  
  validation {
    condition = contains(["LRS", "GRS", "RAGRS", "ZRS"], var.storage_replication_type)
    error_message = "Storage replication type must be one of: LRS, GRS, RAGRS, ZRS."
  }
}

variable "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  type        = string
  default     = "hpc-workspace"
}

variable "log_analytics_sku" {
  description = "SKU for Log Analytics workspace"
  type        = string
  default     = "PerGB2018"
  
  validation {
    condition = contains(["Free", "PerNode", "PerGB2018", "Premium"], var.log_analytics_sku)
    error_message = "Log Analytics SKU must be one of: Free, PerNode, PerGB2018, Premium."
  }
}

variable "log_retention_in_days" {
  description = "Log retention period in days"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_retention_in_days >= 7 && var.log_retention_in_days <= 730
    error_message = "Log retention must be between 7 and 730 days."
  }
}

variable "workbook_display_name" {
  description = "Display name for the Azure Monitor Workbook"
  type        = string
  default     = "HPC Monitoring Dashboard"
}

variable "vnet_address_space" {
  description = "Address space for the virtual network"
  type        = string
  default     = "10.0.0.0/16"
  
  validation {
    condition = can(cidrhost(var.vnet_address_space, 0))
    error_message = "VNet address space must be a valid CIDR block."
  }
}

variable "subnet_address_prefix" {
  description = "Address prefix for the HPC subnet"
  type        = string
  default     = "10.0.1.0/24"
  
  validation {
    condition = can(cidrhost(var.subnet_address_prefix, 0))
    error_message = "Subnet address prefix must be a valid CIDR block."
  }
}

variable "alert_email" {
  description = "Email address for alert notifications"
  type        = string
  default     = "admin@example.com"
  
  validation {
    condition = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.alert_email))
    error_message = "Alert email must be a valid email address."
  }
}

variable "enable_monitoring" {
  description = "Enable monitoring and diagnostic settings"
  type        = bool
  default     = true
}

variable "enable_alerts" {
  description = "Enable performance alerts"
  type        = bool
  default     = true
}

variable "cache_hit_rate_threshold" {
  description = "Cache hit rate threshold for alerts (percentage)"
  type        = number
  default     = 80
  
  validation {
    condition     = var.cache_hit_rate_threshold >= 0 && var.cache_hit_rate_threshold <= 100
    error_message = "Cache hit rate threshold must be between 0 and 100."
  }
}

variable "compute_utilization_threshold" {
  description = "Compute utilization threshold for alerts (percentage)"
  type        = number
  default     = 90
  
  validation {
    condition     = var.compute_utilization_threshold >= 0 && var.compute_utilization_threshold <= 100
    error_message = "Compute utilization threshold must be between 0 and 100."
  }
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Purpose     = "HPC Monitoring"
    Environment = "Demo"
    Project     = "HPC Cache Monitoring"
  }
}