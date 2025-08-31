# Terraform and Provider Version Requirements
# This file defines the minimum required versions for Terraform and Azure providers
# Following Azure and Terraform best practices for version constraints

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

# Configure the Azure Provider
# Using features block to enable/disable specific provider behaviors
provider "azurerm" {
  features {
    # Enable automatic deletion of resources when resource group is deleted
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    
    # Configure Application Insights behavior
    application_insights {
      disable_generated_rule = false
    }
  }
}