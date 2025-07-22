# Terraform and provider version requirements
terraform {
  required_version = ">= 1.5"
  
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.80"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.10"
    }
  }
}

# Configure the Azure Provider
provider "azurerm" {
  features {
    # Enable automatic deletion of resources in resource groups when destroyed
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    
    # API Management specific features
    api_management {
      purge_soft_delete_on_destroy = true
      recover_soft_deleted         = true
    }
    
    # Cosmos DB specific features
    cosmosdb_account {
      prevent_deletion_if_contains_resources = false
    }
  }
}