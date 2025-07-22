# Provider and version requirements for Azure multi-language content localization
# This file defines the required Terraform and Azure provider versions

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

# Configure the Azure Provider
provider "azurerm" {
  features {
    # Enable enhanced security features for cognitive services
    cognitive_account {
      purge_soft_delete_on_destroy = true
    }
    
    # Enable storage account features
    storage {
      purge_soft_delete_on_destroy = true
    }
    
    # Enable resource group features
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}