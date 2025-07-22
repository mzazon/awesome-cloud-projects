# =============================================================================
# Provider and Terraform Version Requirements
# Self-Service Infrastructure Lifecycle with Azure Deployment Environments
# =============================================================================

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    # Azure Resource Manager provider for managing Azure resources
    # Version 4.x required for Azure DevCenter and Deployment Environments support
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    
    # Azure Active Directory provider for identity and access management
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.0"
    }
    
    # Random provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4"
    }
    
    # Time provider for resource delays and scheduling
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
  }
}

# Configure the Azure Provider features
provider "azurerm" {
  features {
    # Enable enhanced security features for key vault
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
    
    # Configure resource group behavior
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    
    # Configure storage account behavior
    storage {
      use_legacy_version               = false
      prevent_nested_items_destruction = false
    }
  }
}

# Configure Azure AD provider
provider "azuread" {
  # Use default configuration from Azure CLI or managed identity
}

# Configure random provider
provider "random" {
  # Use default configuration
}

# Configure time provider
provider "time" {
  # Use default configuration
}