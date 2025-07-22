# Terraform and Provider Version Requirements
# This file specifies the required versions for Terraform and all providers used in this configuration

terraform {
  required_version = ">= 1.5.0"
  
  required_providers {
    # Azure Resource Manager Provider
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.90"
    }
    
    # Random Provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    
    # Time Provider for resource delays and timeouts
    time = {
      source  = "hashicorp/time"
      version = "~> 0.10"
    }
    
    # Template Provider for configuration files
    template = {
      source  = "hashicorp/template"
      version = "~> 2.2"
    }
  }
}

# Configure the Azure Provider
provider "azurerm" {
  features {
    # Enable enhanced resource group management
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    
    # Enable key vault features
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
    
    # Enable SQL managed instance features
    managed_disk {
      expand_without_downtime = true
    }
  }
}

# Configure the Random Provider
provider "random" {}

# Configure the Time Provider
provider "time" {}

# Configure the Template Provider
provider "template" {}