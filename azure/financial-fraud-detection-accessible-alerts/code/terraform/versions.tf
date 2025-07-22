# Terraform version and provider requirements
terraform {
  required_version = ">= 1.6"
  
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.80"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.46"
    }
  }
}

# Configure the Azure Provider
provider "azurerm" {
  features {
    # Enable enhanced security features
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
    
    cognitive_account {
      purge_soft_delete_on_destroy = true
    }
    
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

# Configure the Azure Active Directory Provider
provider "azuread" {
  # Configuration will be set via environment variables or Azure CLI
}

# Configure the Random Provider for generating unique resource names
provider "random" {
  # No configuration needed
}