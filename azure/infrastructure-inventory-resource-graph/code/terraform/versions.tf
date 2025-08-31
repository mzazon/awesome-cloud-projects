# Terraform and provider version constraints
# Azure Infrastructure Inventory with Resource Graph
# This file defines the minimum required versions for Terraform and providers

terraform {
  required_version = ">= 1.5.0"
  
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.100"
    }
    
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.50"
    }
    
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    
    time = {
      source  = "hashicorp/time"
      version = "~> 0.11"
    }
  }
}

# Configure the Azure Provider
provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    
    key_vault {
      purge_soft_delete_on_destroy = true
    }
  }
}

# Configure the Azure AD Provider
provider "azuread" {}

# Random provider for generating unique resource names
provider "random" {}

# Time provider for scheduling and delays
provider "time" {}