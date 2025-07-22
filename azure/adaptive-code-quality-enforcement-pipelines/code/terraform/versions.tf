# Terraform and provider version requirements
terraform {
  required_version = ">= 1.0"
  
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

# Configure the Azure Provider
provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    
    application_insights {
      disable_generated_rule = false
    }
    
    logic_app {
      # Enable features for Logic Apps
    }
  }
}

# Configure the Azure Active Directory Provider
provider "azuread" {
  # Configuration options
}

# Configure the Random Provider
provider "random" {
  # Configuration options
}