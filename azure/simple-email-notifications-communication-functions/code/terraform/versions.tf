# Terraform version and provider requirements
terraform {
  required_version = ">= 1.0"
  
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.116"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

# Configure the Azure Provider
provider "azurerm" {
  features {
    # Resource Group deletion behavior
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    
    # Function App configuration
    app_service {
      purge_soft_deleted_function_apps_on_destroy = true
    }
  }
}