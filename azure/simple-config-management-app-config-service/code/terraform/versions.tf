# Terraform and Provider Version Requirements
# This file defines the minimum required versions for Terraform and the Azure provider
# to ensure consistent deployments across different environments

terraform {
  required_version = ">= 1.5.0"
  
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
  }
}

# Configure the Azure Provider
# The features block is required for v3.0+ of the AzureRM provider
provider "azurerm" {
  features {
    # Configure App Service specific features
    app_service {
      purge_soft_deleted_service_plans = true
    }
    
    # Configure resource group specific features
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}