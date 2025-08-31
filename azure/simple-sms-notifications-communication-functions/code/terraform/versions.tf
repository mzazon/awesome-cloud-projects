# Terraform configuration for SMS notifications with Azure Communication Services and Functions
# This configuration defines provider requirements and versions for the infrastructure

terraform {
  required_version = ">= 1.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
  }
}

# Configure the Microsoft Azure Provider
provider "azurerm" {
  features {
    # Configure resource group behavior
    resource_group {
      prevent_deletion_if_contains_resources = false
    }

    # Configure storage account behavior
    storage {
      prevent_deletion_if_contains_resources = false
    }

    # Configure communication services behavior  
    communication {
      purge_soft_deleted_communication_services_on_destroy = true
    }
  }
}

# Configure the Random Provider for generating unique resource names
provider "random" {}