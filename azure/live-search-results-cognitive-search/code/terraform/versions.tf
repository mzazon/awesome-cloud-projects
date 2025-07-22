# versions.tf
# Terraform and provider version requirements for Azure real-time search application

terraform {
  required_version = ">= 1.5"
  
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
      version = "~> 3.5"
    }
  }
}

# Configure the Azure Provider
provider "azurerm" {
  features {
    # Enable enhanced resource group deletion
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    
    # Enable enhanced key vault features
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
    
    # Enable cognitive services account deletion
    cognitive_account {
      purge_soft_delete_on_destroy = true
    }
  }
}

# Configure Azure AD Provider
provider "azuread" {
  # Azure AD provider configuration
}

# Configure Random Provider
provider "random" {
  # Random provider configuration
}