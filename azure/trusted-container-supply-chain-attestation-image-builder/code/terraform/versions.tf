# Terraform and provider version constraints
terraform {
  required_version = ">= 1.5.0"
  
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.80"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.45"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# Configure the Azure Provider
provider "azurerm" {
  features {
    # Enable soft delete for Key Vault
    key_vault {
      purge_soft_delete_on_destroy    = var.purge_key_vault_on_destroy
      recover_soft_deleted_key_vaults = true
    }
    
    # Enable soft delete for Container Registry
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

# Configure the Azure Active Directory Provider
provider "azuread" {
  # Configuration options if needed
}