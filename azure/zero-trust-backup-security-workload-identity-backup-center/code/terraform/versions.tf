# versions.tf - Provider requirements and version constraints
# This file defines the required providers and their versions for the zero-trust backup security solution

terraform {
  required_version = ">= 1.0"

  required_providers {
    # Azure Resource Manager provider for core Azure resources
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }

    # Azure Active Directory provider for identity and access management
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.0"
    }

    # Random provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }

    # TLS provider for certificate generation
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }

    # Time provider for time-based operations
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
  }
}

# Configure the Azure Provider with features
provider "azurerm" {
  features {
    # Enable advanced Key Vault features
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }

    # Enable virtual machine features
    virtual_machine {
      delete_os_disk_on_deletion     = true
      graceful_shutdown              = false
      skip_shutdown_and_force_delete = false
    }

    # Enable resource group features
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

# Configure the Azure AD Provider
provider "azuread" {
  tenant_id = var.tenant_id
}