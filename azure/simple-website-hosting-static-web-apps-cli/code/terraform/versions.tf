# Terraform and Provider Version Requirements
# This file defines the minimum required versions for Terraform and providers

terraform {
  # Require Terraform version 1.0 or higher for stability and feature support
  required_version = ">= 1.0"

  # Define required providers with version constraints
  required_providers {
    # Azure Resource Manager provider for managing Azure resources
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"  # Use latest 3.x version for current feature support
    }

    # Random provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4"  # Latest stable version for random resource generation
    }
  }
}

# Configure the Azure Provider with recommended features
provider "azurerm" {
  # Enable all resource provider features for comprehensive service support
  features {
    # Configure resource group behavior
    resource_group {
      # Prevent accidental deletion of non-empty resource groups
      prevent_deletion_if_contains_resources = true
    }
  }

  # Skip provider registration to avoid unnecessary API calls
  # Set to true if using service principal with limited permissions
  skip_provider_registration = false
}