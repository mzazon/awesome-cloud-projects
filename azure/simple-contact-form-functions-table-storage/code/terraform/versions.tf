# Terraform and provider version requirements
# This file defines the minimum required versions for Terraform and the Azure provider

terraform {
  # Minimum Terraform version required for this configuration
  required_version = ">= 1.3"

  # Required providers and their version constraints
  required_providers {
    # Azure Resource Manager provider for managing Azure resources
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }

    # Random provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
  }
}

# Configure the Azure Provider with required features
provider "azurerm" {
  # Enable the features block to use the latest AzureRM provider functionality
  features {
    # Storage account feature configuration
    storage {
      # Prevent accidental deletion of storage accounts
      prevent_deletion_if_contains_resources = true
    }
    
    # App Service (Function App) feature configuration
    app_service {
      # Purge soft deleted app service plans on destroy
      purge_soft_deleted_on_destroy = true
    }
  }
}

# Configure the Random provider (no configuration needed)
provider "random" {}