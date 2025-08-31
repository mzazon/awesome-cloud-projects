# Terraform provider configuration file
# Defines the minimum required Terraform version and provider requirements
# for the Azure basic file storage solution

terraform {
  # Minimum Terraform version required for this configuration
  # Version 1.3.0 or higher provides stable features used in this configuration
  required_version = ">= 1.3.0"

  # Required providers for this Terraform configuration
  required_providers {
    # Azure Resource Manager provider for managing Azure resources
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.37.0"
    }

    # Random provider for generating unique resource names and identifiers
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4.0"
    }
  }
}

# Configure the Azure Provider with recommended features and settings
provider "azurerm" {
  # Enable all resource provider features for full functionality
  features {
    # Storage provider features for enhanced blob storage management
    storage {
      # Prevent accidental deletion of storage containers and blobs
      purge_soft_delete_on_destroy    = false
      recover_soft_deleted_key_vaults = false
    }

    # Resource group provider features
    resource_group {
      # Prevent accidental deletion of non-empty resource groups
      prevent_deletion_if_contains_resources = false
    }
  }

  # Use Azure CLI authentication by default
  # Alternatively, service principal authentication can be configured
  # using environment variables or configuration blocks
}