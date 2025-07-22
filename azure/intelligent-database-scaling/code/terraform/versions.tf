# Terraform and Provider Version Requirements
# This file defines the minimum required versions for Terraform and providers

terraform {
  required_version = ">= 1.5.0"
  
  required_providers {
    # Azure Resource Manager provider for managing Azure resources
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.80"
    }
    
    # Random provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4"
    }
    
    # Azure Active Directory provider for RBAC assignments
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.45"
    }
  }
}

# Configure the Azure Provider features
provider "azurerm" {
  features {
    # Automatically delete resources in resource group when it's deleted
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    
    # Key Vault configuration for soft delete and purge protection
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
    
    # SQL Server configuration
    mssql_server {
      # Enable extended auditing policy by default
      extended_auditing_enabled = true
    }
  }
}

# Configure the Azure AD Provider
provider "azuread" {}

# Configure the Random Provider  
provider "random" {}