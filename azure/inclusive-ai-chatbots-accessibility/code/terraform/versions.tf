# Terraform and Provider Version Requirements
# This file specifies the minimum required versions for Terraform and providers

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    # Azure Resource Manager provider for managing Azure resources
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    
    # Azure AD provider for managing Azure Active Directory resources
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.0"
    }
    
    # Random provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

# Configure the Azure Resource Manager provider
provider "azurerm" {
  features {
    # Key Vault configuration for secure secret management
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
    
    # Cognitive Services configuration for AI services
    cognitive_services {
      purge_soft_delete_on_destroy = true
    }
    
    # Storage account configuration for bot state management
    storage {
      purge_soft_delete_on_destroy = true
    }
  }
}

# Configure the Azure AD provider
provider "azuread" {
  # Uses the same authentication as azurerm provider
}

# Configure the Random provider
provider "random" {
  # No specific configuration required
}