# Terraform configuration for Azure resource organization with resource groups and tags
# This file defines the required provider versions and configuration

terraform {
  required_version = ">= 1.5.0"
  
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
  }
}

# Configure the Microsoft Azure Provider
provider "azurerm" {
  features {
    # Enable enhanced resource group deletion behavior
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    
    # Configure storage account deletion behavior
    storage {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_storage    = true
    }
  }
}