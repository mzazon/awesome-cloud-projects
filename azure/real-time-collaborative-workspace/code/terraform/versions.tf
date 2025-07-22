# Provider version constraints for Azure real-time collaborative applications
# This file defines the required Terraform version and provider versions
# to ensure consistent deployments across different environments

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    # Azure Resource Manager provider for main Azure resources
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.80"
    }
    
    # Random provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
    
    # Time provider for resource creation delays
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
  }
}

# Configure the Azure Provider
provider "azurerm" {
  features {
    # Enable advanced security features for Key Vault
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
    
    # Configure resource group deletion behavior
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    
    # Enable advanced features for storage accounts
    storage {
      # Use Azure AD authentication when possible
      use_azuread_auth = true
    }
  }
}

# Configure the Random Provider
provider "random" {
  # No specific configuration needed
}

# Configure the Time Provider  
provider "time" {
  # No specific configuration needed
}