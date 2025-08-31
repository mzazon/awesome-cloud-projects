# Terraform version and provider requirements for Azure Meeting Intelligence solution
terraform {
  required_version = ">= 1.0"
  
  required_providers {
    # Azure Resource Manager provider for managing Azure resources
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.85.0"
    }
    
    # Random provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5.0"
    }
    
    # Time provider for managing time-based resources and delays
    time = {
      source  = "hashicorp/time"
      version = "~> 0.10.0"
    }
  }
}

# Azure Resource Manager provider configuration
provider "azurerm" {
  features {
    # Enable soft delete protection for Cognitive Services
    cognitive_account {
      purge_soft_delete_on_destroy = false
    }
    
    # Configure resource group behavior
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    
    # Configure storage account behavior
    storage {
      purge_soft_delete_on_destroy = false
    }
    
    # Configure Service Bus behavior
    service_bus {
      purge_soft_delete_on_destroy = false
    }
  }
}