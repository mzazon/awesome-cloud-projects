# Terraform version and provider requirements
terraform {
  required_version = ">= 1.0"
  
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4"
    }
  }
}

# Configure the Azure Provider
provider "azurerm" {
  features {
    # Enable soft delete for Key Vault (recommended for production)
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
    
    # Resource group cleanup behavior
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}