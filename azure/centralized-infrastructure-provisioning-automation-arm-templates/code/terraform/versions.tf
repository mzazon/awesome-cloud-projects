# Terraform and provider version constraints
terraform {
  required_version = ">= 1.0"
  
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

# Configure the Azure Provider
provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    
    automation_account {
      # Enable enhanced security features
      encryption_at_rest_enabled = true
    }
    
    storage_account {
      # Enable secure configurations
      blob_public_access_enabled = false
    }
  }
}