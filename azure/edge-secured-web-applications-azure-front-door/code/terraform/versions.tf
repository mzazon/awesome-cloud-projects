# versions.tf
# Terraform and provider version constraints for Azure Static Web Apps with Front Door WAF

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
    # Enable enhanced resource group deletion to handle dependencies
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    
    # Configure Front Door features
    cdn_frontdoor {
      purge_soft_delete_enabled = true
    }
  }
}

# Configure the Random Provider for unique resource naming
provider "random" {}