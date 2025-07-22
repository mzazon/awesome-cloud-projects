# Terraform version and provider requirements for Azure infrastructure chatbot solution
terraform {
  required_version = ">= 1.0"
  
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.80"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.45"
    }
  }
}

# Configure the Azure Provider
provider "azurerm" {
  features {
    # Enable enhanced resource deletion behavior
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    
    # Configure Application Insights features
    application_insights {
      disable_generated_rule = false
    }
    
    # Configure Key Vault features for secure secret management
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
  }
}

# Configure Azure AD provider for managed identity operations
provider "azuread" {}

# Configure random provider for unique resource naming
provider "random" {}