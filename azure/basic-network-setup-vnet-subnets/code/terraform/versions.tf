# Terraform configuration block specifying required providers and versions
# This ensures consistent behavior across different environments and team members

terraform {
  # Minimum Terraform version required for this configuration
  required_version = ">= 1.0"

  # Required providers with version constraints
  required_providers {
    # Azure Resource Manager provider for managing Azure resources
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }

    # Random provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
  }
}

# Configure the Azure Provider with recommended settings
provider "azurerm" {
  # Enable all provider features for comprehensive resource management
  features {
    # Resource group management features
    resource_group {
      # Prevent accidental deletion of non-empty resource groups
      prevent_deletion_if_contains_resources = false
    }

    # Network security group management features
    network {
      # Relaxed deletion requirements for development environments
      relaxed_locking = true
    }
  }
}