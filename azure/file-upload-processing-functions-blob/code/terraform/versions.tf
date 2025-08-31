# Terraform version and provider requirements for Azure file upload processing infrastructure
# This configuration ensures compatibility with the latest Azure provider features

terraform {
  required_version = ">= 1.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.100"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4"
    }
  }
}

# Configure the Azure Provider with features block for enhanced functionality
provider "azurerm" {
  features {
    # Enable application insights purge on destroy for clean deletion
    application_insights {
      disable_generated_rule = false
    }

    # Enable resource group deletion including all contained resources
    resource_group {
      prevent_deletion_if_contains_resources = false
    }

    # Configure storage account deletion behavior
    storage {
      prevent_nested_items_deletion = false
    }
  }
}