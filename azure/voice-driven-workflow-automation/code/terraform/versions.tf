# Terraform configuration for Azure Voice Automation Infrastructure
# This file defines the required providers and their versions

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

# Configure the Microsoft Azure Provider
provider "azurerm" {
  features {
    # Configure provider features
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    
    cognitive_account {
      purge_soft_delete_on_destroy = true
    }
    
    storage {
      purge_soft_delete_on_destroy = true
    }
  }
}