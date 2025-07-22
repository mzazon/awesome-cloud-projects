# Terraform and Provider Version Configuration
# This file defines the required Terraform version and provider configurations
# for the Azure IoT Operations and Event Hubs manufacturing analytics solution

terraform {
  required_version = ">= 1.5.0"
  
  required_providers {
    # Azure Resource Manager provider for main Azure resources
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.100"
    }
    
    # Azure Active Directory provider for identity and access management
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.47"
    }
    
    # Random provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    
    # Time provider for resource deployment delays and scheduling
    time = {
      source  = "hashicorp/time"
      version = "~> 0.11"
    }
    
    # Local provider for generating configuration files
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }
  }
}

# Configure the Azure Resource Manager provider
provider "azurerm" {
  features {
    # Enable enhanced resource group deletion capabilities
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    
    # Configure key vault behavior for manufacturing secrets
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
    
    # Configure Event Hubs namespace behavior
    eventhub {
      prevent_deletion_if_contains_resources = false
    }
    
    # Configure Log Analytics workspace behavior
    log_analytics_workspace {
      permanently_delete_on_destroy = true
    }
  }
}

# Configure the Azure Active Directory provider
provider "azuread" {
  # Use default configuration from Azure CLI or environment variables
}

# Configure the Random provider
provider "random" {
  # Use default configuration
}

# Configure the Time provider
provider "time" {
  # Use default configuration
}

# Configure the Local provider
provider "local" {
  # Use default configuration
}