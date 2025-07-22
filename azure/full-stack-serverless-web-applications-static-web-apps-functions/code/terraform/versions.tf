# Terraform and Provider Version Requirements
# This file defines the required Terraform version and provider versions

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    # Azure Resource Manager Provider
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    
    # Random Provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4"
    }
    
    # Time Provider for managing time-based resources
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
  }
}

# Configure the Azure Provider
provider "azurerm" {
  features {
    # Enable automatic deletion of resources in resource groups
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    
    # Configure storage account features
    storage {
      use_legacy_version = false
    }
  }
}

# Configure the Random Provider
provider "random" {}

# Configure the Time Provider
provider "time" {}