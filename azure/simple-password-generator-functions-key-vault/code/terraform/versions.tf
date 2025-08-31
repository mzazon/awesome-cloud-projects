# Terraform and Provider Requirements
# This file defines the minimum Terraform version and required providers for the password generator solution

terraform {
  required_version = ">= 1.5"
  
  required_providers {
    # Azure Resource Manager provider for managing Azure resources
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.80"
    }
    
    # Random provider for generating unique resource names and suffixes
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    
    # Archive provider for creating function app deployment packages
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

# Configure the Azure Provider with features
provider "azurerm" {
  features {
    # Key Vault configuration
    key_vault {
      # Don't purge Key Vault on destroy to allow recovery
      purge_soft_delete_on_destroy    = false
      recover_soft_deleted_key_vaults = true
    }
    
    # Resource Group configuration
    resource_group {
      # Prevent accidental deletion of non-empty resource groups
      prevent_deletion_if_contains_resources = false
    }
  }
}