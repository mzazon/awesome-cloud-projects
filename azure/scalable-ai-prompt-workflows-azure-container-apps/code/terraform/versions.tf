# Terraform and provider version requirements
# This file specifies the minimum versions required for Terraform and Azure providers

terraform {
  required_version = ">= 1.5.0"
  
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.85"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.47"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# Configure the Microsoft Azure Provider
provider "azurerm" {
  features {
    # Enable advanced features for Container Apps
    container_registry {
      purge_soft_delete_on_destroy = true
    }
    
    # Enable advanced features for AI services
    cognitive_account {
      purge_soft_delete_on_destroy = true
    }
    
    # Enable advanced features for Log Analytics
    log_analytics_workspace {
      permanently_delete_on_destroy = true
    }
  }
}

# Configure the Azure Active Directory Provider
provider "azuread" {
}

# Configure the Random Provider
provider "random" {
}