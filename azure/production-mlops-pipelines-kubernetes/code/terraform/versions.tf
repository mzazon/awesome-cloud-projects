# Terraform version and provider requirements for MLOps Pipeline
# This file defines the minimum required versions for Terraform and providers

terraform {
  required_version = ">= 1.0"

  required_providers {
    # Azure Resource Manager Provider
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    
    # Random Provider for generating unique names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    
    # Null Provider for provisioners and data sources
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
    
    # Time Provider for time-based operations
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
    
    # Kubernetes Provider for post-deployment configuration
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
      optional = true
    }
  }

  # Optional: Configure backend for state management
  # Uncomment and configure for production deployments
  # backend "azurerm" {
  #   resource_group_name  = "rg-terraform-state"
  #   storage_account_name = "terraformstate"
  #   container_name       = "tfstate"
  #   key                  = "mlops-pipeline.terraform.tfstate"
  # }
}

# Provider configuration for Azure Resource Manager
provider "azurerm" {
  features {
    # Key Vault configuration
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
    
    # Resource Group configuration
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    
    # Storage Account configuration
    storage_account {
      prevent_deletion_if_contains_resources = false
    }
    
    # Machine Learning configuration
    machine_learning {
      purge_soft_deleted_workspace_on_destroy = true
    }
    
    # Container Registry configuration
    container_registry {
      export_policy_enabled = true
    }
  }
}

# Optional: Kubernetes provider configuration for post-deployment setup
# Uncomment if you need to configure Kubernetes resources after AKS deployment
# provider "kubernetes" {
#   host                   = azurerm_kubernetes_cluster.mlops_aks.kube_config.0.host
#   client_certificate     = base64decode(azurerm_kubernetes_cluster.mlops_aks.kube_config.0.client_certificate)
#   client_key             = base64decode(azurerm_kubernetes_cluster.mlops_aks.kube_config.0.client_key)
#   cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.mlops_aks.kube_config.0.cluster_ca_certificate)
# }