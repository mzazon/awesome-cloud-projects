# versions.tf
# This file specifies the required Terraform version and provider versions
# for the Azure Logic Apps schedule reminder solution

terraform {
  # Require Terraform version 1.0 or higher for stable features
  required_version = ">= 1.0"

  # Define required providers with version constraints
  required_providers {
    # Azure Resource Manager provider for creating Azure resources
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"  # Use latest 3.x version for stability
    }

    # Random provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }

    # Local provider for processing local values and templates
    local = {
      source  = "hashicorp/local"
      version = "~> 2.1"
    }
  }
}

# Configure the Azure Provider with required features
provider "azurerm" {
  # Enable features block (required for AzureRM provider 2.0+)
  features {
    # Configure resource group deletion behavior
    resource_group {
      prevent_deletion_if_contains_resources = false
    }

    # Configure Logic App behavior
    logic_app {
      # Allow workflows to be deleted when the Logic App is destroyed
      delete_contents_on_destroy = true
    }
  }
}