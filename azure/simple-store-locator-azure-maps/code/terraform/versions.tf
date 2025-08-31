# Terraform provider requirements for Azure Maps Store Locator
# This file defines the minimum required versions for Terraform and the Azure provider

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    # Azure Resource Manager provider for managing Azure resources
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    
    # Random provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4"
    }
  }
}

# Configure the Azure Provider with required features
provider "azurerm" {
  features {
    # Enable enhanced resource group management
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}