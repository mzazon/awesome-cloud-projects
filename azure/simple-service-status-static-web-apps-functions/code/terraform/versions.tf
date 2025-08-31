# Terraform and provider version requirements
# This configuration ensures compatibility with the Azure provider
# and defines the minimum required Terraform version

terraform {
  required_version = ">= 1.5.0"
  
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.80"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4"
    }
  }
}

# Configure the Azure Provider
# This enables all Azure Resource Manager features
provider "azurerm" {
  features {
    # Configure provider features for specific resource types
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}