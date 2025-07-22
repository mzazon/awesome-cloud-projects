# Terraform version and provider requirements
terraform {
  required_version = ">= 1.5"
  
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.80"
    }
    azapi = {
      source  = "Azure/azapi"
      version = "~> 1.10"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4"
    }
  }
}

# Configure Azure Provider
provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
    
    machine_learning {
      purge_soft_deleted_workspace_on_destroy = true
    }
  }
}

# Configure Azure API Provider for advanced features
provider "azapi" {}

# Configure Random Provider for unique naming
provider "random" {}