#
# Provider version requirements for Azure simple daily quote generator
# This file defines the required provider versions and features for the recipe
#

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    # Azure Resource Manager provider for managing Azure resources
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    
    # Random provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
    
    # Archive provider for creating function deployment packages
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }
}

# Configure the Azure Provider with required features
provider "azurerm" {
  features {
    # Enable deletion of resources when destroying
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    
    # Function App configuration
    app_service {
      # Allow deletion of function apps with content
      purge_soft_deleted_function_apps_on_destroy = true
    }
  }
}