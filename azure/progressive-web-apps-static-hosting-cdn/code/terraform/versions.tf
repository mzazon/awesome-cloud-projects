# Terraform provider requirements for Azure PWA infrastructure
# This file defines the minimum provider versions and required Terraform version

terraform {
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
      version = "~> 3.4"
    }
    
    # Time provider for managing time-based resources
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
  }
}

# Configure the Microsoft Azure Provider
provider "azurerm" {
  features {
    # Application Insights configuration
    application_insights {
      disable_generated_rule = false
    }
    
    # Resource Group configuration
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    
    # CDN configuration
    cdn {
      # Enable CDN endpoint purging
      purge_soft_deleted_cdn_endpoints = true
    }
  }
}