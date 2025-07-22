# Terraform version and provider requirements for Azure smart manufacturing digital twins solution
# This file defines the minimum Terraform version and required providers with their versions

terraform {
  required_version = ">= 1.5"
  
  required_providers {
    # Azure Resource Manager provider for core Azure resources
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.80"
    }
    
    # Azure Active Directory provider for role assignments and user management
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.45"
    }
    
    # Random provider for generating unique resource names and suffixes
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
    
    # Time provider for managing resource creation delays and dependencies
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
  }
}

# Configure the Azure Provider features
provider "azurerm" {
  features {
    # Enable enhanced resource group management
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    
    # Configure Key Vault features for secure credential management
    key_vault {
      purge_soft_delete_on_destroy    = false
      recover_soft_deleted_key_vaults = false
    }
    
    # Configure storage account features for data lake capabilities
    storage {
      prevent_nested_items_deletion = false
    }
  }
}

# Configure Azure AD provider
provider "azuread" {
  # Use default tenant from Azure CLI authentication
}