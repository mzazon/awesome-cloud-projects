# Terraform and Provider Version Requirements
# This file defines the required versions for Terraform and the Azure provider

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    # Azure Resource Manager Provider
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    
    # Random Provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
    
    # Archive Provider for packaging Function App code
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }
}

# Configure the Azure Provider
provider "azurerm" {
  features {
    # Configure feature flags for the Azure provider
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
    
    log_analytics_workspace {
      permanently_delete_on_destroy = true
    }
  }
}

# Configure the Random Provider
provider "random" {}

# Configure the Archive Provider
provider "archive" {}