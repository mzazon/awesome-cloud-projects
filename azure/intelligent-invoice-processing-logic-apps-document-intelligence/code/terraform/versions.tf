# Terraform and provider version constraints
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
  }
}

# Configure the Azure Provider
provider "azurerm" {
  features {
    # Enable soft delete for storage accounts
    storage {
      delete_retention_policy {
        days = 7
      }
    }
    
    # Configure Cognitive Services features
    cognitive_account {
      purge_soft_delete_on_destroy = true
    }
    
    # Configure resource group features
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}