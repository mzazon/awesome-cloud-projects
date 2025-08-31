# Terraform and provider version constraints
# This file specifies the required Terraform version and Azure provider configuration
# for the AI-powered email marketing solution

terraform {
  required_version = ">= 1.0"
  
  # Azure provider requirements for OpenAI, Logic Apps, and Communication Services
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"  
      version = "~> 3.88"
    }
    
    # Random provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4"
    }
  }
}

# Configure the Azure Provider with required features
provider "azurerm" {
  features {
    # Enable automatic cleanup of resource groups
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    
    # Enable key vault features for secure secret management
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
    
    # Enable cognitive services features for OpenAI
    cognitive_account {
      purge_soft_delete_on_destroy = true
    }
  }
}

# Random provider for generating unique suffixes
provider "random" {}