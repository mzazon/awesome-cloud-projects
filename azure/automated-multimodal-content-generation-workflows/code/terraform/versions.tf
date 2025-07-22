# Terraform version and provider requirements
terraform {
  required_version = ">= 1.5"
  
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

# Configure the Azure Provider features
provider "azurerm" {
  features {
    # Enable enhanced security for Key Vault
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
    
    # Enable enhanced security for Storage Account
    storage {
      purge_soft_delete_on_destroy = true
    }
    
    # Configure resource group deletion behavior
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

# Configure Azure AD provider
provider "azuread" {}

# Configure random provider
provider "random" {}