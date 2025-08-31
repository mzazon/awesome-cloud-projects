# Terraform and Provider Requirements
# This file defines the minimum versions required for Terraform and providers

terraform {
  required_version = ">= 1.5"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.80"
    }
    
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}

# Configure the Azure Resource Manager Provider
provider "azurerm" {
  features {
    # Ensure resource group is deleted even if it contains resources
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    
    # Configure Log Analytics workspace deletion behavior
    log_analytics_workspace {
      permanently_delete_on_destroy = true
    }
  }
}

# Random provider for generating unique resource names
provider "random" {}