# Variables for Azure Workload Identity and Container Storage Infrastructure

variable "resource_group_name" {
  description = "Name of the Azure resource group"
  type        = string
  default     = null
  
  validation {
    condition     = var.resource_group_name == null || can(regex("^[a-zA-Z0-9._-]+$", var.resource_group_name))
    error_message = "Resource group name must contain only alphanumeric characters, periods, underscores, and hyphens."
  }
}

variable "location" {
  description = "Azure region for resource deployment"
  type        = string
  default     = "eastus"
  
  validation {
    condition = contains([
      "eastus", "eastus2", "westus", "westus2", "westus3", "centralus", "northcentralus", "southcentralus",
      "westcentralus", "canadacentral", "canadaeast", "brazilsouth", "northeurope", "westeurope",
      "uksouth", "ukwest", "francecentral", "germanywestcentral", "norwayeast", "switzerlandnorth",
      "uaenorth", "southafricanorth", "australiaeast", "australiasoutheast", "centralindia", "southindia",
      "westindia", "japaneast", "japanwest", "koreacentral", "koreasouth", "southeastasia", "eastasia"
    ], var.location)
    error_message = "Location must be a valid Azure region."
  }
}

variable "aks_cluster_name" {
  description = "Name of the AKS cluster"
  type        = string
  default     = null
  
  validation {
    condition     = var.aks_cluster_name == null || can(regex("^[a-zA-Z0-9-]+$", var.aks_cluster_name))
    error_message = "AKS cluster name must contain only alphanumeric characters and hyphens."
  }
}

variable "kubernetes_version" {
  description = "Kubernetes version for the AKS cluster"
  type        = string
  default     = "1.28"
  
  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+$", var.kubernetes_version))
    error_message = "Kubernetes version must be in format 'x.y' (e.g., '1.28')."
  }
}

variable "node_count" {
  description = "Number of nodes in the default node pool"
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
    condition = contains([
      "Standard_D2s_v3", "Standard_D4s_v3", "Standard_D8s_v3", "Standard_D16s_v3",
      "Standard_B2s", "Standard_B4ms", "Standard_B8ms", "Standard_F2s_v2", "Standard_F4s_v2"
    ], var.node_vm_size)
    error_message = "VM size must be a valid Azure VM size."
  }
}

variable "key_vault_name" {
  description = "Name of the Azure Key Vault"
  type        = string
  default     = null
  
  validation {
    condition     = var.key_vault_name == null || can(regex("^[a-zA-Z0-9-]+$", var.key_vault_name))
    error_message = "Key Vault name must contain only alphanumeric characters and hyphens."
  }
}

variable "key_vault_sku" {
  description = "SKU for the Azure Key Vault"
  type        = string
  default     = "standard"
  
  validation {
    condition     = contains(["standard", "premium"], var.key_vault_sku)
    error_message = "Key Vault SKU must be either 'standard' or 'premium'."
  }
}

variable "managed_identity_name" {
  description = "Name of the user-assigned managed identity"
  type        = string
  default     = null
  
  validation {
    condition     = var.managed_identity_name == null || can(regex("^[a-zA-Z0-9-_]+$", var.managed_identity_name))
    error_message = "Managed identity name must contain only alphanumeric characters, hyphens, and underscores."
  }
}

variable "storage_pool_size" {
  description = "Size of the ephemeral storage pool in GB"
  type        = number
  default     = 100
  
  validation {
    condition     = var.storage_pool_size >= 50 && var.storage_pool_size <= 1000
    error_message = "Storage pool size must be between 50 and 1000 GB."
  }
}

variable "namespace_name" {
  description = "Kubernetes namespace for workload identity demo"
  type        = string
  default     = "workload-identity-demo"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.namespace_name))
    error_message = "Namespace name must contain only lowercase alphanumeric characters and hyphens."
  }
}

variable "service_account_name" {
  description = "Name of the Kubernetes service account"
  type        = string
  default     = "workload-identity-sa"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.service_account_name))
    error_message = "Service account name must contain only lowercase alphanumeric characters and hyphens."
  }
}

variable "enable_container_storage" {
  description = "Enable Azure Container Storage extension"
  type        = bool
  default     = true
}

variable "enable_test_workload" {
  description = "Deploy test workload to validate the setup"
  type        = bool
  default     = true
}

variable "container_storage_release_namespace" {
  description = "Namespace for Azure Container Storage extension"
  type        = string
  default     = "acstor"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.container_storage_release_namespace))
    error_message = "Container storage namespace must contain only lowercase alphanumeric characters and hyphens."
  }
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    purpose     = "workload-identity-demo"
    environment = "test"
    terraform   = "true"
  }
  
  validation {
    condition     = length(var.tags) <= 15
    error_message = "Maximum of 15 tags allowed."
  }
}

variable "random_suffix_length" {
  description = "Length of random suffix for resource names"
  type        = number
  default     = 6
  
  validation {
    condition     = var.random_suffix_length >= 4 && var.random_suffix_length <= 8
    error_message = "Random suffix length must be between 4 and 8 characters."
  }
}