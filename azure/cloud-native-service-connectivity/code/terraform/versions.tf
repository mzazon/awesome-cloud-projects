# Provider version requirements for Azure cloud-native service connectivity infrastructure
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
    # Enable features for Key Vault
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
    
    # Enable features for Storage Account
    storage {
      prevent_nested_items_deletion = false
    }
    
    # Enable features for SQL Server
    mssql {
      restore_dropped_database_on_new_server = false
    }
  }
}

# Configure the Random Provider for unique resource naming
provider "random" {}