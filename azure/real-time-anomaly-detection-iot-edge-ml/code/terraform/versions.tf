# Terraform and Provider Version Requirements
# This file defines the required versions for Terraform and Azure providers

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    # Azure Resource Manager provider for core Azure resources
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    
    # Azure Active Directory provider for identity management
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.0"
    }
    
    # Random provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    
    # Time provider for managing time-based resources
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
  }
}

# Configure the Azure Provider
provider "azurerm" {
  features {
    # Enable key vault purge protection features
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
    
    # Resource group features
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    
    # Log analytics workspace features
    log_analytics_workspace {
      permanently_delete_on_destroy = true
    }
  }
}

# Configure the Azure AD Provider
provider "azuread" {
  # Configuration will be inherited from Azure CLI or environment variables
}