# Configure Terraform and required providers
terraform {
  required_version = ">= 1.5"
  
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4"
    }
  }
}

# Configure the Azure Provider features
provider "azurerm" {
  features {
    # Enable automatic cleanup of resources in resource group when deleted
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}