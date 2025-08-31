# Azure Container Registry and Container Instances Terraform Configuration
# This file defines the Terraform version requirements and provider configurations
# for deploying a simple web container with Azure Container Instances and Azure Container Registry

terraform {
  # Minimum Terraform version required for this configuration
  required_version = ">= 1.6"

  # Required providers with version constraints
  required_providers {
    # Azure Resource Manager provider for managing Azure resources
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }

    # Random provider for generating random values for unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# Configure the Azure Provider
# This provider configuration enables all Azure Resource Manager features
provider "azurerm" {
  # Enable all features for the Azure Resource Manager provider
  features {
    # Resource Group settings
    resource_group {
      # Prevent deletion of resource groups that contain resources
      prevent_deletion_if_contains_resources = false
    }

    # Container Registry settings
    container_registry {
      # Automatically delete container images when the registry is deleted
      delete_on_destroy = true
    }
  }

  # Skip provider registration for faster deployment
  # Set to false if you need to register providers in your subscription
  skip_provider_registration = false
}

# Random provider configuration
provider "random" {
  # No additional configuration needed for the random provider
}