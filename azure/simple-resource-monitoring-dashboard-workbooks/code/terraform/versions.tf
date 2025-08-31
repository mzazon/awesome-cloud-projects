# Terraform and provider version requirements
# This file defines the minimum required versions for Terraform and Azure providers

terraform {
  required_version = ">= 1.5.0"
  
  required_providers {
    # Azure Resource Manager provider for managing Azure resources
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.80"
    }
    
    # Random provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# Configure the Azure Provider with features
provider "azurerm" {
  features {
    # Enable deletion of Log Analytics workspace on destroy
    log_analytics_workspace {
      permanently_delete_on_destroy = true
    }
    
    # Configure resource group management
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

# Configure the Random Provider
provider "random" {}