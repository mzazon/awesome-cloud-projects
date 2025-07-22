# Terraform and Provider Version Requirements
# This file specifies the minimum required versions for Terraform and providers

terraform {
  required_version = ">= 1.5.0"
  
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.80"
    }
    azapi = {
      source  = "Azure/azapi"
      version = "~> 1.10"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}

# Configure the Azure Provider
provider "azurerm" {
  features {
    # Resource Group auto-deletion settings
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    
    # Virtual Machine settings
    virtual_machine {
      delete_os_disk_on_deletion     = true
      graceful_shutdown              = false
      skip_shutdown_and_force_delete = false
    }
    
    # Log Analytics Workspace settings
    log_analytics_workspace {
      permanently_delete_on_destroy = true
    }
  }
}

# Configure the Azure API Provider for Chaos Studio
provider "azapi" {
}

# Configure the Random Provider for unique resource naming
provider "random" {
}