# Terraform and Provider Version Constraints
# This file defines the required versions for Terraform and all providers used in this configuration

terraform {
  required_version = ">= 1.8.0"
  
  required_providers {
    # Azure Resource Manager provider for managing Azure resources
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.115.0"
    }
    
    # Random provider for generating unique resource names and passwords
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6.0"
    }
    
    # Time provider for managing time-based resources and delays
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12.0"
    }
  }
}

# Configure the Azure Provider with required features
provider "azurerm" {
  features {
    # Enable advanced features for SQL Server management
    mssql_server {
      # Skip dropping of SQL Server on destroy (safety feature)
      skip_dropping_databases_on_destroy = false
    }
    
    # Enable advanced features for resource group management
    resource_group {
      # Prevent deletion of non-empty resource groups
      prevent_deletion_if_contains_resources = false
    }
    
    # Enable advanced features for backup vault management
    backup {
      # Skip recovery services vault soft delete (for easier cleanup in dev/test)
      skip_recovery_services_vault_soft_delete = true
    }
  }
}