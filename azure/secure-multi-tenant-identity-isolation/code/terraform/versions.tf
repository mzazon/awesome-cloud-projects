# Terraform and Provider Version Requirements
# This configuration specifies the minimum versions required for Terraform and the Azure Provider

terraform {
  required_version = ">= 1.5.0"
  
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.80"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.45"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}

# Configure the Azure Provider
provider "azurerm" {
  features {
    # Enable automatic deletion of resources in resource groups when they are deleted
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    
    # Configure Key Vault settings for secure secret management
    key_vault {
      purge_soft_delete_on_destroy    = false
      recover_soft_deleted_key_vaults = true
    }
    
    # Configure API Management settings
    api_management {
      purge_soft_delete_on_destroy = false
      recover_soft_deleted         = true
    }
  }
}

# Configure Azure AD Provider for External ID tenant management
provider "azuread" {
  # Azure AD provider configuration is inherited from Azure CLI authentication
}

# Configure Random Provider for generating unique resource names
provider "random" {
  # Random provider requires no additional configuration
}