# Terraform version and provider requirements
# This file defines the minimum versions for Terraform and required providers

terraform {
  # Minimum Terraform version required
  required_version = ">= 1.0"

  # Required providers with version constraints
  required_providers {
    # Azure Resource Manager provider for managing Azure resources
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.80"
    }

    # Random provider for generating unique suffixes
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4"
    }

    # Time provider for managing time-based resources
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
  }
}

# Configure the Azure Provider
provider "azurerm" {
  # Enable features for advanced resource management
  features {
    # Enable advanced key vault features
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }

    # Enable advanced resource group features
    resource_group {
      prevent_deletion_if_contains_resources = false
    }

    # Enable advanced virtual machine features
    virtual_machine {
      delete_os_disk_on_deletion     = true
      graceful_shutdown              = false
      skip_shutdown_and_force_delete = false
    }
  }
}