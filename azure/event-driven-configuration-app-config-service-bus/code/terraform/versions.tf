# Terraform and Provider Version Requirements
# This file defines the minimum required versions for Terraform and providers

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
      version = "~> 3.1"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.2"
    }
  }
}

# Azure Provider Configuration
provider "azurerm" {
  features {
    # Enable advanced features for resource management
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    
    # App Configuration specific features
    app_configuration {
      purge_soft_delete_on_destroy = true
      recover_soft_deleted         = true
    }
    
    # Key Vault features for secure configuration management
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
  }
}

# Azure AD Provider Configuration
provider "azuread" {
  # Use default configuration
}