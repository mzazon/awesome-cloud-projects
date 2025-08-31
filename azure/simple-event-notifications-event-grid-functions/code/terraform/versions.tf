# Terraform and Provider Version Requirements
# This configuration specifies the minimum required versions for Terraform and providers

terraform {
  required_version = ">= 1.5.0"
  
  required_providers {
    # Azure Resource Manager Provider
    # Provides resources for managing Azure infrastructure
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.80"
    }
    
    # Random Provider
    # Used for generating unique resource names and identifiers
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}

# Configure the Azure Provider
# Features block configures provider-specific settings
provider "azurerm" {
  features {
    # Key Vault configuration for managing secrets and keys
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
    
    # Resource Group configuration for cleanup behavior
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    
    # Application Insights configuration for monitoring
    application_insights {
      disable_generated_rule = false
    }
  }
}