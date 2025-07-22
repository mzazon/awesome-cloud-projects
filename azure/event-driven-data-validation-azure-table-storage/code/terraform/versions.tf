# Terraform and Provider Version Requirements
# This file defines the required Terraform version and provider versions for the
# real-time data validation workflow infrastructure

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
      version = "~> 3.1"
    }
    
    # Archive provider for creating deployment packages
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.2"
    }
  }
}

# Configure the Azure Provider
provider "azurerm" {
  features {
    # Enable enhanced features for resource management
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    
    # Configure storage account features
    storage {
      # Prevent deletion of storage containers with blobs
      prevent_deletion_if_contains_resources = false
    }
    
    # Configure key vault features
    key_vault {
      # Purge soft deleted key vaults on destroy
      purge_soft_delete_on_destroy    = true
      # Recover soft deleted key vaults on create
      recover_soft_deleted_key_vaults = true
    }
  }
}

# Random provider configuration for unique naming
provider "random" {}

# Archive provider configuration for deployment packages
provider "archive" {}