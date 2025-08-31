# Terraform and Provider Version Requirements
# This file defines the minimum required versions for Terraform and providers

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    # Azure Resource Manager provider for managing Azure resources
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    
    # Random provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

# Configure the Azure Provider features
provider "azurerm" {
  features {
    # Enable soft delete for storage accounts to prevent accidental data loss
    storage {
      delete_retention_policy {
        days = 7
      }
    }
    
    # Resource group deletion behavior
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}