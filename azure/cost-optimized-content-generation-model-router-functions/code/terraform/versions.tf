# Terraform provider version requirements
# This file defines the required providers and their versions for the content generation solution

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
      version = "~> 3.1"
    }
    
    # Time provider for resource dependencies and delays
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
  }
}

# Configure the Azure Provider with required features
provider "azurerm" {
  features {
    # Enable automatic deletion of resources in resource groups
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    
    # Configure Key Vault features for secret management
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
    
    # Configure storage account features
    storage {
      prevent_nested_items_deletion = false
    }
    
    # Configure Cognitive Services features for AI Foundry
    cognitive_account {
      purge_soft_delete_on_destroy = true
    }
  }
}