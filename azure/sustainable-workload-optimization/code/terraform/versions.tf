# Terraform version and provider requirements for Azure sustainable workload optimization
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
    # Enable advanced features for automation and monitoring
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    
    # Enable automation account features
    automation_account {
      enable_azure_automation_account = true
    }
    
    # Enable key vault purge protection
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
  }
}