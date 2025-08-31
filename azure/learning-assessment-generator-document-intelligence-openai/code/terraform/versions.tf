# Terraform version and provider requirements
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
  }
}

# Configure the Azure Provider
provider "azurerm" {
  features {
    # Enable enhanced resource cleanup for development environments
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    
    # Configure Cognitive Services account cleanup behavior
    cognitive_services {
      purge_soft_delete_on_destroy = true
    }
    
    # Configure Cosmos DB account cleanup behavior
    cosmosdb {
      ignore_server_version_change = false
    }
  }
}