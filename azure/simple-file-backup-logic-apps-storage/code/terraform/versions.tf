# Terraform and Provider Version Constraints
# This file defines the minimum required versions for Terraform and providers
# to ensure compatibility and access to necessary features.

terraform {
  required_version = ">= 1.5.0"
  
  required_providers {
    # Azure Resource Manager provider for all Azure resources
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.80"
    }
    
    # Random provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4"
    }
    
    # Time provider for timestamp-based resources
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
  }
}

# Configure the Azure Provider with features block
provider "azurerm" {
  features {
    # Enable purge protection for Key Vault (not used in this recipe but good practice)
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
    
    # Storage account configuration
    storage {
      # Allow blob container soft delete to be disabled
      prevent_deletion_if_contains_resources = false
    }
    
    # Resource group configuration
    resource_group {
      # Allow resource group deletion even if it contains resources
      prevent_deletion_if_contains_resources = false
    }
  }
}