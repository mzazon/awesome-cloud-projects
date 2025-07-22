# Terraform and Provider Version Requirements
# This file defines the required Terraform version and provider versions for the
# stateful workload monitoring solution with Azure Container Storage and Azure Managed Prometheus

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    # Azure Resource Manager Provider
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.80"
    }
    
    # Azure Active Directory Provider for identity management
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.46"
    }
    
    # Random provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    
    # Local provider for local computations
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }
    
    # Time provider for time-based operations
    time = {
      source  = "hashicorp/time"
      version = "~> 0.10"
    }
  }
}

# Configure the Azure Provider
provider "azurerm" {
  features {
    # Enable deletion of items in the key vault on destroy
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
    
    # Configure resource group deletion behavior
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    
    # Configure Log Analytics workspace behavior
    log_analytics_workspace {
      permanently_delete_on_destroy = true
    }
  }
}

# Configure the Azure AD Provider
provider "azuread" {
  # Configuration will be inherited from Azure CLI or environment variables
}