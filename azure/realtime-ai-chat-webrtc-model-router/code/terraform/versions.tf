# Terraform version and provider requirements
terraform {
  required_version = ">= 1.5"
  
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
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
    # Enable automatic purging of Cognitive Services accounts on deletion
    cognitive_account {
      purge_soft_delete_on_destroy = true
    }
    
    # Function App features
    app_service {
      # Disable key vault reference identity warning
      key_vault_reference_check_enabled = false
    }
  }
}