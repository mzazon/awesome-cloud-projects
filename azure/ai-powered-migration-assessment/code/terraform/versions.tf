# Terraform and provider version requirements
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
    # Enable preview features for Azure OpenAI and Migrate services
    cognitive_account {
      purge_soft_delete_on_destroy = true
    }
    
    # Resource group management
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    
    # Storage account configuration
    storage {
      prevent_nested_items_deletion = false
    }
  }
}

# Configure random provider for unique resource naming
provider "random" {}

# Configure archive provider for function app deployment
provider "archive" {}