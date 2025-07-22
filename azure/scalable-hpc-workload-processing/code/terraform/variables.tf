# Variables for Azure HPC Workload Processing Infrastructure

# General Configuration
variable "location" {
  description = "The Azure region where resources will be deployed"
  type        = string
  default     = "East US"
  
  validation {
    condition = can(regex("^[A-Za-z0-9 ]+$", var.location))
    error_message = "Location must be a valid Azure region name."
  }
}

variable "environment" {
  description = "Environment name for resource tagging"
  type        = string
  default     = "demo"
  
  validation {
    condition = contains(["dev", "test", "staging", "prod", "demo"], var.environment)
    error_message = "Environment must be one of: dev, test, staging, prod, demo."
  }
}

variable "resource_group_name" {
  description = "Name of the Azure resource group"
  type        = string
  default     = "rg-hpc-esan"
  
  validation {
    condition = can(regex("^[a-zA-Z0-9._-]+$", var.resource_group_name))
    error_message = "Resource group name must contain only alphanumeric characters, periods, underscores, and hyphens."
  }
}

# Networking Configuration
variable "virtual_network_name" {
  description = "Name of the virtual network for HPC communication"
  type        = string
  default     = "vnet-hpc"
  
  validation {
    condition = can(regex("^[a-zA-Z0-9._-]+$", var.virtual_network_name))
    error_message = "Virtual network name must contain only alphanumeric characters, periods, underscores, and hyphens."
  }
}

variable "subnet_name" {
  description = "Name of the subnet for Batch compute nodes"
  type        = string
  default     = "subnet-batch"
  
  validation {
    condition = can(regex("^[a-zA-Z0-9._-]+$", var.subnet_name))
    error_message = "Subnet name must contain only alphanumeric characters, periods, underscores, and hyphens."
  }
}

variable "network_security_group_name" {
  description = "Name of the network security group for HPC traffic"
  type        = string
  default     = "nsg-hpc"
  
  validation {
    condition = can(regex("^[a-zA-Z0-9._-]+$", var.network_security_group_name))
    error_message = "Network security group name must contain only alphanumeric characters, periods, underscores, and hyphens."
  }
}

# Storage Configuration
variable "storage_account_name" {
  description = "Name of the storage account for Batch applications and logs (must be globally unique)"
  type        = string
  default     = "sthpc"
  
  validation {
    condition = can(regex("^[a-z0-9]{3,24}$", var.storage_account_name))
    error_message = "Storage account name must be 3-24 characters long and contain only lowercase letters and numbers."
  }
}

variable "elastic_san_name" {
  description = "Name of the Azure Elastic SAN instance"
  type        = string
  default     = "esan-hpc"
  
  validation {
    condition = can(regex("^[a-zA-Z0-9._-]+$", var.elastic_san_name))
    error_message = "Elastic SAN name must contain only alphanumeric characters, periods, underscores, and hyphens."
  }
}

variable "elastic_san_base_size_tib" {
  description = "Base size of the Elastic SAN in TiB (minimum 1 TiB)"
  type        = number
  default     = 1
  
  validation {
    condition = var.elastic_san_base_size_tib >= 1 && var.elastic_san_base_size_tib <= 100
    error_message = "Elastic SAN base size must be between 1 and 100 TiB."
  }
}

variable "elastic_san_extended_capacity_tib" {
  description = "Extended capacity size of the Elastic SAN in TiB"
  type        = number
  default     = 2
  
  validation {
    condition = var.elastic_san_extended_capacity_tib >= 0 && var.elastic_san_extended_capacity_tib <= 400
    error_message = "Elastic SAN extended capacity must be between 0 and 400 TiB."
  }
}

variable "data_input_volume_size_gib" {
  description = "Size of the data input volume in GiB"
  type        = number
  default     = 500
  
  validation {
    condition = var.data_input_volume_size_gib >= 1 && var.data_input_volume_size_gib <= 65536
    error_message = "Data input volume size must be between 1 and 65536 GiB."
  }
}

variable "results_output_volume_size_gib" {
  description = "Size of the results output volume in GiB"
  type        = number
  default     = 1000
  
  validation {
    condition = var.results_output_volume_size_gib >= 1 && var.results_output_volume_size_gib <= 65536
    error_message = "Results output volume size must be between 1 and 65536 GiB."
  }
}

