# Terraform and Provider Version Requirements
# This file defines the required versions for Terraform and Azure providers

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
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
  }
}

# Configure the Microsoft Azure Provider
provider "azurerm" {
  features {
    # Enable enhanced security features
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    
    # Configure storage account features
    storage {
      prevent_deletion_if_contains_resources = false
    }
    
    # Configure Log Analytics workspace features
    log_analytics_workspace {
      permanently_delete_on_destroy = true
    }
  }
}