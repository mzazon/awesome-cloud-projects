# Terraform version and provider requirements for Azure Private 5G deployment
terraform {
  required_version = ">= 1.0"

  required_providers {
    # Azure Resource Manager provider for core Azure resources
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.80"
    }

    # Azure Active Directory provider for identity management
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.40"
    }

    # Random provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4"
    }

    # Time provider for resource creation delays
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
  }
}

# Configure the Azure Provider
provider "azurerm" {
  features {
    # Enable key vault purge protection and soft delete
    key_vault {
      purge_soft_delete_on_destroy    = false
      recover_soft_deleted_key_vaults = true
    }

    # Configure resource group deletion behavior
    resource_group {
      prevent_deletion_if_contains_resources = false
    }

    # Configure Log Analytics workspace deletion behavior
    log_analytics_workspace {
      permanently_delete_on_destroy = false
    }
  }
}

# Configure Azure AD provider
provider "azuread" {
  # Uses the same authentication as azurerm provider
}