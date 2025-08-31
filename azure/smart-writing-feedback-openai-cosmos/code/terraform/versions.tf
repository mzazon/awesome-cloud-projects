# Terraform version and provider requirements for Azure Smart Writing Feedback System
# This file defines the minimum versions and provider configurations needed

terraform {
  required_version = ">= 1.0"

  required_providers {
    # Azure Resource Manager provider for core Azure resources
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.100"
    }

    # Random provider for generating unique suffixes
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# Configure the Azure Provider with features
provider "azurerm" {
  features {
    # Enable advanced features for Function Apps
    app_service {
      purge_soft_deleted_function_apps_on_destroy = true
    }

    # Enable advanced features for Storage Accounts
    storage {
      purge_soft_delete_on_destroy = true
    }

    # Enable advanced features for Cognitive Services
    cognitive_account {
      purge_soft_delete_on_destroy = true
    }

    # Enable advanced features for Cosmos DB
    cosmosdb_account {
      prevent_deletion_if_contains_data = false
    }
  }
}