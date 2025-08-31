# ===================================================================
# Provider Requirements and Version Constraints
# ===================================================================
# This file defines the required Terraform version and provider versions
# for the Azure Content Personalization Engine infrastructure.

terraform {
  # Terraform version constraint
  required_version = ">= 1.5.0"

  # Required providers with version constraints
  required_providers {
    # Azure Resource Manager provider
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.116"
    }

    # Random provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }

    # Time provider for deployment timestamps and delays
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }
  }

  # Optional: Configure remote state backend
  # Uncomment and configure for production deployments
  /*
  backend "azurerm" {
    resource_group_name  = "rg-terraform-state"
    storage_account_name = "stterraformstate"
    container_name       = "tfstate"
    key                  = "content-personalization.tfstate"
  }
  */

  # Optional: Configure Terraform Cloud backend
  # Uncomment and configure for Terraform Cloud deployments
  /*
  cloud {
    organization = "your-organization"
    workspaces {
      name = "azure-content-personalization"
    }
  }
  */
}

# ===================================================================
# Provider Configuration
# ===================================================================

# Configure the Azure Provider
provider "azurerm" {
  # Enable provider features with specific configurations
  features {
    # Resource group configuration
    resource_group {
      # Allow deletion of resource groups containing resources
      prevent_deletion_if_contains_resources = false
    }

    # Key Vault configuration
    key_vault {
      # Purge soft-deleted Key Vaults immediately
      purge_soft_delete_on_destroy    = true
      # Recover soft-deleted Key Vaults on creation
      recover_soft_deleted_key_vaults = true
    }

    # Cognitive Services configuration
    cognitive_account {
      # Purge soft-deleted Cognitive Services immediately
      purge_soft_delete_on_destroy = true
    }

    # Storage account configuration
    storage {
      # Prevent soft-delete retention for test environments
      prevent_deletion_if_contains_resources = false
    }

    # Virtual machine configuration
    virtual_machine {
      # Delete OS disk on VM deletion
      delete_os_disk_on_deletion     = true
      # Graceful shutdown before deletion
      graceful_shutdown              = false
      # Skip shutdown and deallocate before deletion
      skip_shutdown_and_force_delete = false
    }

    # Machine Learning workspace configuration
    machine_learning {
      # Purge soft-deleted ML workspaces immediately
      purge_soft_deleted_workspace_on_destroy = true
    }
  }

  # Optional: Skip provider registration for specific scenarios
  # skip_provider_registration = true

  # Optional: Specify subscription ID if managing multiple subscriptions
  # subscription_id = var.subscription_id

  # Optional: Specify tenant ID for multi-tenant scenarios
  # tenant_id = var.tenant_id

  # Optional: Use specific authentication method
  # use_msi = true  # For Managed Service Identity
  # use_cli = false # Disable Azure CLI authentication
}

# Configure the Random Provider
provider "random" {
  # No specific configuration required for random provider
}

# Configure the Time Provider
provider "time" {
  # No specific configuration required for time provider
}

# ===================================================================
# Provider Version Information
# ===================================================================

# Local values for provider version tracking
locals {
  provider_versions = {
    terraform = ">=1.5.0"
    azurerm   = "~>3.116"
    random    = "~>3.6"
    time      = "~>0.12"
  }

  # Feature flags for provider capabilities
  provider_features = {
    azurerm_purge_soft_delete           = true
    azurerm_prevent_resource_deletion   = false
    azurerm_recover_soft_deleted_vaults = true
    cognitive_purge_on_destroy         = true
    ml_purge_on_destroy               = true
  }

  # Azure CLI minimum version requirement
  azure_cli_version_required = "2.50.0"

  # PowerShell Az module minimum version (if using PowerShell)
  powershell_az_version_required = "9.0.0"
}

# ===================================================================
# Version Validation
# ===================================================================

# Check if we're using a supported Terraform version
check "terraform_version" {
  assert {
    condition = can(regex("^1\\.(5|6|7|8|9)\\.", terraform.version))
    error_message = "This configuration requires Terraform version 1.5.0 or later. Current version: ${terraform.version}"
  }
}

# ===================================================================
# Provider Configuration Validation
# ===================================================================

# Validate Azure provider configuration
data "azurerm_client_config" "version_check" {}

# Local validation for Azure subscription access
locals {
  validate_azure_access = data.azurerm_client_config.version_check.subscription_id != "" ? true : false
}

# ===================================================================
# Development vs Production Provider Settings
# ===================================================================

# Different provider configurations based on environment
# This can be used with workspace-specific terraform.tfvars files

locals {
  # Environment-specific provider features
  environment_features = var.environment == "prod" ? {
    # Production: Enable protections
    prevent_deletion = true
    purge_soft_delete = false
    recover_soft_deleted = true
  } : {
    # Development: Allow faster cleanup
    prevent_deletion = false
    purge_soft_delete = true
    recover_soft_deleted = false
  }
}

# ===================================================================
# Required Azure Resource Providers
# ===================================================================

# Note: The following Azure resource providers must be registered
# in your subscription for this configuration to work:
# - Microsoft.DocumentDB (for Cosmos DB)
# - Microsoft.CognitiveServices (for Azure OpenAI)
# - Microsoft.Web (for Function Apps)
# - Microsoft.Storage (for Storage Accounts)
# - Microsoft.KeyVault (for Key Vault)
# - Microsoft.Insights (for Application Insights)
# - Microsoft.MachineLearningServices (for AI Foundry)

# You can register these using Azure CLI:
# az provider register --namespace Microsoft.DocumentDB
# az provider register --namespace Microsoft.CognitiveServices
# az provider register --namespace Microsoft.Web
# az provider register --namespace Microsoft.Storage
# az provider register --namespace Microsoft.KeyVault  
# az provider register --namespace Microsoft.Insights
# az provider register --namespace Microsoft.MachineLearningServices

# ===================================================================
# Compatibility Information
# ===================================================================

# This configuration is compatible with:
# - Terraform >= 1.5.0
# - Azure CLI >= 2.50.0
# - PowerShell Az module >= 9.0.0
# - Azure Resource Manager API versions as of late 2024
# - Azure OpenAI service (preview features)
# - Azure Cosmos DB NoSQL API with vector search
# - Azure Machine Learning workspace (AI Foundry foundation)

# Known limitations:
# - Vector search in Cosmos DB requires preview feature registration
# - Azure OpenAI availability varies by region
# - Some AI Foundry features may be in preview
# - Managed identity permissions may take time to propagate

# ===================================================================
# Migration Notes
# ===================================================================

# If migrating from older provider versions:
# - AzureRM 3.x: Review breaking changes in resource configurations
# - Terraform 1.4 to 1.5+: Check for deprecated syntax
# - Provider authentication: Ensure service principal or managed identity has required permissions

# Upgrade path:
# 1. terraform init -upgrade
# 2. terraform plan (review changes)
# 3. terraform apply (apply with caution)

# ===================================================================
# Security Considerations
# ===================================================================

# Provider security best practices:
# - Use managed identity when running in Azure
# - Store state files in encrypted Azure Storage with access controls
# - Use Azure Key Vault for sensitive configuration values
# - Enable audit logging for all provider operations
# - Regularly update provider versions for security patches