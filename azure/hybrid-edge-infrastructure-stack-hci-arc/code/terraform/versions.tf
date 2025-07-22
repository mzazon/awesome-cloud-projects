# Terraform and provider version requirements
# This file specifies the minimum versions for Terraform and required providers

terraform {
  required_version = ">= 1.5.0"
  
  required_providers {
    # Azure Resource Manager provider for main Azure resources
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.80"
    }
    
    # Azure Active Directory provider for identity management
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.47"
    }
    
    # Random provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    
    # Time provider for resource delays and scheduling
    time = {
      source  = "hashicorp/time"
      version = "~> 0.10"
    }
  }
}

# Configure the Azure Provider with required features
provider "azurerm" {
  features {
    # Resource group management settings
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    
    # Key vault management settings
    key_vault {
      purge_soft_delete_on_destroy    = false
      recover_soft_deleted_key_vaults = false
    }
    
    # Storage account management settings  
    storage {
      prevent_nested_items_deletion = false
    }
    
    # Log Analytics workspace settings
    log_analytics_workspace {
      permanently_delete_on_destroy = false
    }
  }
}

# Configure Azure AD provider
provider "azuread" {
  # Use default tenant from Azure CLI context
}

# Configure random provider
provider "random" {
  # No configuration required
}

# Configure time provider
provider "time" {
  # No configuration required
}