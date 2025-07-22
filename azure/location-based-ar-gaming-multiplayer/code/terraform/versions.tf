# Provider requirements and version constraints
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
  }
}

# Configure the Azure Provider
provider "azurerm" {
  features {
    # Enable enhanced features for resource management
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    
    # Configure key vault features
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
    
    # Configure storage account features
    storage_account {
      prevent_deletion_if_contains_resources = false
    }
  }
}

# Configure Azure Active Directory provider
provider "azuread" {
  # Configuration will be inherited from Azure CLI or environment variables
}

# Configure random provider for generating unique suffixes
provider "random" {
  # No specific configuration required
}