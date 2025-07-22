# Terraform and Provider Version Requirements
# This file defines the minimum Terraform version and required providers for the
# Azure stateful microservices orchestration infrastructure

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    # Azure Resource Manager provider for core Azure resources
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.80"
    }
    
    # Random provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
    
    # Local provider for local value processing
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }
  }
}

# Configure the Azure Provider
provider "azurerm" {
  features {
    # Enable enhanced security features for Service Fabric
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
    
    # Configure resource group behavior
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    
    # Configure SQL Database features
    mssql {
      skip_extended_auditing_policy = false
    }
  }
}