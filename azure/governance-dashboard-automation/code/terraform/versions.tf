# ===============================================
# Terraform and Provider Version Requirements
# ===============================================
# This file defines the minimum required versions for Terraform
# and Azure providers to ensure compatibility and access to
# the latest features for governance dashboard implementation.

terraform {
  # Minimum Terraform version required
  required_version = ">= 1.0"

  # Required providers configuration
  required_providers {
    # Azure Resource Manager Provider
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.110"
    }

    # Random Provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4"
    }

    # Local Provider for managing local files
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }

    # Time Provider for handling time-based resources
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
  }

  # Optional: Configure remote state backend
  # Uncomment and configure based on your requirements
  
  # backend "azurerm" {
  #   resource_group_name  = "terraform-state-rg"
  #   storage_account_name = "terraformstateaccount"
  #   container_name       = "tfstate"
  #   key                  = "governance-dashboard.terraform.tfstate"
  # }

  # Alternative backend configurations:
  
  # backend "remote" {
  #   organization = "your-organization"
  #   workspaces {
  #     name = "governance-dashboard"
  #   }
  # }

  # backend "s3" {
  #   bucket = "your-terraform-state-bucket"
  #   key    = "azure/governance-dashboard/terraform.tfstate"
  #   region = "us-east-1"
  # }
}

# ===============================================
# Provider Configuration
# ===============================================

# Configure the Azure Provider with features
provider "azurerm" {
  # Enable or disable various Azure features
  features {
    # Resource Group features
    resource_group {
      prevent_deletion_if_contains_resources = false
    }

    # Key Vault features
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }

    # Virtual Machine features
    virtual_machine {
      delete_os_disk_on_deletion     = true
      graceful_shutdown              = false
      skip_shutdown_and_force_delete = false
    }

    # Log Analytics Workspace features
    log_analytics_workspace {
      permanently_delete_on_destroy = false
    }

    # Application Insights features
    application_insights {
      disable_generated_rule = false
    }

    # Template Deployment features
    template_deployment {
      delete_nested_items_during_deletion = true
    }

    # Cognitive Services features
    cognitive_account {
      purge_soft_delete_on_destroy = true
    }

    # API Management features
    api_management {
      purge_soft_delete_on_destroy = true
      recover_soft_deleted         = true
    }
  }

  # Optional: Configure additional provider settings
  # storage_use_azuread        = true
  # disable_correlation_request_id = false
  # environment                = "public"
  # metadata_host              = "https://management.azure.com/"
  
  # Skip provider registration for certain resource providers
  # skip_provider_registration = false
  
  # Optional: Configure partner ID for tracking
  # partner_id = "your-partner-id"
}

# Configure the Random Provider
provider "random" {}

# Configure the Local Provider
provider "local" {}

# Configure the Time Provider
provider "time" {}

# ===============================================
# Terraform Cloud/Enterprise Configuration
# ===============================================
# Uncomment if using Terraform Cloud or Enterprise

# terraform {
#   cloud {
#     organization = "your-organization"
#     workspaces {
#       name = "governance-dashboard"
#     }
#   }
# }

# ===============================================
# Provider Version Constraints Explanation
# ===============================================
# 
# AzureRM Provider (~> 3.110):
# - Uses the latest stable 3.x version with backwards compatibility
# - Includes support for Monitor Workbooks, Logic Apps v2, and enhanced alerting
# - Provides improved Resource Graph integration and policy management
# - Supports the latest Azure services and features for governance
#
# Random Provider (~> 3.4):
# - Used for generating unique suffixes for resource names
# - Ensures resource name uniqueness across deployments
# - Provides cryptographically secure random generation
#
# Local Provider (~> 2.4):
# - Used for creating local files (e.g., sample Resource Graph queries)
# - Enables local file management as part of infrastructure deployment
# - Supports file templating and content generation
#
# Time Provider (~> 0.9):
# - Used for time-based resource configurations
# - Enables scheduled operations and time-dependent logic
# - Supports timezone conversions and timestamp generation
#
# ===============================================
# Experimental Features
# ===============================================
# Uncomment to enable experimental Terraform features if needed

# terraform {
#   experiments = [
#     example_feature
#   ]
# }

# ===============================================
# Version Upgrade Path
# ===============================================
# 
# When upgrading provider versions:
# 1. Review the CHANGELOG for breaking changes
# 2. Test in a development environment first
# 3. Update version constraints gradually
# 4. Run 'terraform init -upgrade' to update providers
# 5. Validate with 'terraform plan' before applying
#
# Example upgrade path:
# Current: azurerm = "~> 3.110"
# Next:    azurerm = "~> 3.115"
# Future:  azurerm = "~> 4.0"
#
# ===============================================
# Provider Plugin Cache Configuration
# ===============================================
# To improve performance, configure provider plugin caching:
# 
# CLI Configuration (~/.terraformrc or %APPDATA%\terraform.rc):
# plugin_cache_dir = "$HOME/.terraform.d/plugin-cache"
# disable_checkpoint = true
# 
# Environment Variables:
# export TF_PLUGIN_CACHE_DIR="$HOME/.terraform.d/plugin-cache"
# export TF_CLI_CONFIG_FILE="$HOME/.terraformrc"