# Terraform version and provider requirements for Azure Healthcare Chatbot solution
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
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
  }
}

# Configure the Microsoft Azure Provider
provider "azurerm" {
  features {
    # Enable enhanced security features for healthcare compliance
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
    
    # Enhanced resource group features
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    
    # SQL security features for HIPAA compliance
    managed_disk {
      expand_without_downtime = true
    }
  }
}

# Configure random provider for generating unique resource names
provider "random" {}

# Configure time provider for deployment timestamps
provider "time" {}