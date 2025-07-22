# Terraform and Provider Version Requirements
# This file defines the minimum required versions for Terraform and Azure providers

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.1"
    }
  }
}

# Configure the Microsoft Azure Provider
provider "azurerm" {
  features {
    # Enable advanced features for resource group management
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    
    # Enable advanced features for MySQL flexible server
    mysql_flexible_server {
      restore_point_in_time_utc = null
    }
    
    # Enable advanced logging features
    log_analytics_workspace {
      permanently_delete_on_destroy = true
    }
  }
}