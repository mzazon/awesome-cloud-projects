# Terraform and Provider Version Requirements
# This file defines the required versions for Terraform and providers
# used in the user onboarding workflow infrastructure

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
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
  }
}

# Configure the Azure Provider
provider "azurerm" {
  features {
    # Enable soft delete for Key Vault
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
    
    # Configure resource group behavior
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

# Configure the Azure AD Provider
provider "azuread" {
  # Uses the same authentication as azurerm provider
}