# Terraform version and provider requirements for Azure distributed session management
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
  }
}

# Configure the Microsoft Azure Provider
provider "azurerm" {
  features {
    # Enable deletion of non-empty resource groups
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    
    # Configure App Service features
    app_service {
      # Enable advanced threat protection
      enable_backup = true
    }
    
    # Configure Key Vault features for secure configuration
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
  }
}