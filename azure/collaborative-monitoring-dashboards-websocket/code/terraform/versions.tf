# Provider version requirements for Azure collaborative dashboard infrastructure
terraform {
  required_version = ">= 1.5"
  
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

# Configure the Azure Provider with enhanced features
provider "azurerm" {
  features {
    # Enhanced resource group deletion behavior
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    
    # Key vault configuration for soft delete handling
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
    
    # Application insights configuration
    application_insights {
      disable_generated_rule = true
    }
  }
}

# Configure Azure AD provider for identity management
provider "azuread" {
  # Uses the same authentication as azurerm provider
}