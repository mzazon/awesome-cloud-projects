# Terraform and Provider Version Requirements
# This file defines the minimum required versions for Terraform and providers

terraform {
  required_version = ">= 1.0"

  required_providers {
    # Azure Resource Manager provider for managing Azure resources
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }

    # Random provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4"
    }

    # Archive provider for creating zip files for function deployment
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
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
    
    # Configure Key Vault features
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
  }
}