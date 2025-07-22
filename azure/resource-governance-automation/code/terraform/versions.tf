# Terraform and Provider Version Requirements
# This file defines the minimum required versions for Terraform and providers
# used in this Azure Policy and Resource Graph implementation

terraform {
  required_version = ">= 1.0"

  required_providers {
    # Azure Resource Manager Provider
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }

    # Azure Active Directory Provider for identity management
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.0"
    }

    # Random provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }

    # Time provider for resource dependencies and delays
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
  }
}

# Configure the Azure Provider
provider "azurerm" {
  features {
    # Configure resource group deletion behavior
    resource_group {
      prevent_deletion_if_contains_resources = false
    }

    # Configure Log Analytics workspace behavior
    log_analytics_workspace {
      permanently_delete_on_destroy = true
    }

    # Configure policy assignment behavior
    template_deployment {
      delete_nested_items_during_deletion = true
    }
  }
}

# Configure the Azure Active Directory Provider
provider "azuread" {
  # Use default configuration from Azure CLI or environment variables
}