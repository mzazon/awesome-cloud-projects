# Terraform provider version requirements for Azure AI Cost Monitoring infrastructure
# This file defines the required providers and their version constraints

terraform {
  required_version = ">= 1.5"
  
  required_providers {
    # Azure Resource Manager provider for core Azure resources
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.90"
    }
    
    # Random provider for generating unique resource names and identifiers
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
    
    # Time provider for managing time-based resources and delays
    time = {
      source  = "hashicorp/time"
      version = "~> 0.11"
    }
  }
}

# Configure the Azure Resource Manager provider
provider "azurerm" {
  features {
    # Enable automatic deletion of resources when the resource group is deleted
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    
    # Configure Key Vault features for secure secret management
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
    
    # Configure Machine Learning workspace features
    machine_learning {
      purge_soft_deleted_workspace_on_destroy = true
    }
  }
}

# Configure the Random provider
provider "random" {
  # Random provider doesn't require specific configuration
}

# Configure the Time provider
provider "time" {
  # Time provider doesn't require specific configuration
}