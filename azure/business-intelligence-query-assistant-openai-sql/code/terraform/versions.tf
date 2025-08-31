# Provider version constraints and required providers
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
    # Enable soft delete for Key Vault (recommended for production)
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
    
    # Cognitive Services account recovery settings
    cognitive_account {
      purge_soft_delete_on_destroy = true
    }
  }
}