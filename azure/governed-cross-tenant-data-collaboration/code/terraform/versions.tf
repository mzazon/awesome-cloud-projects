# Terraform and provider version constraints
terraform {
  required_version = "~> 1.0"
  
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

# Configure the Microsoft Azure Provider
provider "azurerm" {
  features {
    # Enable soft delete for storage accounts
    storage {
      delete_retention_policy {
        days = 7
      }
    }
    
    # Enable soft delete for Purview accounts
    purview {
      purge_soft_delete_on_destroy = true
    }
  }
}