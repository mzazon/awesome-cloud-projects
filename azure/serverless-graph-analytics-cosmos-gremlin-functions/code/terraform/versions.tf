# Terraform provider version requirements for Azure serverless graph analytics solution
# This configuration ensures compatibility and stability across different environments

terraform {
  required_version = ">= 1.5.0"
  
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.75"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
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
    # Enable deletion of resources even if they contain data
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    
    # Configure Application Insights features
    application_insights {
      disable_generated_rule = false
    }
    
    # Configure Key Vault features for secure operations
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
  }
}