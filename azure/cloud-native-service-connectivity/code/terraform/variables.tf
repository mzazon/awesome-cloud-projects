# Variables for Azure cloud-native service connectivity infrastructure

variable "location" {
  description = "The Azure region where resources will be deployed"
  type        = string
  default     = "eastus"
  
  validation {
    condition     = contains(["eastus", "westus2", "westeurope", "northeurope", "centralus", "eastus2"], var.location)
    error_message = "The location must be a valid Azure region that supports Application Gateway for Containers."
  }
}

variable "resource_group_name" {
  description = "Name of the resource group to create"
  type        = string
  default     = "rg-cloud-native-connectivity"
}

variable "cluster_name_prefix" {
  description = "Prefix for the AKS cluster name"
  type        = string
  default     = "aks-connectivity"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.cluster_name_prefix))
    error_message = "The cluster name prefix must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "node_count" {
  description = "Number of nodes in the AKS cluster"
  type        = number
  default     = 3
  
  validation {
    condition     = var.node_count >= 1 && var.node_count <= 10
    error_message = "Node count must be between 1 and 10."
  }
}

variable "node_vm_size" {
  description = "VM size for AKS cluster nodes"
  type        = string
  default     = "Standard_D2s_v3"
  
  validation {
    condition     = contains(["Standard_D2s_v3", "Standard_D4s_v3", "Standard_D8s_v3", "Standard_B2s", "Standard_B4ms"], var.node_vm_size)
    error_message = "Node VM size must be a valid Azure VM size suitable for AKS."
  }
}

variable "sql_admin_username" {
  description = "Administrator username for Azure SQL Server"
  type        = string
  default     = "cloudadmin"
  
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_-]*$", var.sql_admin_username))
    error_message = "SQL admin username must start with a letter and contain only letters, numbers, underscores, and hyphens."
  }
}

variable "sql_admin_password" {
  description = "Administrator password for Azure SQL Server"
  type        = string
  sensitive   = true
  default     = "SecurePassword123!"
  
  validation {
    condition     = length(var.sql_admin_password) >= 8
    error_message = "SQL admin password must be at least 8 characters long."
  }
}

variable "storage_account_tier" {
  description = "Performance tier for Azure Storage Account"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be either Standard or Premium."
  }
}

variable "storage_account_replication_type" {
  description = "Replication type for Azure Storage Account"
  type        = string
  default     = "LRS"
  
  validation {
    condition     = contains(["LRS", "GRS", "ZRS"], var.storage_account_replication_type)
    error_message = "Storage account replication type must be LRS, GRS, or ZRS."
  }
}

variable "sql_database_sku" {
  description = "SKU for Azure SQL Database"
  type        = string
  default     = "Basic"
  
  validation {
    condition     = contains(["Basic", "S0", "S1", "P1"], var.sql_database_sku)
    error_message = "SQL database SKU must be a valid Azure SQL Database SKU."
  }
}

variable "enable_auto_scaling" {
  description = "Enable auto-scaling for AKS cluster"
  type        = bool
  default     = true
}

variable "min_node_count" {
  description = "Minimum number of nodes when auto-scaling is enabled"
  type        = number
  default     = 1
}

variable "max_node_count" {
  description = "Maximum number of nodes when auto-scaling is enabled"
  type        = number
  default     = 10
}

variable "kubernetes_version" {
  description = "Version of Kubernetes to use for AKS cluster"
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags to be applied to all resources"
  type        = map(string)
  default = {
    purpose     = "cloud-native-connectivity"
    environment = "demo"
    project     = "azure-agc-service-connector"
  }
}

variable "namespace_name" {
  description = "Kubernetes namespace name for applications"
  type        = string
  default     = "cloud-native-app"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.namespace_name))
    error_message = "Namespace name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "service_account_name" {
  description = "Kubernetes service account name for workload identity"
  type        = string
  default     = "workload-identity-sa"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.service_account_name))
    error_message = "Service account name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "enable_rbac" {
  description = "Enable Role-Based Access Control for AKS"
  type        = bool
  default     = true
}

variable "enable_network_policy" {
  description = "Enable network policy for AKS"
  type        = bool
  default     = true
}

variable "enable_pod_security_policy" {
  description = "Enable Pod Security Policy for AKS"
  type        = bool
  default     = false
}

variable "enable_private_cluster" {
  description = "Enable private cluster for AKS"
  type        = bool
  default     = false
}

variable "key_vault_sku" {
  description = "SKU for Azure Key Vault"
  type        = string
  default     = "standard"
  
  validation {
    condition     = contains(["standard", "premium"], var.key_vault_sku)
    error_message = "Key Vault SKU must be either standard or premium."
  }
}