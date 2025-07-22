# Terraform and Provider Version Requirements
# This file specifies the required Terraform version and provider versions

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
    
    # Time provider for resource dependencies and delays
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
  }
}

# Configure the Azure Provider
provider "azurerm" {
  features {
    # Configure resource group behavior
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    
    # Configure key vault behavior for development
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
    
    # Configure Cognitive Services account deletion
    cognitive_account {
      purge_soft_delete_on_destroy = true
    }
  }
}