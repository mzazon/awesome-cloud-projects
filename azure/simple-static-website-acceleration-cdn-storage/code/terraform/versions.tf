# Terraform and Provider Version Requirements
# This file defines the minimum versions required for Terraform and providers

terraform {
  required_version = ">= 1.5.0"
  
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.70"
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
    # Enable enhanced storage account features
    storage {
      purge_soft_deleted_blobs_on_destroy = true
    }
    
    # Enable resource group cleanup features
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}