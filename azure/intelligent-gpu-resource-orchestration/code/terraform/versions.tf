# Terraform version and provider requirements for Azure GPU orchestration recipe
# This configuration ensures compatibility with the required Azure providers

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.110"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.53"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# Configure the Azure Provider with required features
provider "azurerm" {
  features {
    # Key Vault configuration for secure secret management
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
    
    # Resource Group configuration
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    
    # Container Apps configuration
    container_app {
      delete_jobs = true
    }
  }
}

# Configure Azure AD provider for managed identity assignments
provider "azuread" {
  # Use default configuration from environment
}

# Configure random provider for unique resource naming
provider "random" {
  # Use default configuration
}