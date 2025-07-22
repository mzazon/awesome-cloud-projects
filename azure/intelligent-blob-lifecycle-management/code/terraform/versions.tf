# Provider version requirements for Azure Storage Lifecycle Management
terraform {
  required_version = ">= 1.5.0"
  
  required_providers {
    # Azure Resource Manager provider for core Azure resources
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.80"
    }
    
    # Random provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    
    # Local provider for file operations and local values
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }
  }
}

# Configure the Azure Provider with required features
provider "azurerm" {
  features {
    # Enable resource group auto-deletion when empty
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    
    # Configure storage account behavior
    storage {
      # Prevent accidental deletion of storage accounts with data
      prevent_deletion_if_contains_resources = true
    }
    
    # Configure Log Analytics workspace behavior
    log_analytics_workspace {
      # Allow permanent deletion of Log Analytics workspaces
      permanently_delete_on_destroy = true
    }
  }
}

# Configure the Random provider
provider "random" {}

# Configure the Local provider
provider "local" {}