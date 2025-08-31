# Terraform and Provider Version Requirements
# This file defines the minimum required versions for Terraform and providers

terraform {
  required_version = ">= 1.5"

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

    # Random provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4"
    }
  }
}

# Configure the Azure Provider with features
provider "azurerm" {
  features {
    # Enable automatic resource group deletion when empty
    resource_group {
      prevent_deletion_if_contains_resources = false
    }

    # Configure Logic App features
    logic_app {
      # Enable logic app diagnostic settings
      enable_diagnostic_settings = true
    }

    # Configure storage account features  
    storage {
      # Allow cross-tenant object replication
      cross_tenant_replication_enabled = false
    }
  }
}

# Configure Azure AD provider
provider "azuread" {
  # Use default configuration from Azure CLI or environment variables
}

# Configure Random provider
provider "random" {
  # Use default configuration
}