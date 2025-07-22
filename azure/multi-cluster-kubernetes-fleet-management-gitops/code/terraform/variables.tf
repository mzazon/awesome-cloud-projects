# General Configuration
variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = "rg-fleet-demo"
}

variable "location" {
  description = "Primary Azure region for deployment"
  type        = string
  default     = "East US"
}

variable "regions" {
  description = "List of Azure regions for AKS clusters"
  type        = list(string)
  default     = ["East US", "West US 2", "Central US"]
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "demo"
}

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "fleet-demo"
}

# Fleet Manager Configuration
variable "fleet_name" {
  description = "Name of the Azure Kubernetes Fleet Manager"
  type        = string
  default     = "multicluster-fleet"
}

# AKS Cluster Configuration
variable "aks_cluster_prefix" {
  description = "Prefix for AKS cluster names"
  type        = string
  default     = "aks-fleet"
}

variable "aks_node_count" {
  description = "Number of nodes in each AKS cluster"
  type        = number
  default     = 2
}

variable "aks_node_vm_size" {
  description = "VM size for AKS nodes"
  type        = string
  default     = "Standard_DS2_v2"
}

variable "kubernetes_version" {
  description = "Kubernetes version for AKS clusters"
  type        = string
  default     = "1.28.5"
}

variable "network_plugin" {
  description = "Network plugin for AKS clusters"
  type        = string
  default     = "azure"
}

variable "network_policy" {
  description = "Network policy for AKS clusters"
  type        = string
  default     = "azure"
}

# Azure Service Operator Configuration
variable "aso_namespace" {
  description = "Namespace for Azure Service Operator"
  type        = string
  default     = "azureserviceoperator-system"
}

variable "aso_service_principal_name" {
  description = "Name of the service principal for Azure Service Operator"
  type        = string
  default     = "sp-aso-fleet"
}

variable "aso_crd_pattern" {
  description = "CRD pattern for Azure Service Operator"
  type        = string
  default     = "resources.azure.com/*;containerservice.azure.com/*;keyvault.azure.com/*;containerregistry.azure.com/*;storage.azure.com/*"
}

# Container Registry Configuration
variable "acr_name" {
  description = "Name of the Azure Container Registry (will be suffixed with random string)"
  type        = string
  default     = "acrfleet"
}

variable "acr_sku" {
  description = "SKU for Azure Container Registry"
  type        = string
  default     = "Standard"
}

# Key Vault Configuration
variable "key_vault_name" {
  description = "Name of the Azure Key Vault (will be suffixed with random string)"
  type        = string
  default     = "kv-fleet"
}

variable "key_vault_sku" {
  description = "SKU for Azure Key Vault"
  type        = string
  default     = "standard"
}

variable "key_vault_soft_delete_retention_days" {
  description = "Soft delete retention days for Key Vault"
  type        = number
  default     = 7
}

# Storage Account Configuration
variable "storage_account_prefix" {
  description = "Prefix for storage account names"
  type        = string
  default     = "stfleet"
}

variable "storage_account_tier" {
  description = "Performance tier for storage accounts"
  type        = string
  default     = "Standard"
}

variable "storage_account_replication_type" {
  description = "Replication type for storage accounts"
  type        = string
  default     = "LRS"
}

variable "storage_account_kind" {
  description = "Kind of storage account"
  type        = string
  default     = "StorageV2"
}

variable "storage_account_access_tier" {
  description = "Access tier for storage accounts"
  type        = string
  default     = "Hot"
}

# Application Configuration
variable "app_namespace" {
  description = "Namespace for the fleet application"
  type        = string
  default     = "fleet-app"
}

variable "app_replicas" {
  description = "Number of replicas for the application"
  type        = number
  default     = 2
}

variable "app_image" {
  description = "Container image for the application"
  type        = string
  default     = "mcr.microsoft.com/azuredocs/aks-helloworld:v1"
}

# Cert Manager Configuration
variable "cert_manager_version" {
  description = "Version of cert-manager to install"
  type        = string
  default     = "v1.14.1"
}

variable "cert_manager_namespace" {
  description = "Namespace for cert-manager"
  type        = string
  default     = "cert-manager"
}

# Tags
variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Environment = "demo"
    Project     = "fleet-demo"
    Purpose     = "fleet-demo"
  }
}