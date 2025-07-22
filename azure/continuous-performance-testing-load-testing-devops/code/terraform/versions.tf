# Terraform and Provider Version Requirements
# This file defines the minimum required versions for Terraform and providers

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    # Azure Resource Manager Provider
    # Used for managing Azure resources including Load Testing and Monitor services
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    
    # Azure Active Directory Provider
    # Used for service principal and application registrations
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.0"
    }
    
    # Random Provider
    # Used for generating unique suffixes for globally unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
  }
}

# Configure the Azure Resource Manager Provider
provider "azurerm" {
  features {
    # Enhanced resource group management
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    
    # Enhanced key vault management for secrets
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
    
    # Application Insights configuration
    application_insights {
      disable_generated_rule = false
    }
  }
}

# Configure the Azure Active Directory Provider
provider "azuread" {
  # Use default tenant from Azure CLI or environment variables
}

# Configure the Random Provider
provider "random" {
  # No specific configuration required
}