# Terraform version and provider requirements for Real-time Status Notifications with SignalR and Functions
# This configuration ensures compatibility with the Azure RM provider and defines the required provider versions

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# Configure the Azure Provider
provider "azurerm" {
  features {
    # Enable resource group deletion when empty
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    
    # Configure Function App features
    api_management {
      purge_soft_delete_on_destroy = true
    }
  }
}