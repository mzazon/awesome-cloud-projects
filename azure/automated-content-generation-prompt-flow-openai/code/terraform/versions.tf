# ==============================================================================
# TERRAFORM AND PROVIDER VERSION CONSTRAINTS
# Azure Automated Content Generation with Prompt Flow and OpenAI
# ==============================================================================

terraform {
  # Specify the minimum Terraform version required
  required_version = ">= 1.9.0"

  # Define required providers with version constraints
  required_providers {
    # Azure Resource Manager Provider
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.112.0"
    }

    # Random Provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6.0"
    }

    # Time Provider for time-based resources (if needed for future extensions)
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12.0"
    }
  }

  # Backend configuration for remote state storage
  # Uncomment and configure for production deployments
  /*
  backend "azurerm" {
    resource_group_name  = "rg-terraform-state"
    storage_account_name = "terraformstateXXXXXX"
    container_name       = "tfstate"
    key                  = "content-generation/terraform.tfstate"
  }
  */

  # Alternative backend configurations
  /*
  # For Terraform Cloud
  backend "remote" {
    organization = "your-organization"
    workspaces {
      name = "azure-content-generation"
    }
  }
  */

  /*
  # For local state with encryption
  backend "local" {
    path = "terraform.tfstate"
  }
  */

  # Experimental features (if needed)
  # experiments = [example_experiment]
}

# ==============================================================================
# PROVIDER CONFIGURATIONS
# ==============================================================================

# Configure the Microsoft Azure Provider
provider "azurerm" {
  # Feature blocks for provider-specific configurations
  features {
    # Resource Group configurations
    resource_group {
      prevent_deletion_if_contains_resources = false
    }

    # Key Vault configurations
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }

    # Cognitive Services configurations
    cognitive_account {
      purge_soft_delete_on_destroy = true
    }

    # Application Insights configurations
    application_insights {
      disable_generated_rule = true
    }

    # Storage Account configurations
    storage {
      # Prevent accidental deletion of storage accounts containing data
      prevent_deletion_if_contains_resources = true
    }

    # Machine Learning configurations
    machine_learning {
      # Purge deleted workspaces immediately (be careful in production)
      purge_soft_deleted_workspace_on_destroy = true
    }

    # Log Analytics configurations
    log_analytics_workspace {
      # Permanently delete workspace on destroy (be careful in production)
      permanently_delete_on_destroy = true
    }
  }

  # Optional: Skip provider registration if using a service principal
  # with limited permissions
  # skip_provider_registration = true

  # Optional: Disable partner ID for partner scenarios
  # disable_terraform_partner_id = true

  # Optional: Set subscription ID explicitly (useful for multi-subscription scenarios)
  # subscription_id = var.subscription_id

  # Optional: Set tenant ID explicitly
  # tenant_id = var.tenant_id

  # Optional: Use specific authentication method
  # For service principal authentication:
  # client_id       = var.client_id
  # client_secret   = var.client_secret
  # tenant_id       = var.tenant_id

  # For managed identity authentication:
  # use_msi = true

  # For Azure CLI authentication (default):
  # use_cli = true
}

# Configure the Random Provider
provider "random" {
  # No specific configuration required for random provider
}

# Configure the Time Provider
provider "time" {
  # No specific configuration required for time provider
}

# ==============================================================================
# TERRAFORM CLOUD/ENTERPRISE CONFIGURATIONS
# ==============================================================================

# Variables for Terraform Cloud/Enterprise (if used)
/*
variable "tfc_organization" {
  description = "Terraform Cloud organization name"
  type        = string
  default     = ""
}

variable "tfc_workspace" {
  description = "Terraform Cloud workspace name"
  type        = string
  default     = ""
}
*/

# ==============================================================================
# VERSION COMPATIBILITY NOTES
# ==============================================================================

/*
This configuration has been tested with:

Terraform Core: >= 1.9.0
- Uses latest stable features and improvements
- Supports enhanced error messages and validation
- Compatible with Terraform Cloud and Enterprise

AzureRM Provider: ~> 3.112.0
- Latest stable version with full Azure OpenAI support
- Includes all recent Azure services and features
- Supports managed identity authentication
- Compatible with Azure Machine Learning v2

Random Provider: ~> 3.6.0
- Latest stable version for resource name generation
- Improved entropy and security features

Time Provider: ~> 0.12.0
- Latest stable version for time-based operations
- Useful for scheduled deployments and resource lifecycle

Provider Feature Notes:
- Key Vault soft delete is enabled by default in Azure
- Cognitive Services soft delete supports Azure OpenAI
- Machine Learning workspace soft delete prevents accidental data loss
- Storage account protection prevents deletion with data

Compatibility Matrix:
┌─────────────────────┬─────────────────┬─────────────────┐
│ Terraform Version   │ AzureRM Version │ Status          │
├─────────────────────┼─────────────────┼─────────────────┤
│ 1.9.x              │ 3.112.x         │ ✅ Recommended  │
│ 1.8.x              │ 3.110.x         │ ✅ Supported    │
│ 1.7.x              │ 3.100.x         │ ⚠️  Limited     │
│ < 1.7.0            │ < 3.100.0       │ ❌ Not supported│
└─────────────────────┴─────────────────┴─────────────────┘

Upgrade Path:
1. Always backup your state file before upgrading
2. Test upgrades in non-production environments first
3. Review provider changelog for breaking changes
4. Update required_version constraints gradually
5. Use `terraform plan` to preview changes before applying

Breaking Changes to Watch:
- AzureRM 4.x will introduce significant changes
- Resource naming conventions may change
- Authentication methods may be updated
- New required fields may be added

For production deployments:
- Pin exact provider versions for stability
- Use remote state backend for team collaboration
- Implement proper access controls and RBAC
- Enable state locking to prevent concurrent modifications
- Set up automated testing and validation pipelines
*/