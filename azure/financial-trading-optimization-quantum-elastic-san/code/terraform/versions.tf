# Terraform provider version constraints for Azure Quantum Financial Trading Solution
# This configuration ensures compatibility with the required Azure services

terraform {
  required_version = ">= 1.5.0"
  
  required_providers {
    # Azure Resource Manager provider for core Azure services
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.80"
    }
    
    # Random provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
    
    # Time provider for managing resource creation timing
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
  }
}

# Configure the Microsoft Azure Provider
provider "azurerm" {
  features {
    # Enable preview features for Azure Quantum
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    
    # Configure storage account features for Elastic SAN
    storage {
      use_legacy_version = false
    }
    
    # Configure machine learning workspace features
    machine_learning {
      purge_soft_deleted_workspace_on_destroy = true
    }
  }
}