# ==============================================================================
# Terraform and Provider Version Constraints
# ==============================================================================
# This file defines the required versions of Terraform and providers to ensure
# consistent deployments and compatibility with the Service Bus resources.
# Version constraints follow best practices for production deployments.
# ==============================================================================

terraform {
  # Minimum Terraform version required for this configuration
  # Version 1.0+ provides stable configuration language and state format
  required_version = ">= 1.0"

  # Required providers with version constraints
  required_providers {
    # Azure Resource Manager (AzureRM) Provider
    # Manages Azure resources including Service Bus namespaces and queues
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }

  # Optional: Configure remote state backend for team collaboration
  # Uncomment and configure based on your organization's requirements
  #
  # backend "azurerm" {
  #   resource_group_name  = "rg-terraform-state"
  #   storage_account_name = "terraformstatestorage"
  #   container_name      = "tfstate"
  #   key                 = "servicebus-messaging.terraform.tfstate"
  # }
}

# Azure Resource Manager Provider Configuration
# The provider block configures the Azure provider with required features
provider "azurerm" {
  # Enable all provider features - required for AzureRM provider v2.0+
  features {
    # Resource Group features
    resource_group {
      # Prevent accidental deletion of non-empty resource groups
      prevent_deletion_if_contains_resources = true
    }

    # Key Vault features (if using customer-managed keys in the future)
    key_vault {
      # Purge soft-deleted Key Vaults after destroy
      purge_soft_delete_on_destroy    = false
      # Recover soft-deleted Key Vaults during creation
      recover_soft_deleted_key_vaults = true
    }
  }

  # Optional: Set subscription ID explicitly for multi-subscription scenarios
  # subscription_id = var.subscription_id

  # Optional: Set specific Azure AD tenant
  # tenant_id = var.tenant_id

  # Optional: Configure provider for specific Azure environment
  # environment = "public" # public, usgovernment, german, china
}

# Data source to retrieve current Azure client configuration
# Provides information about the current Azure subscription and authentication context
data "azurerm_client_config" "current" {}

# ==============================================================================
# PROVIDER VERSION COMPATIBILITY NOTES
# ==============================================================================
# 
# AzureRM Provider v4.x Features:
# - Enhanced Service Bus resource support
# - Improved Azure Resource Manager API integration  
# - Better support for Azure AD authentication
# - Enhanced tagging and metadata support
# - Improved error handling and validation
#
# Breaking Changes from v3.x:
# - Some resource properties may have changed names
# - Enhanced validation may require property updates
# - Authentication methods may have been updated
#
# For production deployments:
# - Pin to specific minor version (e.g., "~> 4.37") for consistency
# - Test provider upgrades in non-production environments first
# - Review provider CHANGELOG before upgrading
# 
# ==============================================================================