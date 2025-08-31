# Terraform and Provider Version Configuration
# This file specifies the minimum Terraform version and required providers
# for the Azure File Sync infrastructure deployment

terraform {
  required_version = ">= 1.0"
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
# Features block is required for AzureRM provider v2.0+
provider "azurerm" {
  features {
    # Configure storage account settings
    storage {
      prevent_nested_items_deletion = false
    }
    
    # Configure resource group settings
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}