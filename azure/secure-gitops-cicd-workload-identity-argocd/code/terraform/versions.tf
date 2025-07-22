# Terraform and provider version requirements
# This configuration ensures compatibility and stability for Azure Workload Identity and ArgoCD deployment

terraform {
  required_version = ">= 1.5.0"
  
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.80"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.45"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.24"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}

# Configure the Azure Provider
provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    key_vault {
      purge_soft_delete_on_destroy = true
    }
  }
}

# Configure the Azure AD Provider
provider "azuread" {}

# Configure the Kubernetes Provider
# This will be configured after AKS cluster creation
provider "kubernetes" {
  host                   = try(azurerm_kubernetes_cluster.aks.kube_config[0].host, "")
  client_certificate     = try(base64decode(azurerm_kubernetes_cluster.aks.kube_config[0].client_certificate), "")
  client_key             = try(base64decode(azurerm_kubernetes_cluster.aks.kube_config[0].client_key), "")
  cluster_ca_certificate = try(base64decode(azurerm_kubernetes_cluster.aks.kube_config[0].cluster_ca_certificate), "")
}

# Configure the Helm Provider
provider "helm" {
  kubernetes {
    host                   = try(azurerm_kubernetes_cluster.aks.kube_config[0].host, "")
    client_certificate     = try(base64decode(azurerm_kubernetes_cluster.aks.kube_config[0].client_certificate), "")
    client_key             = try(base64decode(azurerm_kubernetes_cluster.aks.kube_config[0].client_key), "")
    cluster_ca_certificate = try(base64decode(azurerm_kubernetes_cluster.aks.kube_config[0].cluster_ca_certificate), "")
  }
}