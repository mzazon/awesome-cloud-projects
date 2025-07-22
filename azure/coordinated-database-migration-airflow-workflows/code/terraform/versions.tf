# ===================================================================================
# Terraform Configuration: Provider Requirements
# Description: Defines Terraform and provider version constraints for the 
#              intelligent database migration orchestration solution
# Version: 1.0
# ===================================================================================

terraform {
  required_version = ">= 1.5.0"
  
  required_providers {
    # Azure Resource Manager provider for core Azure resources
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.110.0"
    }
    
    # Random provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6.0"
    }
    
    # Time provider for resource creation delays and timing
    time = {
      source  = "hashicorp/time"
      version = "~> 0.11.0"
    }
  }
}

# Configure the Azure Provider
provider "azurerm" {
  features {
    # Storage account features
    storage {
      # Prevent accidental deletion of storage containers
      prevent_deletion_if_contains_resources = true
    }
    
    # Key vault features
    key_vault {
      # Purge soft deleted key vaults on destroy
      purge_soft_delete_on_destroy    = false
      recover_soft_deleted_key_vaults = true
    }
    
    # Resource group features
    resource_group {
      # Prevent deletion of resource groups containing resources
      prevent_deletion_if_contains_resources = true
    }
    
    # Log analytics workspace features
    log_analytics_workspace {
      # Permanently delete workspace on destroy
      permanently_delete_on_destroy = false
    }
  }
}

# Configure the Random provider
provider "random" {}

# Configure the Time provider  
provider "time" {}