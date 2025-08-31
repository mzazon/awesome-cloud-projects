# Terraform provider version requirements for Azure resource cleanup automation
# This file specifies the minimum provider versions required for this configuration

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
  }
}

# Configure the Azure Provider with features
provider "azurerm" {
  features {
    # Enable automatic deletion of resources when resource group is deleted
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}