# Terraform version and provider requirements for Azure video processing workflow
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
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    
    storage {
      # Enable soft delete for storage accounts
      purge_soft_delete_on_destroy = true
    }
    
    container_instance {
      # Automatically delete container groups on destroy
      auto_delete_on_destroy = true
    }
  }
}