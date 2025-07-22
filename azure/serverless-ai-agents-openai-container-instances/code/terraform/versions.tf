# Terraform version and provider requirements
terraform {
  required_version = ">= 1.5.0"
  
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.80"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4"
    }
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
  }
}

# Configure the Azure Provider
provider "azurerm" {
  features {
    # Enable enhanced security features
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    
    # Cognitive Services security
    cognitive_account {
      purge_soft_delete_on_destroy = true
    }
    
    # Storage Account security
    storage {
      prevent_deletion_if_contains_resources = false
    }
  }
}

# Random suffix for unique resource names
provider "random" {}

# Docker provider for container image builds
provider "docker" {
  # Configuration will be provided through Azure Container Registry
}