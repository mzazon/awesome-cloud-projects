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
    azapi = {
      source  = "Azure/azapi"
      version = "~> 1.0"
    }
  }
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    
    storage {
      # Enable advanced threat protection for storage accounts
      advanced_threat_protection_enabled = true
    }
    
    key_vault {
      # Purge soft-deleted key vaults immediately during destroy
      purge_soft_delete_on_destroy = true
    }
  }
}

# Get current client configuration for subscription ID
data "azurerm_client_config" "current" {}