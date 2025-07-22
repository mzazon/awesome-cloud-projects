# =============================================================================
# Terraform and Provider Version Constraints
# =============================================================================
# This file defines the required versions for Terraform and providers used in
# the Azure IoT Edge Analytics with Percept and Sphere infrastructure deployment.

terraform {
  # Minimum Terraform version required
  required_version = ">= 1.5.0"

  # Provider requirements with version constraints
  required_providers {
    # Azure Resource Manager provider
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.80"
    }

    # Random provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }

    # Time provider for timestamp operations
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }

    # Null provider for conditional resources and triggers
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }

    # TLS provider for certificate operations (if needed for Azure Sphere)
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

  # Optional: Configure backend for state management
  # Uncomment and configure based on your requirements
  #
  # backend "azurerm" {
  #   resource_group_name  = "tfstate-rg"
  #   storage_account_name = "tfstatestorage"
  #   container_name       = "tfstate"
  #   key                  = "iot-edge-analytics.terraform.tfstate"
  # }
}

# =============================================================================
# Azure Provider Configuration
# =============================================================================

provider "azurerm" {
  # Enable all features for the AzureRM provider
  features {
    # Key Vault configuration
    key_vault {
      # Purge soft deleted Key Vaults on destroy
      purge_soft_delete_on_destroy    = true
      # Recover soft deleted Key Vaults
      recover_soft_deleted_key_vaults = true
    }

    # Storage configuration
    storage {
      # Purge soft deleted storage accounts on destroy
      purge_soft_delete_on_destroy = true
    }

    # Resource Group configuration
    resource_group {
      # Prevent deletion of resource groups containing resources
      prevent_deletion_if_contains_resources = true
    }

    # Log Analytics Workspace configuration
    log_analytics_workspace {
      # Permanently delete workspace on destroy
      permanently_delete_on_destroy = true
    }

    # Application Insights configuration
    application_insights {
      # Disable IP masking for Application Insights
      disable_ip_masking = false
    }

    # Cognitive Services configuration
    cognitive_services {
      # Purge soft deleted Cognitive Services on destroy
      purge_soft_delete_on_destroy = true
    }

    # Template Deployment configuration
    template_deployment {
      # Delete nested items on destroy
      delete_nested_items_during_deletion = true
    }

    # Virtual Machine configuration
    virtual_machine {
      # Delete OS disk on deletion
      delete_os_disk_on_deletion = true
      # Graceful shutdown
      graceful_shutdown = false
      # Skip shutdown and force delete
      skip_shutdown_and_force_delete = false
    }

    # Virtual Machine Scale Set configuration
    virtual_machine_scale_set {
      # Force delete when in failed state
      force_delete                  = false
      # Roll instances when required
      roll_instances_when_required  = true
      # Scale to zero before deletion
      scale_to_zero_before_deletion = true
    }

    # API Management configuration
    api_management {
      # Purge soft delete on destroy
      purge_soft_delete_on_destroy = true
      # Recover soft deleted
      recover_soft_deleted         = true
    }

    # App Configuration configuration
    app_configuration {
      # Purge soft delete on destroy
      purge_soft_delete_on_destroy = true
      # Recover soft deleted
      recover_soft_deleted         = true
    }

    # Managed Disk configuration
    managed_disk {
      # Expand without downtime when possible
      expand_without_downtime = true
    }
  }

  # Optional: Configure specific subscription, tenant, and client details
  # subscription_id = var.subscription_id
  # tenant_id       = var.tenant_id
  # client_id       = var.client_id
  # client_secret   = var.client_secret

  # Optional: Use MSI authentication
  # use_msi = true

  # Optional: Use Azure CLI authentication
  # use_cli = true

  # Optional: Use Azure DevOps authentication
  # use_azuread_auth = true

  # Configure provider metadata
  partner_id = "a79fe048-6869-45ac-8683-7fd2446fc73c" # Microsoft partner ID for tracking
}

# =============================================================================
# Random Provider Configuration
# =============================================================================

provider "random" {
  # Random provider doesn't require specific configuration
}

# =============================================================================
# Time Provider Configuration
# =============================================================================

provider "time" {
  # Time provider doesn't require specific configuration
}

# =============================================================================
# Null Provider Configuration
# =============================================================================

provider "null" {
  # Null provider doesn't require specific configuration
}

# =============================================================================
# TLS Provider Configuration
# =============================================================================

provider "tls" {
  # TLS provider doesn't require specific configuration
}

# =============================================================================
# Data Sources for Provider Information
# =============================================================================

# Get information about the Azure Resource Manager provider
data "azurerm_client_config" "current" {}

# Get information about the current subscription
data "azurerm_subscription" "current" {}

# =============================================================================
# Provider Requirements Documentation
# =============================================================================

# This configuration requires the following provider versions:
# - azurerm: ~> 3.80 (Azure Resource Manager provider)
# - random: ~> 3.6 (Random provider for unique naming)
# - time: ~> 0.9 (Time provider for timestamps)
# - null: ~> 3.2 (Null provider for conditional resources)
# - tls: ~> 4.0 (TLS provider for certificate operations)
#
# Minimum Terraform version: 1.5.0
#
# The AzureRM provider is configured with the following features:
# - Key Vault: Purge soft deleted vaults on destroy
# - Storage: Purge soft deleted storage accounts on destroy
# - Resource Group: Prevent deletion if contains resources
# - Log Analytics: Permanently delete workspace on destroy
# - Application Insights: Disable IP masking
#
# For production deployments, consider:
# 1. Configuring remote state backend (Azure Storage Account)
# 2. Using service principal authentication
# 3. Implementing proper access controls
# 4. Setting up monitoring and alerting for Terraform operations
# 5. Using Terraform Cloud or Azure DevOps for CI/CD pipelines
#
# Authentication Methods (choose one):
# 1. Azure CLI: az login
# 2. Service Principal: Set ARM_CLIENT_ID, ARM_CLIENT_SECRET, ARM_TENANT_ID
# 3. Managed Identity: Use managed identity when running on Azure
# 4. Azure DevOps: Use Azure DevOps service connection
#
# Environment Variables:
# - ARM_SUBSCRIPTION_ID: Azure subscription ID
# - ARM_TENANT_ID: Azure tenant ID
# - ARM_CLIENT_ID: Service principal client ID
# - ARM_CLIENT_SECRET: Service principal client secret
# - ARM_USE_MSI: Use managed identity (true/false)
# - ARM_USE_CLI: Use Azure CLI (true/false)
#
# For more information, see:
# https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs