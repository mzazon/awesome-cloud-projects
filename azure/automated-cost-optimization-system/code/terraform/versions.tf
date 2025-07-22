# versions.tf - Provider version constraints and requirements
# This file defines the minimum required versions for Terraform and providers

terraform {
  required_version = ">= 1.5.0"
  
  required_providers {
    # Azure Resource Manager provider for managing Azure resources
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.80"
    }
    
    # Azure Active Directory provider for managing AD resources
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.45"
    }
    
    # Random provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
    
    # Time provider for handling time-based operations
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
  }
}

# Configure the Azure Provider with required features
provider "azurerm" {
  features {
    # Key Vault configuration
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
    
    # Storage account configuration
    storage {
      prevent_deletion_if_contains_resources = false
    }
    
    # Resource group configuration
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

# Configure the Azure Active Directory Provider
provider "azuread" {
  # Use the default tenant from the authenticated context
}