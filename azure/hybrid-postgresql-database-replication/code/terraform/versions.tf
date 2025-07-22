# Terraform and Provider Version Requirements
# This file specifies the required Terraform version and provider versions
# for the Azure hybrid PostgreSQL database replication infrastructure

terraform {
  required_version = ">= 1.9.0"
  
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.0"
    }
    
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.34"
    }
    
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }
  }
}

# Configure the Azure Provider
provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
    
    postgresql_flexible_server {
      restart_server_on_configuration_value_change = true
    }
  }
}

# Configure the Azure Active Directory Provider
provider "azuread" {
  # Configuration options
}

# Configure the Kubernetes Provider
provider "kubernetes" {
  # Configuration will be provided via variables or environment
  # This assumes you have a Kubernetes cluster available
}

# Configure the Random Provider
provider "random" {
  # No configuration needed
}

# Configure the Time Provider
provider "time" {
  # No configuration needed
}