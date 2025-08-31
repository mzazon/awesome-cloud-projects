# Terraform version and provider requirements for Azure Weather Dashboard
# This configuration uses the latest stable versions of the Azure provider
# and random provider for generating unique resource identifiers

terraform {
  # Require minimum Terraform version for latest language features
  required_version = ">= 1.0"

  required_providers {
    # Azure Resource Manager provider for managing Azure resources
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    
    # Random provider for generating unique names and secrets
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
  }
}

# Configure the Azure Provider with required features
provider "azurerm" {
  features {
    # Enable resource group deletion protection
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}