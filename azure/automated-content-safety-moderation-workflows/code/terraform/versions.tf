# Terraform version and provider requirements
terraform {
  required_version = ">= 1.6"
  
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.116"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# Configure the Azure Resource Manager provider
provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    cognitive_services {
      purge_soft_deleted_accounts_on_destroy = true
    }
  }
}

# Configure the Random provider for generating unique names
provider "random" {}