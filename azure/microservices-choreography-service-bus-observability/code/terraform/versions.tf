# Terraform and Provider Version Configuration
# This file defines the required Terraform version and provider configurations
# for the microservices choreography infrastructure

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.75"
    }
    azapi = {
      source  = "Azure/azapi"
      version = "~> 1.8"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}

# Configure the Microsoft Azure Provider
provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
    
    application_insights {
      disable_generated_rule = false
    }
  }
}

# Configure the Azure API Provider for resources not yet supported by azurerm
provider "azapi" {}

# Configure the Random Provider for generating unique resource names
provider "random" {}