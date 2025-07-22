# Terraform and Provider Version Requirements
# This file defines the minimum Terraform version and required providers
# for the financial market data processing infrastructure

terraform {
  required_version = ">= 1.5"
  
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.80"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.45"
    }
  }
}

# Azure Resource Manager Provider Configuration
# Enables features required for financial market data processing
provider "azurerm" {
  features {
    # Key Vault configuration for secure secrets management
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
    
    # Resource Group configuration
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    
    # Application Insights configuration for monitoring
    application_insights {
      disable_generated_rule = false
    }
  }
}

# Azure Active Directory Provider for identity management
provider "azuread" {}

# Random Provider for generating unique identifiers
provider "random" {}