# Terraform and Provider Version Requirements
# This file defines the minimum required versions for Terraform and Azure providers

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    # Azure Resource Manager Provider
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.80"
    }

    # Azure Active Directory Provider for identity management
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.45"
    }

    # Random provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }

    # Time provider for resource creation delays
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
  }
}

# Configure the Azure Provider with required features
provider "azurerm" {
  features {
    # Key Vault configuration
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }

    # Storage Account configuration
    storage {
      prevent_deletion_if_contains_resources = false
    }

    # Resource Group configuration
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

# Configure Azure AD Provider
provider "azuread" {
  # Use default tenant
}