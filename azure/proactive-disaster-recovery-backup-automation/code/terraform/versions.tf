# Terraform provider requirements for Azure disaster recovery infrastructure
# This file defines the required providers and their versions for deploying
# intelligent disaster recovery orchestration with Azure Backup Center and Monitor

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    # Azure Resource Manager provider for core Azure resources
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.85"
    }
    
    # Azure Active Directory provider for identity management
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.45"
    }
    
    # Random provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# Configure the Azure Provider with features for disaster recovery
provider "azurerm" {
  features {
    # Enable key vault features for secure backup operations
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
    
    # Enable recovery services features for backup operations
    recovery_services_vault {
      purge_soft_delete_on_destroy = true
      recover_soft_deleted_vault   = true
    }
    
    # Enable resource group features
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

# Configure the Azure AD Provider for identity management
provider "azuread" {
  # Provider will use the current authenticated context
}