# General Configuration Variables
variable "location" {
  description = "The Azure region where resources will be created"
  type        = string
  default     = "East US"
  validation {
    condition = contains([
      "East US", "East US 2", "West US 2", "West US 3", "North Central US", "South Central US",
      "West Europe", "North Europe", "UK South", "Germany West Central", "France Central",
      "Australia East", "Japan East", "Korea Central", "Southeast Asia", "Central India"
    ], var.location)
    error_message = "The location must be a valid Azure region that supports HPC workloads."
  }
}

variable "environment" {
  description = "Environment name for resource tagging"
  type        = string
  default     = "hpc-demo"
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.environment))
    error_message = "Environment must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "resource_group_name" {
  description = "Name of the resource group to create"
  type        = string
  default     = ""
}

# Network Configuration Variables
variable "vnet_address_space" {
  description = "Address space for the virtual network"
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "compute_subnet_address_prefix" {
  description = "Address prefix for the compute subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "management_subnet_address_prefix" {
  description = "Address prefix for the management subnet"
  type        = string
  default     = "10.0.2.0/24"
}

variable "storage_subnet_address_prefix" {
  description = "Address prefix for the storage subnet"
  type        = string
  default     = "10.0.3.0/24"
}

# Azure Managed Lustre Configuration
variable "lustre_storage_capacity_tib" {
  description = "Storage capacity for Azure Managed Lustre in TiB"
  type        = number
  default     = 4
  validation {
    condition     = var.lustre_storage_capacity_tib >= 4 && var.lustre_storage_capacity_tib <= 504
    error_message = "Lustre storage capacity must be between 4 and 504 TiB."
  }
}

variable "lustre_throughput_per_unit_mb" {
  description = "Throughput per unit for Azure Managed Lustre in MB/s"
  type        = number
  default     = 1000
  validation {
    condition     = contains([125, 250, 500, 1000], var.lustre_throughput_per_unit_mb)
    error_message = "Lustre throughput must be one of: 125, 250, 500, or 1000 MB/s."
  }
}

variable "lustre_file_system_type" {
  description = "File system type for Azure Managed Lustre"
  type        = string
  default     = "Durable"
  validation {
    condition     = contains(["Durable", "NonDurable"], var.lustre_file_system_type)
    error_message = "Lustre file system type must be either 'Durable' or 'NonDurable'."
  }
}

variable "lustre_storage_type" {
  description = "Storage type for Azure Managed Lustre"
  type        = string
  default     = "SSD"
  validation {
    condition     = contains(["SSD", "HDD"], var.lustre_storage_type)
    error_message = "Lustre storage type must be either 'SSD' or 'HDD'."
  }
}

# CycleCloud Configuration
variable "cyclecloud_vm_size" {
  description = "VM size for the CycleCloud management server"
  type        = string
  default     = "Standard_D4s_v3"
  validation {
    condition = contains([
      "Standard_D4s_v3", "Standard_D8s_v3", "Standard_D16s_v3",
      "Standard_E4s_v3", "Standard_E8s_v3", "Standard_E16s_v3"
    ], var.cyclecloud_vm_size)
    error_message = "CycleCloud VM size must be a supported general-purpose VM size."
  }
}

variable "cyclecloud_admin_username" {
  description = "Admin username for CycleCloud VM"
  type        = string
  default     = "azureuser"
  validation {
    condition     = can(regex("^[a-z_][a-z0-9_-]{0,31}$", var.cyclecloud_admin_username))
    error_message = "Admin username must be valid Linux username format."
  }
}

variable "cyclecloud_os_disk_size_gb" {
  description = "OS disk size in GB for CycleCloud VM"
  type        = number
  default     = 128
  validation {
    condition     = var.cyclecloud_os_disk_size_gb >= 64 && var.cyclecloud_os_disk_size_gb <= 4095
    error_message = "OS disk size must be between 64 and 4095 GB."
  }
}

# HPC Cluster Configuration
variable "hpc_cluster_name" {
  description = "Name for the HPC cluster"
  type        = string
  default     = "hpc-slurm-cluster"
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.hpc_cluster_name))
    error_message = "HPC cluster name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "hpc_compute_vm_size" {
  description = "VM size for HPC compute nodes"
  type        = string
  default     = "Standard_HB120rs_v3"
  validation {
    condition = contains([
      "Standard_HB120rs_v3", "Standard_HB120rs_v2", "Standard_HC44rs",
      "Standard_HX176rs", "Standard_ND40rs_v2", "Standard_ND96asr_v4"
    ], var.hpc_compute_vm_size)
    error_message = "HPC compute VM size must be a supported HPC VM size."
  }
}

variable "hpc_max_core_count" {
  description = "Maximum core count for HPC cluster auto-scaling"
  type        = number
  default     = 480
  validation {
    condition     = var.hpc_max_core_count >= 1 && var.hpc_max_core_count <= 10000
    error_message = "Max core count must be between 1 and 10000."
  }
}

variable "hpc_use_low_priority" {
  description = "Use low priority VMs for cost optimization"
  type        = bool
  default     = false
}

# Storage Configuration
variable "storage_account_tier" {
  description = "Storage account tier for CycleCloud and data staging"
  type        = string
  default     = "Standard"
  validation {
    condition     = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be either 'Standard' or 'Premium'."
  }
}

variable "storage_account_replication_type" {
  description = "Storage account replication type"
  type        = string
  default     = "LRS"
  validation {
    condition     = contains(["LRS", "ZRS", "GRS", "RAGRS"], var.storage_account_replication_type)
    error_message = "Storage account replication type must be LRS, ZRS, GRS, or RAGRS."
  }
}

# Monitoring Configuration
variable "enable_monitoring" {
  description = "Enable Azure Monitor and Log Analytics for HPC workloads"
  type        = bool
  default     = true
}

variable "log_analytics_sku" {
  description = "SKU for Log Analytics workspace"
  type        = string
  default     = "PerGB2018"
  validation {
    condition     = contains(["PerGB2018", "PerNode", "Premium", "Standard", "Standalone", "Unlimited"], var.log_analytics_sku)
    error_message = "Log Analytics SKU must be a valid pricing tier."
  }
}

variable "log_retention_days" {
  description = "Log retention period in days"
  type        = number
  default     = 30
  validation {
    condition     = var.log_retention_days >= 30 && var.log_retention_days <= 730
    error_message = "Log retention must be between 30 and 730 days."
  }
}

# Security Configuration
variable "enable_ssh_key_authentication" {
  description = "Enable SSH key authentication for VMs"
  type        = bool
  default     = true
}

variable "ssh_public_key_path" {
  description = "Path to SSH public key file"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

variable "allowed_ssh_cidrs" {
  description = "List of CIDR blocks allowed for SSH access"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# Tagging Configuration
variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    purpose    = "hpc-demo"
    managed-by = "terraform"
    workload   = "high-performance-computing"
  }
}

# Random Suffix Configuration
variable "random_suffix_length" {
  description = "Length of random suffix for resource names"
  type        = number
  default     = 6
  validation {
    condition     = var.random_suffix_length >= 3 && var.random_suffix_length <= 10
    error_message = "Random suffix length must be between 3 and 10."
  }
}