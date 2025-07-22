# Terraform and provider version constraints for Azure infrastructure health monitoring
# This configuration ensures compatibility and stability across deployments

terraform {
  required_version = ">= 1.5.0"
  
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.80"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
  }
}

# Configure the Azure Provider features
provider "azurerm" {
  features {
    # Enable advanced Key Vault features for secret management
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
    
    # Configure resource group cleanup behavior
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    
    # Enable Log Analytics workspace features
    log_analytics_workspace {
      permanently_delete_on_destroy = true
    }
  }
}