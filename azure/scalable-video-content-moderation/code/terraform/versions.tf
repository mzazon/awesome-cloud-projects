# Provider version constraints and requirements
terraform {
  required_version = ">= 1.0"
  
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.80"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4"
    }
  }
}

# Configure the Azure Provider
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
      # Enable advanced threat protection for storage accounts
      advanced_threat_protection_enabled = true
    }
  }
}