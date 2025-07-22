# Terraform configuration for Azure Orbital and Azure Local edge-to-orbit data processing
# This file defines the required providers and their versions

terraform {
  required_version = ">= 1.5.0"
  
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.80"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.40"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.20"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.10"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
  }
}

# Configure the Azure Resource Manager Provider
provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
    
    storage {
      prevent_deletion_if_contains_resources = false
    }
  }
}

# Configure the Azure Active Directory Provider
provider "azuread" {
  # Configuration options
}

# Configure the Random Provider
provider "random" {
  # Configuration options
}

# Configure the Kubernetes Provider
provider "kubernetes" {
  # Configuration will be provided by Azure Local cluster
}

# Configure the Helm Provider
provider "helm" {
  # Configuration will be provided by Azure Local cluster
}

# Configure the Time Provider
provider "time" {
  # Configuration options
}