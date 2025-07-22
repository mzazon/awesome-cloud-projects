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
      version = "~> 3.1"
    }
  }
}

# Configure the Azure Provider
provider "azurerm" {
  features {
    # Enable resource group deletion for cleanup
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    
    # Enable key vault features
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
    
    # Enable cognitive account features
    cognitive_account {
      purge_soft_deleted_on_destroy = true
    }
  }
}