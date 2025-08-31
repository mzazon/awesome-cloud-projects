# Terraform configuration for Event-Driven AI Agent Workflows
# This file defines the required providers and versions

terraform {
  required_version = ">= 1.5"
  
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.70"
    }
    
    azapi = {
      source  = "azure/azapi"
      version = "~> 1.8"
    }
    
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}

# Configure the Microsoft Azure Provider
provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    
    machine_learning {
      purge_soft_deleted_workspace_on_destroy = true
    }
  }
}

# Azure API provider for preview services
provider "azapi" {}