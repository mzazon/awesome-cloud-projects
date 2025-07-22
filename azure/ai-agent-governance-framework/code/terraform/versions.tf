# Terraform configuration with required provider versions
terraform {
  required_version = ">= 1.5"
  
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.90"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.47"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# Configure the Microsoft Azure Provider
provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
    
    log_analytics_workspace {
      permanently_delete_on_destroy = true
    }
  }
}

# Configure the Azure Active Directory Provider
provider "azuread" {
  # Configuration options
}

# Configure the Random Provider
provider "random" {
  # Configuration options
}