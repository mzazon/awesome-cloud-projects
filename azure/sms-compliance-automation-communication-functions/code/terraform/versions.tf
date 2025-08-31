# Terraform and Provider Version Requirements
# This file defines the required versions for Terraform and all providers used in this configuration

terraform {
  # Specify minimum Terraform version required
  required_version = ">= 1.5"

  # Define required providers with version constraints
  required_providers {
    # Azure Resource Manager Provider
    # Official provider for managing Azure resources
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.84"
    }

    # Random Provider
    # Used for generating unique resource identifiers
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }

    # Time Provider
    # Used for time-based resources and delays
    time = {
      source  = "hashicorp/time"
      version = "~> 0.10"
    }

    # Local Provider
    # Used for local file operations and data processing
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }

    # Null Provider
    # Used for provisioner operations and resource lifecycle management
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }

  # Optional: Configure Terraform Cloud or Terraform Enterprise backend
  # Uncomment and configure the backend block below for remote state management
  
  # backend "azurerm" {
  #   # Example backend configuration for Azure Storage
  #   # resource_group_name  = "terraform-state-rg"
  #   # storage_account_name = "terraformstateaccount"
  #   # container_name       = "terraform-state"
  #   # key                  = "sms-compliance/terraform.tfstate"
  # }

  # backend "remote" {
  #   # Example backend configuration for Terraform Cloud
  #   # organization = "your-organization"
  #   # workspaces {
  #   #   name = "sms-compliance-automation"
  #   # }
  # }
}

# Configure the Azure Provider features and settings
provider "azurerm" {
  # Enable provider features with specific configurations
  features {
    # Resource Group management features
    resource_group {
      # Allow deletion of resource groups containing resources
      prevent_deletion_if_contains_resources = false
    }

    # Key Vault management features
    key_vault {
      # Purge soft-deleted Key Vaults immediately
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }

    # App Service management features
    app_service {
      # Enable App Service slot management
      enable_slot_swap = false
    }

    # Storage Account management features
    storage {
      # Prevent accidental data loss
      prevent_blob_deletion_if_contains_data = false
    }

    # Application Insights management features
    application_insights {
      # Disable API key management
      disable_generated_rule = false
    }

    # Log Analytics management features
    log_analytics_workspace {
      # Allow permanent deletion of Log Analytics workspaces
      permanently_delete_on_destroy = true
    }
  }

  # Optional: Configure provider-level settings
  # Use these settings to override defaults or specify subscription/tenant
  
  # subscription_id = var.azure_subscription_id
  # tenant_id       = var.azure_tenant_id
  # client_id       = var.azure_client_id
  # client_secret   = var.azure_client_secret

  # Alternative authentication methods:
  # use_msi         = true  # Use Managed Service Identity
  # use_cli         = true  # Use Azure CLI authentication
  # use_oidc        = true  # Use OpenID Connect authentication

  # Optional: Set default tags for all resources
  # default_tags {
  #   Environment = var.environment
  #   ManagedBy   = "Terraform"
  #   Project     = "SMS Compliance Automation"
  # }
}

# Configure the Random Provider
provider "random" {
  # Random provider doesn't require additional configuration
  # but you can specify it explicitly if needed
}

# Configure the Time Provider
provider "time" {
  # Time provider doesn't require additional configuration
  # Used for time-based resources like sleeping and rotating resources
}

# Configure the Local Provider
provider "local" {
  # Local provider doesn't require additional configuration
  # Used for local file operations and template rendering
}

# Configure the Null Provider
provider "null" {
  # Null provider doesn't require additional configuration
  # Used for provisioner operations and local-exec commands
}

# Version compatibility notes:
# - azurerm ~> 3.84: Uses the latest 3.x version of the Azure provider
#   - Supports all Azure Communication Services features including Opt-Out Management API
#   - Includes latest Azure Functions runtime support (v4)
#   - Compatible with Node.js 18 and 20 runtime stacks
#   - Supports managed identity and Key Vault integration
#
# - random ~> 3.6: Latest stable version for generating unique identifiers
#   - Used for creating unique resource suffixes
#   - Provides cryptographically secure random values
#
# - time ~> 0.10: Latest stable version for time-based operations
#   - Used for resource scheduling and rotation
#   - Supports timezone-aware operations
#
# - local ~> 2.4: Latest stable version for local operations
#   - Used for file operations and template rendering
#   - Supports both binary and text file operations
#
# - null ~> 3.2: Latest stable version for provisioner operations
#   - Used for local-exec and remote-exec provisioners
#   - Supports complex resource lifecycle management

# Terraform version requirements explanation:
# - >= 1.5: Minimum version supporting all required features
#   - Module composition and variable validation
#   - Enhanced error handling and debugging
#   - Improved plan output and state management
#   - Support for provider-defined functions
#   - Native testing framework support