# Terraform configuration for Azure secure code execution workflow
# Provider requirements and version constraints

terraform {
  required_version = ">= 1.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.85"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# Configure the Azure Provider features
provider "azurerm" {
  features {
    # Enable enhanced security features
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
    
    # Enhanced resource group cleanup
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    
    # Application Insights configuration
    application_insights {
      disable_generated_rule = false
    }
  }
}

# Random provider for generating unique suffixes
provider "random" {}