# ==================================================================================================
# TERRAFORM VERSION CONSTRAINTS AND PROVIDER REQUIREMENTS
# ==================================================================================================
# This file defines the minimum Terraform version and required providers with version constraints
# to ensure compatibility and stability of the Document Q&A infrastructure deployment.
# ==================================================================================================

terraform {
  # Minimum Terraform version required for this configuration
  # Version 1.3+ is required for enhanced validation features and latest provider compatibility
  required_version = ">= 1.3"

  # Required providers with version constraints for stability and feature availability
  required_providers {
    # Azure Resource Manager provider for managing Azure resources
    # Version 4.0+ includes latest Azure AI Search and OpenAI Service features
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
      configuration_aliases = []
    }

    # Random provider for generating unique resource names and values
    # Version 3.4+ provides enhanced string generation capabilities
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4"
    }

    # Time provider for managing time-based resources and operations
    # Used for deployment timing and resource provisioning delays
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }
  }

  # Optional: Configure Terraform Cloud or remote state backend
  # Uncomment and modify the following block if using Terraform Cloud or remote state
  #
  # cloud {
  #   organization = "your-terraform-organization"
  #   workspaces {
  #     name = "azure-document-qa"
  #   }
  # }

  # Optional: Configure remote state backend for team collaboration
  # Example configurations for different backend types:
  #
  # backend "azurerm" {
  #   resource_group_name  = "terraform-state-rg"
  #   storage_account_name = "terraformstate12345"
  #   container_name       = "tfstate"
  #   key                  = "document-qa/terraform.tfstate"
  # }
  #
  # backend "s3" {
  #   bucket = "your-terraform-state-bucket"
  #   key    = "azure/document-qa/terraform.tfstate"
  #   region = "us-east-1"
  # }
}

# ==================================================================================================
# PROVIDER CONFIGURATION BLOCKS
# ==================================================================================================

# Azure Resource Manager provider configuration with feature flags
provider "azurerm" {
  # Enable provider features that affect resource behavior
  features {
    # Cognitive Services (Azure OpenAI) configuration
    cognitive_account {
      # Enable automatic purging of soft-deleted cognitive services accounts
      # This accelerates testing and cleanup but reduces accidental deletion protection
      purge_soft_delete_on_destroy = true
      
      # Enable automatic purging when account is disabled
      purge_soft_delete_on_disable = false
    }

    # Resource Group configuration
    resource_group {
      # Allow deletion of resource groups containing resources
      # Useful for testing environments but should be false in production
      prevent_deletion_if_contains_resources = false
    }

    # Key Vault configuration (for future use with customer-managed keys)
    key_vault {
      # Purge soft-deleted Key Vaults on destroy
      # Enables faster testing cycles but reduces recovery options
      purge_soft_delete_on_destroy = true
      
      # Recover soft-deleted Key Vaults instead of failing
      recover_soft_deleted_key_vaults = true
    }

    # Storage Account configuration
    storage {
      # Purge soft-deleted storage accounts on destroy
      # Speeds up testing but reduces recovery protection
      purge_soft_delete_on_destroy = true
    }

    # Log Analytics Workspace configuration
    log_analytics_workspace {
      # Delete workspace permanently on destroy (no soft delete)
      permanently_delete_on_destroy = true
    }

    # Application Insights configuration
    application_insights {
      # Disable Application Insights on destroy
      disable_generated_rule = false
    }
  }

  # Optional: Skip provider registration if using service principal
  # with limited permissions that cannot register resource providers
  # skip_provider_registration = true

  # Optional: Configure specific subscription if different from default
  # subscription_id = "00000000-0000-0000-0000-000000000000"

  # Optional: Configure partner ID for tracking deployments
  # partner_id = "00000000-0000-0000-0000-000000000000"
}

# Random provider configuration
provider "random" {
  # No specific configuration required for random provider
}

# Time provider configuration  
provider "time" {
  # No specific configuration required for time provider
}

# ==================================================================================================
# PROVIDER VERSION COMPATIBILITY MATRIX
# ==================================================================================================

# The following provider versions have been tested and validated:
#
# azurerm provider versions:
# - 4.0.x: Initial release with OpenAI Service and AI Search improvements
# - 4.1.x: Enhanced security features and managed identity support
# - 4.2.x: Additional Function App configuration options
# - 4.3.x: Improved cognitive services deployment capabilities
#
# Terraform versions:
# - 1.3.x: Enhanced validation and provider requirement features
# - 1.4.x: Improved module and resource lifecycle management
# - 1.5.x: Enhanced state management and import capabilities
# - 1.6.x: Latest stable release with performance improvements
#
# Compatibility notes:
# - Azure CLI version 2.66.0+ recommended for authentication
# - PowerShell Az module 10.0+ for Windows environments
# - Ensure Azure subscription has necessary service quotas enabled
# - Verify regional availability for Azure OpenAI and AI Search services

# ==================================================================================================
# EXPERIMENTAL FEATURES AND ALPHA PROVIDERS
# ==================================================================================================

# The following experimental features may be available:
# - provider_meta blocks for additional provider configuration
# - enhanced for_each capabilities for complex resource loops
# - improved validation functions for variable constraints
#
# Note: Experimental features should not be used in production environments
# until they reach general availability status.

# ==================================================================================================
# DEPRECATED PROVIDER VERSIONS AND MIGRATION NOTES
# ==================================================================================================

# Important migration information:
# - azurerm 3.x is deprecated and not compatible with this configuration
# - cognitive_account resources replaced cognitive_services_account in 2.x
# - function_app resources replaced app_service_function in 2.x
# - search_service replaces search in 3.x
#
# Migration from earlier versions:
# 1. Update provider version constraints
# 2. Run 'terraform init -upgrade' to update providers
# 3. Review and update deprecated resource arguments
# 4. Test in non-production environment before applying to production
# 5. Consider using 'terraform plan' to preview changes

# ==================================================================================================
# PROVIDER PLUGIN CACHE CONFIGURATION
# ==================================================================================================

# For improved performance, consider configuring provider plugin cache:
# 1. Set TF_PLUGIN_CACHE_DIR environment variable
# 2. Create cache directory: mkdir -p ~/.terraform.d/plugin-cache
# 3. Export cache directory: export TF_PLUGIN_CACHE_DIR="$HOME/.terraform.d/plugin-cache"
#
# This reduces download time for provider plugins across multiple Terraform configurations.

# ==================================================================================================
# PROVIDER AUTHENTICATION METHODS
# ==================================================================================================

# The azurerm provider supports multiple authentication methods:
#
# 1. Azure CLI authentication (recommended for development):
#    - Run 'az login' before Terraform operations
#    - Automatically uses current Azure CLI context
#
# 2. Service Principal authentication (recommended for CI/CD):
#    - Set ARM_CLIENT_ID, ARM_CLIENT_SECRET, ARM_TENANT_ID, ARM_SUBSCRIPTION_ID
#    - Provides non-interactive authentication for automated deployments
#
# 3. Managed Identity authentication (for Azure-hosted deployments):
#    - Automatically available on Azure VMs, Container Instances, etc.
#    - Set use_msi = true in provider configuration
#
# 4. Azure PowerShell authentication:
#    - Alternative to Azure CLI for Windows environments
#    - Set use_azuread = true in provider configuration
#
# Choose the authentication method that best fits your deployment environment
# and security requirements.