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

# Configure the Microsoft Azure Provider
provider "azurerm" {
  features {
    # Enable advanced features for resource management
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    
    # Configure Function App features
    app_service {
      # Allow Function App to be deleted even if it contains resources
      purge_soft_delete_on_destroy = true
    }
    
    # Configure Cognitive Services features
    cognitive_account {
      # Allow purging of soft-deleted Cognitive Services accounts
      purge_soft_delete_on_destroy = true
    }
  }
}