# =============================================================================
# TERRAFORM PROVIDER REQUIREMENTS
# =============================================================================
# This configuration ensures compatibility with the latest Azure provider features
# for environmental impact dashboard and sustainability reporting solutions.

terraform {
  required_version = ">= 1.6"
  
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.37"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}

# =============================================================================
# PROVIDER CONFIGURATIONS
# =============================================================================

# Configure the Azure Provider
provider "azurerm" {
  features {
    # Enable enhanced security features for sustainability workloads
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
    
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    
    application_insights {
      disable_generated_rule = false
    }
    
    # Storage account security enhancements
    storage {
      prevent_deletion_if_contains_resources = false
    }
    
    # Function app security features
    app_service {
      expand_app_settings = false
    }
  }
}

# Configure Azure AD Provider for Power BI and security principals
provider "azuread" {
  # Use current tenant context for Azure AD operations
}