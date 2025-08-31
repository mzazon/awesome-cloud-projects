# Terraform provider version requirements
# This configuration ensures compatibility with Azure provider features for AI services

terraform {
  required_version = ">= 1.5"
  
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4"
    }
  }
}

# Configure the Microsoft Azure Provider
provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    
    cognitive_account {
      purge_soft_delete_on_destroy = true
    }
  }
}

# Provider for generating random values for unique resource naming
provider "random" {}