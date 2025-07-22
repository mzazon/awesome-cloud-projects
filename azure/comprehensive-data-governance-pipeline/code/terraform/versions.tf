# Terraform and Provider Version Constraints
# This file defines the required Terraform version and provider versions for the
# Azure Purview and Data Lake Storage governance solution

terraform {
  # Require Terraform version 1.0 or higher for stability and feature support
  required_version = ">= 1.0"

  # Required providers with version constraints
  required_providers {
    # Azure Resource Manager provider for Azure services
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.80"
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

# Configure the Azure Provider features
provider "azurerm" {
  features {
    # Key Vault configuration for secure secret management
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }

    # Resource Group configuration for cleanup behavior
    resource_group {
      prevent_deletion_if_contains_resources = false
    }

    # Storage Account configuration for data lake features
    storage {
      prevent_deletion_if_contains_resources = false
    }
  }
}