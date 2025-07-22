# Terraform version and provider requirements
terraform {
  required_version = ">= 1.0"
  
  required_providers {
    # Azure Resource Manager provider for managing Azure resources
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.80"
    }
    
    # Random provider for generating unique suffixes
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
    
    # Null provider for local provisioners
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

# Configure the Azure Provider with features
provider "azurerm" {
  features {
    # Configure resource group deletion behavior
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    
    # Configure Log Analytics workspace retention
    log_analytics_workspace {
      permanently_delete_on_destroy = true
    }
    
    # Configure Container Registry behavior
    container_registry {
      purge_soft_deleted_images_on_destroy = true
    }
  }
}

# Configure random provider
provider "random" {}

# Configure null provider
provider "null" {}