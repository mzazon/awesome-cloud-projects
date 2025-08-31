# Terraform provider version constraints and requirements
# This file defines the minimum Terraform version and required providers for the automated video analysis solution

terraform {
  required_version = ">= 1.5.0"
  
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.100"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}

# Configure the Microsoft Azure Provider
provider "azurerm" {
  features {
    # Enable enhanced validation for Cognitive Services accounts
    cognitive_account {
      purge_soft_delete_on_destroy = true
    }
    
    # Configure resource group deletion behavior
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    
    # Configure storage account behavior
    storage {
      prevent_nested_items_deletion = false
    }
  }
}

# Configure random provider for generating unique resource names
provider "random" {}

# Configure archive provider for function app deployment packages
provider "archive" {}

# Configure local provider for file operations
provider "local" {}