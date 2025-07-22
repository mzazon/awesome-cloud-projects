# Terraform and Provider Version Requirements
# This file defines the minimum required versions for Terraform and providers
# for the Enterprise API Protection with Premium Management and WAF solution

terraform {
  required_version = ">= 1.5.0"
  
  required_providers {
    # Azure Resource Manager provider for core Azure resources
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.85"
    }
    
    # Random provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    
    # Time provider for managing time-based resources and delays
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
  }
}

# Configure the Azure Resource Manager Provider
provider "azurerm" {
  features {
    # Enable enhanced security features for Key Vault
    key_vault {
      purge_soft_delete_on_destroy = false
      recover_soft_deleted_key_vaults = true
    }
    
    # Enhanced security for API Management
    api_management {
      purge_soft_delete_on_destroy = false
      recover_soft_deleted_api_managements = true
    }
    
    # Enhanced features for Application Insights
    application_insights {
      disable_generated_rule = false
    }
    
    # Resource group cleanup configuration
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    
    # Enhanced features for Log Analytics
    log_analytics_workspace {
      permanently_delete_on_destroy = false
    }
  }
}

# Random provider for generating unique resource names
provider "random" {}

# Time provider for managing deployment timing
provider "time" {}