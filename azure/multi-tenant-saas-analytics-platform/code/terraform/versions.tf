# Terraform provider version constraints for Azure multi-tenant SaaS analytics solution
# This file defines the required providers and their version constraints

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    # Azure Resource Manager provider for core Azure resources
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    
    # Random provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4"
    }
    
    # Time provider for managing time-based resources
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
  }
}

# Configure Azure Provider with required features
provider "azurerm" {
  features {
    # Enable key vault purge protection and soft delete recovery
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
    
    # Enable resource group prevention of deletion when containing resources
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    
    # Configure Log Analytics workspace behavior
    log_analytics_workspace {
      permanently_delete_on_destroy = true
    }
  }
}