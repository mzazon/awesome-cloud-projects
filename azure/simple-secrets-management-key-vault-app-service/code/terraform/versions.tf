# Terraform provider version requirements
# This file defines the minimum versions required for Terraform and providers

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

# Configure the Azure Provider
provider "azurerm" {
  features {
    # Enable enhanced Key Vault features
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
    
    # Enable App Service features
    app_service {
      purge_soft_deleted_service_plan = true
    }
  }
}