# Terraform and Provider Version Requirements
# This file defines the minimum required versions for Terraform and the Azure provider

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.80"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
  }
}

# Azure Resource Manager Provider Configuration
# Configure the Azure Provider with features for this solution
provider "azurerm" {
  features {
    # Enable soft delete for Key Vault (if used in future extensions)
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
    
    # Resource group management features
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    
    # Cosmos DB configuration
    cosmos_db {
      recover_soft_deleted_databases = true
    }
  }
}

# Random Provider for generating unique resource names
provider "random" {}