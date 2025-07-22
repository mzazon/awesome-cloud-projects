# Terraform version and provider requirements
# This file defines the minimum versions for Terraform and the Azure provider

terraform {
  required_version = ">= 1.5.0"
  
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.80"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4"
    }
  }
}

# Configure the Azure Provider with features
provider "azurerm" {
  features {
    # Enable automatic deletion of resources
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    
    # Key Vault configuration
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
    
    # Log Analytics workspace configuration
    log_analytics_workspace {
      permanently_delete_on_destroy = true
    }
  }
}