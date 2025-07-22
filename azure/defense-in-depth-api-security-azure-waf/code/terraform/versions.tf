# Terraform and provider version requirements
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
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    
    api_management {
      purge_soft_delete_on_destroy = true
      recover_soft_deleted         = true
    }
    
    application_gateway {
      # Enable Application Gateway features
    }
    
    log_analytics_workspace {
      permanently_delete_on_destroy = true
    }
  }
}