# Terraform version and provider requirements for Azure Cost Governance
# This file specifies the required Terraform version and provider constraints

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    # Azure Resource Manager Provider
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.80"
    }

    # Azure Active Directory Provider
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.45"
    }

    # Random Provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4"
    }

    # Local Provider for creating local files (Resource Graph queries)
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }

    # Time Provider for time-based operations
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
  }

  # Optional: Configure backend for remote state storage
  # Uncomment and configure according to your requirements
  
  # backend "azurerm" {
  #   resource_group_name  = "rg-terraform-state"
  #   storage_account_name = "tfstateXXXXXXXX"
  #   container_name       = "tfstate"
  #   key                  = "cost-governance.terraform.tfstate"
  # }

  # Alternative backend configurations:
  
  # backend "remote" {
  #   organization = "your-org"
  #   workspaces {
  #     name = "cost-governance-azure"
  #   }
  # }
  
  # backend "s3" {
  #   bucket = "your-terraform-state-bucket"
  #   key    = "azure/cost-governance/terraform.tfstate"
  #   region = "us-east-1"
  # }
}

# Provider configuration with feature flags
provider "azurerm" {
  features {
    # Key Vault configuration
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }

    # Resource Group configuration
    resource_group {
      prevent_deletion_if_contains_resources = false
    }

    # Storage configuration
    storage {
      prevent_deletion_if_contains_resources = false
    }

    # Logic App configuration
    logic_app_workflow {
      delete_draft_versions_on_destroy = true
    }

    # Cost Management configuration
    cost_management {
      # Enable cost management features
    }
  }

  # Optional: Configure provider-specific settings
  # Uncomment and configure according to your requirements
  
  # subscription_id = var.subscription_id
  # tenant_id       = var.tenant_id
  # client_id       = var.client_id
  # client_secret   = var.client_secret
  
  # Use managed identity when running in Azure
  # use_msi = true
  
  # Use Azure CLI authentication (default)
  # use_cli = true
  
  # Skip provider registration if already registered
  # skip_provider_registration = true
}

# Azure Active Directory Provider configuration
provider "azuread" {
  # Use same authentication as azurerm provider
  # tenant_id = var.tenant_id
  # client_id = var.client_id
  # client_secret = var.client_secret
}

# Random Provider configuration
provider "random" {
  # No specific configuration required
}

# Local Provider configuration
provider "local" {
  # No specific configuration required
}

# Time Provider configuration
provider "time" {
  # No specific configuration required
}

# Optional: Configure experiment features
# Uncomment to enable specific Terraform experimental features
# terraform {
#   experiments = [
#     # Add experimental features here
#   ]
# }

# Optional: Configure cloud backend
# Uncomment and configure if using Terraform Cloud/Enterprise
# cloud {
#   organization = "your-organization"
#   workspaces {
#     name = "cost-governance-azure"
#   }
# }