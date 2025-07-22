# Terraform and Provider Version Constraints
# This file defines the required Terraform version and provider versions
# for the Azure geospatial analytics infrastructure

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
  }
}

# Configure the Azure Provider
provider "azurerm" {
  features {
    # Enable enhanced security features
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    
    # Key Vault configuration
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
    
    # Storage account configuration
    storage {
      prevent_nested_items_deletion = false
    }
  }
}

# Configure Random Provider for unique naming
provider "random" {}

# Configure Time Provider for resource delays
provider "time" {}