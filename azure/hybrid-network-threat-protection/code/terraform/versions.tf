# Terraform and Provider Version Requirements
# This file defines the required Terraform version and provider versions for the hybrid network security solution

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
    
    # Time provider for resource timing and delays
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
  }
}

# Configure the Azure Provider
provider "azurerm" {
  features {
    # Enable soft delete for Key Vault resources
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
    
    # Configure resource group deletion behavior
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    
    # Configure Log Analytics workspace deletion behavior
    log_analytics_workspace {
      permanently_delete_on_destroy = true
    }
  }
}

# Configure the Random Provider
provider "random" {}

# Configure the Time Provider
provider "time" {}