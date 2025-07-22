# Terraform version and provider requirements
terraform {
  required_version = ">= 1.0"
  
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.80"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4"
    }
  }
}

# Configure the Microsoft Azure Provider
provider "azurerm" {
  features {
    # Enable enhanced features for Container Apps
    container_apps {
      prevent_deletion_if_contains_resources = false
    }
    
    # Enable features for Cognitive Services
    cognitive_account {
      purge_soft_deleted_on_destroy = true
    }
    
    # Enable features for Service Bus
    service_bus {
      # Allow Service Bus namespace deletion even if it contains resources
    }
    
    # Enable features for Key Vault
    key_vault {
      purge_soft_deleted_certificates_on_destroy = true
      purge_soft_deleted_keys_on_destroy         = true
      purge_soft_deleted_secrets_on_destroy      = true
      recover_soft_deleted_certificates          = true
      recover_soft_deleted_keys                  = true
      recover_soft_deleted_secrets               = true
    }
  }
}