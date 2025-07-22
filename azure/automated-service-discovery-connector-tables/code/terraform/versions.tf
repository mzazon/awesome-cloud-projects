# Terraform and Provider Version Requirements
# This file defines the minimum required versions for Terraform and Azure providers

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
    null = {
      source  = "hashicorp/null"
      version = "~> 3.1"
    }
  }
}

# Configure the Azure Provider
provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    
    storage {
      # Enable soft delete for production environments
      # Set to false for development/testing to allow immediate cleanup
      enable_soft_delete = var.enable_soft_delete
    }
    
    key_vault {
      # Purge soft-deleted Key Vaults on destroy
      purge_soft_delete_on_destroy = true
      # Recover soft-deleted Key Vaults
      recover_soft_deleted_key_vaults = true
    }
  }
}