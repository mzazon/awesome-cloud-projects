# Terraform configuration for AI Code Review Assistant with Reasoning and Functions
# This file defines the required providers and their versions

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    # Azure Resource Manager provider for managing Azure resources
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.80"
    }
    
    # Random provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}

# Configure the Azure Provider with required features
provider "azurerm" {
  features {
    # Configure resource group behavior
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    
    # Configure storage account behavior
    storage {
      prevent_nested_items_removal = false
    }
    
    # Configure Cognitive Services behavior
    cognitive_account {
      purge_soft_delete_on_destroy = true
    }
  }
}