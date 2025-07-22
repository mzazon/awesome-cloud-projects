# Terraform version and provider requirements for Intelligent Alert Response System
# This file defines the minimum Terraform version and required providers with their version constraints
# to ensure compatibility and stability across different environments and team members.

terraform {
  # Minimum Terraform version required for this configuration
  required_version = ">= 1.0"

  # Required providers with version constraints
  required_providers {
    # Azure Resource Manager provider for managing Azure resources
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }

    # Azure Active Directory provider for managing Azure AD resources
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.0"
    }

    # Random provider for generating unique resource names and identifiers
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }

    # Time provider for time-based operations and delays
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }

    # Null provider for null resources and triggers
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }

  # Optional: Configure backend for state management
  # Uncomment and configure based on your state management strategy
  # backend "azurerm" {
  #   resource_group_name  = "rg-terraform-state"
  #   storage_account_name = "tfstateXXXXXXXX"
  #   container_name       = "tfstate"
  #   key                  = "intelligent-alert-response-system.tfstate"
  # }

  # Optional: Configure cloud block for Terraform Cloud/Enterprise
  # cloud {
  #   organization = "your-organization"
  #   workspaces {
  #     name = "intelligent-alert-response-system"
  #   }
  # }
}

# Azure Resource Manager provider configuration
provider "azurerm" {
  # Enable features for specific resource types
  features {
    # Key Vault configuration
    key_vault {
      # Purge soft-deleted Key Vaults on destroy (use with caution in production)
      purge_soft_delete_on_destroy = true
      # Recover soft-deleted Key Vaults automatically
      recover_soft_deleted_key_vaults = true
    }

    # Resource Group configuration
    resource_group {
      # Prevent deletion of resource groups that contain resources
      prevent_deletion_if_contains_resources = false
    }

    # Storage Account configuration
    storage_account {
      # Prevent deletion of storage accounts with blobs
      prevent_deletion_if_contains_resources = false
    }

    # Cosmos DB configuration
    cosmos_db {
      # Prevent deletion of Cosmos DB accounts with data
      prevent_deletion_if_contains_resources = false
    }

    # Log Analytics configuration
    log_analytics {
      # Permanently delete Log Analytics workspaces on destroy
      permanently_delete_on_destroy = true
    }

    # Application Insights configuration
    application_insights {
      # Disable IP masking for Application Insights
      disable_ip_masking = false
    }

    # Virtual Machine configuration
    virtual_machine {
      # Delete OS disk on termination
      delete_os_disk_on_deletion = true
      # Graceful shutdown timeout
      graceful_shutdown_timeout = "5m"
    }
  }

  # Optional: Configure provider-specific settings
  # subscription_id = var.subscription_id
  # client_id       = var.client_id
  # client_secret   = var.client_secret
  # tenant_id       = var.tenant_id

  # Optional: Configure specific Azure environment
  # environment = "public" # public, usgovernment, german, china

  # Optional: Skip provider registration for faster deployments
  # skip_provider_registration = true

  # Optional: Configure partner ID for tracking
  # partner_id = "partner-id-here"
}

# Azure Active Directory provider configuration
provider "azuread" {
  # Optional: Configure provider-specific settings
  # client_id     = var.client_id
  # client_secret = var.client_secret
  # tenant_id     = var.tenant_id

  # Optional: Configure specific Azure environment
  # environment = "public"
}

# Random provider configuration
provider "random" {
  # No specific configuration required for random provider
}

# Time provider configuration
provider "time" {
  # No specific configuration required for time provider
}

# Null provider configuration
provider "null" {
  # No specific configuration required for null provider
}

# Data source for current Azure client configuration
data "azurerm_client_config" "current" {}

# Data source for current Azure AD client configuration
data "azuread_client_config" "current" {}

# Optional: Data source for Azure subscription information
data "azurerm_subscription" "current" {}

# Optional: Data source for Azure locations
data "azurerm_locations" "available" {
  location_filter {
    include_unavailable = false
  }
}

# Locals block for common configurations
locals {
  # Common tags to be applied to all resources
  common_tags = {
    ManagedBy          = "Terraform"
    Environment        = var.environment
    Purpose            = "intelligent-alerts"
    Project            = "alert-response-system"
    CreatedDate        = formatdate("YYYY-MM-DD", timestamp())
    TerraformVersion   = "~> 1.0"
    ProviderVersion    = "~> 3.0"
  }

  # Azure region settings
  location_short_names = {
    "East US"          = "eus"
    "East US 2"        = "eus2"
    "West US"          = "wus"
    "West US 2"        = "wus2"
    "West US 3"        = "wus3"
    "Central US"       = "cus"
    "North Central US" = "ncus"
    "South Central US" = "scus"
    "West Central US"  = "wcus"
    "Canada Central"   = "cac"
    "Canada East"      = "cae"
    "Brazil South"     = "brs"
    "UK South"         = "uks"
    "UK West"          = "ukw"
    "West Europe"      = "weu"
    "North Europe"     = "neu"
    "France Central"   = "frc"
    "Germany West Central" = "gwc"
    "Switzerland North" = "swn"
    "Norway East"      = "noe"
    "Sweden Central"   = "swc"
    "UAE North"        = "uan"
    "South Africa North" = "san"
    "Australia East"   = "aue"
    "Australia Southeast" = "ause"
    "Southeast Asia"   = "sea"
    "East Asia"        = "ea"
    "Japan East"       = "jpe"
    "Japan West"       = "jpw"
    "Korea Central"    = "krc"
    "India Central"    = "inc"
    "Central India"    = "ci"
    "South India"      = "si"
  }

  # Resource naming conventions
  naming_convention = {
    resource_group        = "rg"
    storage_account       = "st"
    function_app          = "func"
    logic_app            = "logic"
    event_grid_topic     = "eg"
    cosmos_db_account    = "cosmos"
    key_vault            = "kv"
    log_analytics        = "law"
    application_insights = "ai"
    workbook             = "wb"
    action_group         = "ag"
    metric_alert         = "ma"
    service_plan         = "plan"
  }

  # Current deployment metadata
  deployment_metadata = {
    terraform_version = "~> 1.0"
    azurerm_version  = "~> 3.0"
    azuread_version  = "~> 2.0"
    random_version   = "~> 3.0"
    time_version     = "~> 0.9"
    null_version     = "~> 3.0"
  }
}

# Optional: Terraform settings for experimental features
# terraform {
#   experiments = []
# }

# Optional: Provider aliases for multi-region deployments
# provider "azurerm" {
#   alias = "secondary"
#   features {}
#   # Configure for secondary region
# }

# Optional: Custom provider configurations for specific scenarios
# provider "azurerm" {
#   alias = "management"
#   features {}
#   subscription_id = var.management_subscription_id
# }

# Comments for version upgrade guidance:
# - When upgrading azurerm provider to v4.x, review breaking changes
# - When upgrading Terraform to v1.x+, review new features and syntax changes
# - Always test upgrades in non-production environments first
# - Consider using version constraints (~> major.minor) for stability
# - Review provider changelog before upgrading versions