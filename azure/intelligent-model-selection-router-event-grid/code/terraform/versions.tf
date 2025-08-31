# Terraform version and provider constraints for Azure intelligent model selection architecture
# This configuration ensures compatibility with the required Azure resource types

terraform {
  required_version = ">= 1.5.0"
  
  required_providers {
    # Azure Resource Manager provider
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.116.0"
    }
    
    # Random provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6.0"
    }
    
    # Archive provider for creating function deployment packages
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4.0"
    }
  }
}

# Configure the Azure Provider with required features
provider "azurerm" {
  features {
    # Enable resource group deletion protection
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    
    # Configure key vault features for secret management
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
    
    # Configure cognitive services for AI Foundry resources
    cognitive_account {
      purge_soft_delete_on_destroy = true
    }
  }
}

# Configure random provider for generating unique suffixes
provider "random" {}

# Configure archive provider for function deployment packages
provider "archive" {}