# Terraform and Provider Version Requirements
# This file defines the minimum versions required for Terraform and the Azure Resource Manager provider

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
  }
}

# Configure the Azure Resource Manager Provider
# This provider enables Terraform to interact with Azure services
provider "azurerm" {
  features {}
}