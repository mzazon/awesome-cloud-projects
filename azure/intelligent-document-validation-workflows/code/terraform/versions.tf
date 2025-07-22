# Terraform provider version requirements for Azure document validation solution
# This configuration ensures compatibility with the latest Azure provider features
# and maintains consistency across different deployment environments

terraform {
  required_version = ">= 1.5.0"
  
  required_providers {
    # Azure Resource Manager provider for core Azure resources
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.80"
    }
    
    # Azure Active Directory provider for identity and access management
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.45"
    }
    
    # Random provider for generating unique resource names and identifiers
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
    
    # Time provider for time-based operations and delays
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
  }
}

# Configure the Azure Provider with features for enhanced functionality
provider "azurerm" {
  features {
    # Enable automatic deletion of resources in resource groups when the group is deleted
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    
    # Key Vault configuration for secure credential management
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
    
    # Cognitive Services configuration for AI Document Intelligence
    cognitive_account {
      purge_soft_delete_on_destroy = true
    }
    
    # Log Analytics workspace configuration for monitoring
    log_analytics_workspace {
      permanently_delete_on_destroy = true
    }
  }
}

# Configure Azure AD provider for identity management
provider "azuread" {
  # Inherits tenant configuration from Azure CLI or environment variables
}