# Terraform and Provider Version Requirements
# This file defines the minimum required versions for Terraform and providers

terraform {
  # Minimum Terraform version required
  required_version = ">= 1.6"

  # Required providers with version constraints
  required_providers {
    # Azure Resource Manager provider for Azure resources
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.84"
    }

    # Random provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4"
    }

    # Local provider for creating local files (used for API configurations)
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }

    # Null provider for executing local commands (used for AI Search API calls)
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

# Configure the Azure Provider with required features
provider "azurerm" {
  features {
    # Enable soft delete purging for Cognitive Services (OpenAI)
    # This allows for immediate recreation of OpenAI services during development
    cognitive_account {
      purge_soft_delete_on_destroy = true
    }

    # Configure Key Vault behavior (if used in future extensions)
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }

    # Configure Resource Group behavior
    resource_group {
      prevent_deletion_if_contains_resources = false
    }

    # Configure App Service behavior
    app_service {
      purge_disabled_services_on_destroy = true
    }
  }

  # Optional: Configure provider settings
  # storage_use_azuread = true  # Use Azure AD for storage authentication (recommended for production)
}

# Configure the Random provider
provider "random" {
  # No specific configuration required
}

# Configure the Local provider
provider "local" {
  # No specific configuration required
}

# Configure the Null provider
provider "null" {
  # No specific configuration required
}