# Terraform version and provider requirements for Azure Confidential Computing
terraform {
  required_version = ">= 1.0"
  
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.80"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.47"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }
  }
}

# Configure the Azure Provider
provider "azurerm" {
  features {
    # Enable soft delete for Key Vault
    key_vault {
      purge_soft_delete_on_destroy    = var.enable_purge_protection ? false : true
      recover_soft_deleted_key_vaults = true
    }
    
    # Configure resource group deletion behavior
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    
    # Configure virtual machine features
    virtual_machine {
      delete_os_disk_on_deletion     = true
      graceful_shutdown             = false
      skip_shutdown_and_force_delete = false
    }
  }
}

# Configure Azure AD Provider
provider "azuread" {}

# Configure TLS Provider
provider "tls" {}

# Configure Random Provider
provider "random" {}

# Configure Local Provider
provider "local" {}