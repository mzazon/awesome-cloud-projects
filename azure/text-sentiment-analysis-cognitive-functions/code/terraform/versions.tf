# Terraform version and provider requirements
# This file defines the minimum Terraform version and required providers
# for the text sentiment analysis solution

terraform {
  required_version = ">= 1.5"
  
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
    # Enable enhanced features for resource management
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    
    # Configure storage account features
    storage {
      # Prevent deletion of storage accounts with blobs
      prevent_deletion_if_contains_resources = true
    }
    
    # Configure Cognitive Services features
    cognitive_account {
      # Purge soft-deleted accounts on destroy
      purge_soft_delete_on_destroy = true
    }
  }
}