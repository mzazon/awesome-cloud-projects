terraform {
  required_version = ">= 1.0"
  
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {
    # Enhanced security for Key Vault with purge protection
    key_vault {
      purge_soft_delete_on_destroy = false
    }
    
    # Enhanced cognitive services management
    cognitive_account {
      purge_soft_deleted_on_destroy = true
    }
  }
}