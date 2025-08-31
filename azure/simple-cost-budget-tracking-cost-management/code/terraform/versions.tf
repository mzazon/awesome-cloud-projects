# Configure Terraform and required providers
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

# Configure the Azure Provider with features
provider "azurerm" {
  features {}
}

# Data source to get current subscription information
data "azurerm_subscription" "current" {}

# Data source to get current client configuration (used for subscription ID)
data "azurerm_client_config" "current" {}