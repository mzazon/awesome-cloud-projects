# Terraform and Provider Version Requirements
# This file defines the minimum Terraform version and required providers
# for deploying Azure Notification Hubs infrastructure

terraform {
  # Require Terraform version 1.0 or higher for improved features and stability
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
      version = "~> 3.0"
    }
  }
}

# Configure the Azure Provider
provider "azurerm" {
  # Enable all features for the AzureRM provider
  features {}
}