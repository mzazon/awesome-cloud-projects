# Terraform version and provider requirements for Azure Tutorial Generator
terraform {
  required_version = ">= 1.5"
  
  required_providers {
    # Azure Resource Manager provider for managing Azure resources
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.70"
    }
    
    # Random provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
    
    # Archive provider for creating function deployment packages
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

# Configure the Azure Provider with features
provider "azurerm" {
  features {
    # Configure storage account features
    storage {
      # Prevent accidental deletion of storage accounts
      prevent_deletion_if_contains_resources = true
    }
    
    # Configure cognitive services features
    cognitive_services {
      # Purge soft deleted accounts on destroy
      purge_soft_delete_on_destroy = true
    }
    
    # Configure resource group features
    resource_group {
      # Prevent deletion of non-empty resource groups
      prevent_deletion_if_contains_resources = true
    }
  }
}