# Terraform version and provider requirements for Azure Marketing Asset Generation
# This configuration defines the minimum Terraform version and required providers
# for deploying automated marketing content generation infrastructure on Azure

terraform {
  required_version = ">= 1.5"
  
  required_providers {
    # Azure Resource Manager provider for core Azure resources
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.80"
    }
    
    # Random provider for generating unique resource names and identifiers
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4"
    }
    
    # Time provider for managing resource creation delays and timestamps
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
  }
}

# Configure the Azure Provider with required features
provider "azurerm" {
  features {
    # Enable enhanced security features for Cognitive Services
    cognitive_account {
      purge_soft_deleted_on_destroy    = true
      purge_soft_delete_on_destroy     = true
    }
    
    # Enable advanced storage account management
    storage {
      prevent_nested_items_destruction = false
    }
    
    # Configure resource group management
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}