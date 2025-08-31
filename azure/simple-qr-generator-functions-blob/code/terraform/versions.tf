# Terraform configuration for Azure QR Code Generator
# Specifies required providers and versions for reliable deployments

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
      version = "~> 2.0"
    }
  }
}

# Configure the Azure Provider
provider "azurerm" {
  features {
    # Enable soft delete for storage accounts (can be disabled for dev environments)
    storage {
      delete_retention_policy_enabled = false
    }
    
    # Configure resource group deletion behavior
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}