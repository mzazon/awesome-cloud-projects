# Terraform Configuration File for Azure Audio Summarization Solution
# This file specifies the required Terraform version and provider requirements

terraform {
  # Specify minimum Terraform version for compatibility
  required_version = ">= 1.6"

  # Define required providers and their versions
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    
    # Random provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

# Configure the Azure Provider with features block
provider "azurerm" {
  features {
    # Enable automatic purging of soft-deleted cognitive services
    cognitive_account {
      purge_soft_delete_on_destroy = true
    }
    
    # Resource group deletion behavior
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}