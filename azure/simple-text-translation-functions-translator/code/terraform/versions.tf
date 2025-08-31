# ==============================================================================
# Simple Text Translation with Functions and Translator - Provider Configuration
# ==============================================================================
# Terraform and provider version requirements for the text translation
# infrastructure. This ensures consistent and reliable deployments across
# different environments and team members.

terraform {
  # Minimum Terraform version required
  required_version = ">= 1.0"

  # Required providers with version constraints
  required_providers {
    # Azure Resource Manager provider for managing Azure resources
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }

    # Random provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }

  # Optional: Configure remote state backend
  # Uncomment and configure for team collaboration
  # backend "azurerm" {
  #   resource_group_name  = "rg-terraform-state"
  #   storage_account_name = "terraformstateXXXXX"
  #   container_name       = "tfstate"
  #   key                  = "translation-function.terraform.tfstate"
  # }
}

# Configure the Azure Provider
provider "azurerm" {
  # Enable all available resource provider features
  features {
    # Key Vault features
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }

    # Cognitive Services features
    cognitive_account {
      purge_soft_delete_on_destroy = true
    }

    # Storage features
    storage {
      # Prevent accidental deletion of storage accounts with data
      prevent_deletion_if_contains_resources = true
    }

    # Application Insights features
    application_insights {
      disable_generated_rule = false
    }

    # Resource Group features
    resource_group {
      prevent_deletion_if_contains_resources = true
    }
  }

  # Optional: Specify subscription ID explicitly
  # subscription_id = var.subscription_id

  # Optional: Configure for specific Azure cloud environment
  # environment = "public"  # or "usgovernment", "china", "german"

  # Optional: Skip provider registration for faster deployments
  # skip_provider_registration = true
}

# Configure the Random Provider
provider "random" {
  # No specific configuration required for the random provider
}

# Optional: Configure additional providers for enhanced functionality

# Azure AD provider for advanced identity management (uncomment if needed)
# provider "azuread" {
#   tenant_id = data.azurerm_client_config.current.tenant_id
# }

# Time provider for time-based resources (uncomment if needed)
# provider "time" {
#   # No specific configuration required
# }