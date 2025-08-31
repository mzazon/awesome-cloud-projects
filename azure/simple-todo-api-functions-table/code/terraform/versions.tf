# =============================================================================
# Provider Requirements and Configuration
# =============================================================================
# This file defines the required Terraform version and Azure provider
# configuration for the Simple Todo API with Azure Functions and Table Storage

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4"
    }
  }
}

# Configure the Microsoft Azure Provider
provider "azurerm" {
  features {
    # Enable enhanced security features for storage accounts
    storage {
      # Prevent accidental deletion of storage accounts
      delete_files_on_destroy = false
    }
    
    # Configure resource group behavior
    resource_group {
      # Prevent accidental deletion of resource groups containing resources
      prevent_deletion_if_contains_resources = true
    }
  }
}