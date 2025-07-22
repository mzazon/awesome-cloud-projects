# Terraform and Provider Version Requirements
# This file defines the required Terraform version and provider versions
# for the automated network security orchestration solution

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
    azapi = {
      source  = "Azure/azapi"
      version = "~> 1.5"
    }
  }
}

# Configure the Azure Provider
provider "azurerm" {
  features {
    # Enable enhanced security features
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
    
    # Configure resource group behavior
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    
    # Configure storage account behavior
    storage {
      prevent_deletion_if_contains_resources = false
    }
  }
}

# Configure the Azure API Provider for advanced resources
provider "azapi" {
  # This provider is used for resources not yet fully supported in azurerm
}

# Configure the Random Provider for unique naming
provider "random" {
  # Used for generating unique suffixes and identifiers
}