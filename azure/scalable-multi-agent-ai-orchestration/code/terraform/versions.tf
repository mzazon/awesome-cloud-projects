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
    azapi = {
      source  = "azure/azapi"
      version = "~> 1.0"
    }
  }
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    
    cognitive_services {
      purge_soft_deleted_accounts_on_destroy = true
    }
    
    container_registry {
      prevent_deletion_if_contains_resources = false
    }
    
    key_vault {
      purge_soft_deleted_keys_on_destroy         = true
      purge_soft_deleted_secrets_on_destroy      = true
      purge_soft_deleted_certificates_on_destroy = true
      recover_soft_deleted_keys                  = true
      recover_soft_deleted_secrets               = true
      recover_soft_deleted_certificates          = true
    }
  }
}

provider "azapi" {
  # Configuration for Azure API provider for preview services
}

provider "random" {
  # Configuration for random provider
}