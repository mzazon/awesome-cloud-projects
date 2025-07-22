# Terraform provider requirements for Azure health monitoring infrastructure
terraform {
  required_version = ">= 1.5"
  
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.100"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# Configure the Azure Resource Manager Provider
provider "azurerm" {
  features {
    # Enable deletion of resources in resource groups
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    
    # Key Vault configuration for secrets management
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
    
    # Log Analytics workspace configuration
    log_analytics_workspace {
      permanently_delete_on_destroy = true
    }
  }
}