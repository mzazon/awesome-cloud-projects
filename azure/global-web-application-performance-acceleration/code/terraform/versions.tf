# Terraform version and provider requirements
terraform {
  required_version = ">= 1.0"
  
  required_providers {
    # Azure Resource Manager Provider
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    
    # Random provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
  }
}

# Configure the Azure Provider
provider "azurerm" {
  features {
    # Enable automatic deletion of resources in resource group when destroying
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    
    # App Service configuration
    app_service {
      # Enable backup and restore features
      backup_enabled = true
    }
    
    # Redis cache configuration
    redis {
      # Enable patch schedule for maintenance
      patch_schedule_enabled = true
    }
  }
}

# Random provider for generating unique suffixes
provider "random" {}