variable "shared_libraries_volume_size_gib" {
  description = "Size of the shared libraries volume in GiB"
  type        = number
  default     = 100
  
  validation {
    condition = var.shared_libraries_volume_size_gib >= 1 && var.shared_libraries_volume_size_gib <= 65536
    error_message = "Shared libraries volume size must be between 1 and 65536 GiB."
  }
}

# Azure Batch Configuration
variable "batch_account_name" {
  description = "Name of the Azure Batch account"
  type        = string
  default     = "batch-hpc"
  
  validation {
    condition = can(regex("^[a-zA-Z0-9]+$", var.batch_account_name))
    error_message = "Batch account name must contain only alphanumeric characters."
  }
}

variable "batch_pool_name" {
  description = "Name of the Batch pool for HPC compute nodes"
  type        = string
  default     = "hpc-compute-pool"
  
  validation {
    condition = can(regex("^[a-zA-Z0-9._-]+$", var.batch_pool_name))
    error_message = "Batch pool name must contain only alphanumeric characters, periods, underscores, and hyphens."
  }
}

variable "batch_vm_size" {
  description = "VM size for Batch compute nodes (HPC-optimized VMs recommended)"
  type        = string
  default     = "Standard_HC44rs"
  
  validation {
    condition = can(regex("^Standard_[A-Z0-9_]+$", var.batch_vm_size))
    error_message = "VM size must be a valid Azure VM size (e.g., Standard_HC44rs)."
  }
}

variable "batch_pool_max_nodes" {
  description = "Maximum number of nodes in the Batch pool for auto-scaling"
  type        = number
  default     = 20
  
  validation {
    condition = var.batch_pool_max_nodes >= 1 && var.batch_pool_max_nodes <= 1000
    error_message = "Maximum nodes must be between 1 and 1000."
  }
}

variable "hpc_user_password" {
  description = "Password for the HPC user account on compute nodes"
  type        = string
  default     = "HPC@Pass123!"
  sensitive   = true
  
  validation {
    condition = length(var.hpc_user_password) >= 12 && can(regex("^.*[A-Z].*[a-z].*[0-9].*[!@#$%^&*()].*$", var.hpc_user_password))
    error_message = "Password must be at least 12 characters long and contain uppercase, lowercase, numeric, and special characters."
  }
}

# Monitoring Configuration
variable "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace for monitoring"
  type        = string
  default     = "law-hpc"
  
  validation {
    condition = can(regex("^[a-zA-Z0-9._-]+$", var.log_analytics_workspace_name))
    error_message = "Log Analytics workspace name must contain only alphanumeric characters, periods, underscores, and hyphens."
  }
}

variable "application_insights_name" {
  description = "Name of the Application Insights instance"
  type        = string
  default     = "ai-hpc"
  
  validation {
    condition = can(regex("^[a-zA-Z0-9._-]+$", var.application_insights_name))
    error_message = "Application Insights name must contain only alphanumeric characters, periods, underscores, and hyphens."
  }
}

variable "action_group_name" {
  description = "Name of the action group for alerting"
  type        = string
  default     = "ag-hpc-alerts"
  
  validation {
    condition = can(regex("^[a-zA-Z0-9._-]+$", var.action_group_name))
    error_message = "Action group name must contain only alphanumeric characters, periods, underscores, and hyphens."
  }
}

variable "alert_email_address" {
  description = "Email address for receiving alerts"
  type        = string
  default     = "admin@example.com"
  
  validation {
    condition = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.alert_email_address))
    error_message = "Must be a valid email address."
  }
}

variable "cost_threshold_node_count" {
  description = "Node count threshold for cost alerts"
  type        = number
  default     = 10
  
  validation {
    condition = var.cost_threshold_node_count >= 1 && var.cost_threshold_node_count <= 1000
    error_message = "Cost threshold node count must be between 1 and 1000."
  }
}

# Feature Flags
variable "enable_monitoring" {
  description = "Enable monitoring and alerting resources"
  type        = bool
  default     = true
}

variable "enable_auto_scaling" {
  description = "Enable auto-scaling for the Batch pool"
  type        = bool
  default     = true
}

variable "enable_diagnostic_settings" {
  description = "Enable diagnostic settings for resources"
  type        = bool
  default     = true
}

# Random suffix for globally unique names
variable "random_suffix" {
  description = "Random suffix to append to resource names for uniqueness"
  type        = string
  default     = ""
  
  validation {
    condition = can(regex("^[a-z0-9]*$", var.random_suffix))
    error_message = "Random suffix must contain only lowercase letters and numbers."
  }
}