terraform {
  required_version = ">= 1.0"
  
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0"
    }
  }
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
  }
}

provider "azuread" {}

provider "random" {}

# Kubernetes provider configuration will be set up after AKS clusters are created
provider "kubernetes" {
  alias = "cluster1"
}

provider "kubernetes" {
  alias = "cluster2"
}

provider "kubernetes" {
  alias = "cluster3"
}

# Helm provider configuration will be set up after AKS clusters are created
provider "helm" {
  alias = "cluster1"
}

provider "helm" {
  alias = "cluster2"
}

provider "helm" {
  alias = "cluster3"
}