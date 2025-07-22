# Terraform provider requirements for Azure precision agriculture analytics platform
# This configuration specifies the required providers and their versions

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    # Azure Resource Manager provider for core Azure resources
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.84"
    }
    
    # Random provider for generating unique resource names and suffixes
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    
    # Time provider for time-based resource naming and delays
    time = {
      source  = "hashicorp/time"
      version = "~> 0.10"
    }
  }
}

# Configure the Azure Provider with features
provider "azurerm" {
  features {
    # Enable features for specific Azure services
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    
    storage {
      # Prevent purging of storage accounts to avoid data loss
      prevent_soft_delete_on_destroy = false
    }
    
    cognitive_services {
      # Enable purging of cognitive services accounts when destroyed
      purge_soft_delete_on_destroy = true
    }
  }
}

# Configure random provider
provider "random" {}

# Configure time provider  
provider "time" {}