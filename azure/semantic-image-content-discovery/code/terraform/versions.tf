# Terraform and Provider Version Constraints
# This file defines the required Terraform version and provider versions
# for the intelligent image content discovery infrastructure

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    # Azure Resource Manager provider for core Azure resources
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    
    # Random provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
    
    # Archive provider for function app deployment packages
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.2"
    }
  }
}

# Configure the Azure Provider with features
provider "azurerm" {
  features {
    # Configure storage account behavior
    storage {
      delete_protection = false
    }
    
    # Configure cognitive services behavior
    cognitive_account {
      purge_soft_delete_on_destroy = true
    }
    
    # Configure resource group behavior
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}