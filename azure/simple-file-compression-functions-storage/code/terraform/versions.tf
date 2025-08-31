# Terraform version and provider requirements
# This file defines the minimum Terraform version and required providers
# for the simple file compression with Azure Functions and Storage solution

terraform {
  # Require minimum Terraform version 1.0 for latest features and stability
  required_version = ">= 1.0"

  # Define required providers with version constraints
  required_providers {
    # Azure Resource Manager provider for core Azure resources
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.80"
    }

    # Azure Active Directory provider for identity and access management
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.45"
    }

    # Random provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4"
    }

    # Archive provider for creating function app deployment packages
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

# Configure the Azure Provider with features
provider "azurerm" {
  features {
    # Configure resource group behavior
    resource_group {
      # Prevent accidental deletion of resource groups containing resources
      prevent_deletion_if_contains_resources = true
    }

    # Configure storage account behavior
    storage {
      # Prevent accidental deletion of storage accounts with data
      prevent_deletion_if_contains_data = true
    }

    # Configure key vault behavior for any future security enhancements
    key_vault {
      # Purge soft deleted key vaults on destroy for clean testing
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
  }

  # Skip provider registration for faster deployment (optional)
  # Uncomment if you have necessary resource providers already registered
  # skip_provider_registration = true
}

# Configure Azure AD provider
provider "azuread" {
  # Use default configuration from Azure CLI or environment variables
}

# Configure Random provider
provider "random" {
  # Use default configuration
}

# Configure Archive provider
provider "archive" {
  # Use default configuration
}