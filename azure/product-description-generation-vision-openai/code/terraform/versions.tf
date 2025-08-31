# Terraform version and provider requirements for Azure product description generation solution
# This configuration specifies the minimum Terraform version and required providers

terraform {
  required_version = ">= 1.5"
  
  required_providers {
    # Azure Resource Manager provider for managing Azure resources
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    
    # Random provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
    
    # Archive provider for packaging Azure Function code
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

# Azure Provider configuration
provider "azurerm" {
  features {
    # Enable enhanced features for resource management
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    
    # Cognitive Services configuration
    cognitive_account {
      purge_soft_delete_on_destroy = true
    }
    
    # Key Vault configuration for secure secret management
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
  }
}