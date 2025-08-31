# Terraform configuration for Azure Intelligent Product Catalog
# This file defines the required providers and their versions

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.116"
    }
    
    azurecaf = {
      source  = "aztfmod/azurecaf"
      version = "~> 1.2"
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
    # Enable advanced features for Function Apps
    app_service {
      purge_soft_deleted_service_on_destroy = true
    }
    
    # Enable advanced features for Storage Accounts
    storage {
      purge_soft_deleted_containers_on_destroy = true
    }
    
    # Enable advanced features for Cognitive Services
    cognitive_account {
      purge_soft_deleted_on_destroy = true
    }
  }
}

# Configure Azure CAF provider for consistent naming
provider "azurecaf" {}

# Configure Random provider for unique resource naming
provider "random" {}