# Variables for Azure GitOps CI/CD with Workload Identity and ArgoCD
# These variables allow customization of the deployment for different environments

variable "resource_group_name" {
  description = "Name of the Azure resource group"
  type        = string
  default     = "rg-gitops-demo"

  validation {
    condition     = length(var.resource_group_name) > 0 && length(var.resource_group_name) <= 90
    error_message = "Resource group name must be between 1 and 90 characters."
  }
}

variable "location" {
  description = "Azure region for all resources"
  type        = string
  default     = "East US"

  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3", "Central US",
      "North Central US", "South Central US", "West Central US", "Canada Central",
      "Canada East", "Brazil South", "North Europe", "West Europe", "UK South",
      "UK West", "France Central", "Germany West Central", "Switzerland North",
      "Norway East", "Sweden Central", "Australia East", "Australia Southeast",
      "East Asia", "Southeast Asia", "Japan East", "Japan West", "Korea Central",
      "India Central", "South Africa North", "UAE North"
    ], var.location)
    error_message = "Location must be a valid Azure region."
  }
}

variable "cluster_name" {
  description = "Name of the AKS cluster"
  type        = string
  default     = "aks-gitops-cluster"

  validation {
    condition     = length(var.cluster_name) >= 1 && length(var.cluster_name) <= 63
    error_message = "Cluster name must be between 1 and 63 characters."
  }
}

variable "node_count" {
  description = "Number of nodes in the default node pool"
  type        = number
  default     = 3

  validation {
    condition     = var.node_count >= 1 && var.node_count <= 100
    error_message = "Node count must be between 1 and 100."
  }
}

variable "node_vm_size" {
  description = "VM size for the default node pool"
  type        = string
  default     = "Standard_D2s_v3"

  validation {
    condition = contains([
      "Standard_D2s_v3", "Standard_D4s_v3", "Standard_D8s_v3", "Standard_D16s_v3",
      "Standard_D2as_v4", "Standard_D4as_v4", "Standard_D8as_v4", "Standard_D16as_v4",
      "Standard_B2s", "Standard_B4ms", "Standard_B8ms", "Standard_B12ms", "Standard_B16ms"
    ], var.node_vm_size)
    error_message = "VM size must be a valid Azure VM size."
  }
}

variable "kubernetes_version" {
  description = "Kubernetes version for the AKS cluster"
  type        = string
  default     = null
}

variable "key_vault_name" {
  description = "Name of the Azure Key Vault (will be suffixed with random string)"
  type        = string
  default     = "kv-gitops"

  validation {
    condition     = length(var.key_vault_name) >= 3 && length(var.key_vault_name) <= 24
    error_message = "Key Vault name must be between 3 and 24 characters."
  }
}

variable "managed_identity_name" {
  description = "Name of the user-assigned managed identity (will be suffixed with random string)"
  type        = string
  default     = "mi-argocd"

  validation {
    condition     = length(var.managed_identity_name) >= 3 && length(var.managed_identity_name) <= 128
    error_message = "Managed identity name must be between 3 and 128 characters."
  }
}

variable "argocd_namespace" {
  description = "Kubernetes namespace for ArgoCD"
  type        = string
  default     = "argocd"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.argocd_namespace))
    error_message = "Namespace must be a valid Kubernetes namespace name."
  }
}

variable "sample_app_namespace" {
  description = "Kubernetes namespace for sample application"
  type        = string
  default     = "sample-app"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.sample_app_namespace))
    error_message = "Namespace must be a valid Kubernetes namespace name."
  }
}

variable "argocd_version" {
  description = "Version of ArgoCD to install"
  type        = string
  default     = "5.51.6"
}

variable "enable_argocd_ui_loadbalancer" {
  description = "Whether to expose ArgoCD UI via LoadBalancer service"
  type        = bool
  default     = false
}

variable "enable_azure_monitor" {
  description = "Enable Azure Monitor for containers"
  type        = bool
  default     = true
}

variable "enable_azure_policy" {
  description = "Enable Azure Policy addon for AKS"
  type        = bool
  default     = false
}

variable "enable_network_policy" {
  description = "Enable network policy for AKS (Azure or Calico)"
  type        = string
  default     = "azure"

  validation {
    condition     = contains(["azure", "calico", ""], var.enable_network_policy)
    error_message = "Network policy must be 'azure', 'calico', or empty string."
  }
}

variable "sku_tier" {
  description = "SKU tier for the AKS cluster"
  type        = string
  default     = "Free"

  validation {
    condition     = contains(["Free", "Paid"], var.sku_tier)
    error_message = "SKU tier must be 'Free' or 'Paid'."
  }
}

variable "sample_secrets" {
  description = "Sample secrets to store in Key Vault for demonstration"
  type = map(string)
  default = {
    "database-connection-string" = "Server=myserver;Database=mydb;User=myuser;Password=mypass"
    "api-key"                    = "your-secure-api-key-here"
  }
  sensitive = true
}

variable "git_repository_url" {
  description = "Git repository URL for ArgoCD application source"
  type        = string
  default     = "https://github.com/Azure-Samples/aks-store-demo.git"
}

variable "git_target_revision" {
  description = "Git target revision (branch, tag, or commit) for ArgoCD application"
  type        = string
  default     = "HEAD"
}

variable "git_path" {
  description = "Path within Git repository for ArgoCD application manifests"
  type        = string
  default     = "kustomize/overlays/dev"
}

variable "auto_sync_enabled" {
  description = "Enable automatic synchronization for ArgoCD applications"
  type        = bool
  default     = true
}

variable "self_heal_enabled" {
  description = "Enable self-healing for ArgoCD applications"
  type        = bool
  default     = true
}

variable "prune_enabled" {
  description = "Enable pruning for ArgoCD applications"
  type        = bool
  default     = true
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default = {
    Purpose     = "gitops-demo"
    Environment = "development"
    Project     = "azure-gitops-argocd"
    ManagedBy   = "terraform"
  }
}