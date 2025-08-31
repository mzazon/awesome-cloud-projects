# Terraform version and provider requirements for Azure Expense Tracker
# This file defines the minimum versions and provider configurations required

terraform {
  required_version = ">= 1.0"

  required_providers {
    # Azure Resource Manager Provider
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.116"
    }

    # Random provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# Configure the Azure Provider
provider "azurerm" {
  # Enable features block for advanced configurations
  features {
    # Cosmos DB configuration
    cosmosdb_account {
      # Prevent accidental deletion of Cosmos DB accounts
      prevent_deletion_if_contains_data = true
    }

    # Resource Group configuration
    resource_group {
      # Allow deletion of resource groups even if they contain resources
      prevent_deletion_if_contains_resources = false
    }

    # Function App configuration
    app_service {
      # Allow destructive changes to App Service plans
      # This is useful for development environments
      backup_enabled = false
    }
  }
}