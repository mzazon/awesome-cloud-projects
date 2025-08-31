# Terraform version constraints and provider requirements
# This file defines the minimum Terraform version and required providers for
# the Customer Support Assistant with OpenAI Assistants and Functions deployment

terraform {
  # Minimum Terraform version required
  required_version = ">= 1.6"

  # Required providers with version constraints
  required_providers {
    # Azure Resource Manager provider for managing Azure resources
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.80"
    }

    # Random provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }

    # Time provider for handling time-based operations
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
  }
}

# Azure Resource Manager provider configuration
provider "azurerm" {
  # Enable features for specific resource types
  features {
    # Resource group configuration
    resource_group {
      # Allow deletion of resource groups that contain resources
      prevent_deletion_if_contains_resources = false
    }

    # Cognitive Services configuration
    cognitive_account {
      # Purge soft-deleted Cognitive Services accounts on destroy
      purge_soft_delete_on_destroy = true
    }

    # Key Vault configuration (if needed for secrets management)
    key_vault {
      # Purge soft-deleted Key Vaults on destroy
      purge_soft_delete_on_destroy    = true
      # Recover soft-deleted Key Vaults before creating new ones
      recover_soft_deleted_key_vaults = true
    }

    # Storage account configuration
    storage {
      # Prevent deletion of storage accounts with nested resources
      prevent_deletion_if_contains_resources = false
    }

    # Application Insights configuration
    application_insights {
      # Disable IP masking for better analytics
      disable_ip_masking = false
    }

    # Log Analytics workspace configuration
    log_analytics_workspace {
      # Allow permanently deleting workspaces on destroy
      permanently_delete_on_destroy = true
    }
  }
}

# Random provider configuration
provider "random" {
  # No specific configuration required for random provider
}

# Time provider configuration
provider "time" {
  # No specific configuration required for time provider
}