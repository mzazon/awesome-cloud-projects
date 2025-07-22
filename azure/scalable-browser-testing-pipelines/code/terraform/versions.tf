# Terraform configuration for Azure Playwright Testing with Azure DevOps
# This file defines the required providers and their versions

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    # Azure Resource Manager provider for core Azure resources
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.80"
    }
    
    # Azure DevOps provider for DevOps project and pipeline resources
    azuredevops = {
      source  = "microsoft/azuredevops"
      version = "~> 0.10"
    }
    
    # Random provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
    
    # Time provider for resource creation delays
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
  }
}

# Configure the Azure Provider
provider "azurerm" {
  features {
    # Enable advanced features for resource management
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    
    # Configure key vault features
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
  }
}

# Configure Azure DevOps Provider
provider "azuredevops" {
  # Organization URL will be provided via environment variable AZDO_ORG_SERVICE_URL
  # Personal Access Token will be provided via environment variable AZDO_PERSONAL_ACCESS_TOKEN
}