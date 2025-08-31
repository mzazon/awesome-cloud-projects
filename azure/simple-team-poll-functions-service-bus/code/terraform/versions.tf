# versions.tf
# Provider requirements and version constraints for the Simple Team Poll System

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
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.2"
    }
  }
}

# Configure the Microsoft Azure Provider
provider "azurerm" {
  features {
    # Enable automatic deletion of resources in resource groups
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    
    # Configure storage account behavior
    storage {
      # Purge soft deleted storage accounts on destroy
      purge_soft_delete_on_destroy = true
    }
  }
}