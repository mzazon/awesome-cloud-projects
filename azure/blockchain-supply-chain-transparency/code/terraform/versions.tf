# ==============================================================================
# TERRAFORM VERSION CONSTRAINTS
# ==============================================================================
# This file specifies the required Terraform version and provider versions
# for the blockchain supply chain transparency infrastructure.

terraform {
  # Specify the minimum Terraform version required
  required_version = ">= 1.0"

  # Define required providers and their version constraints
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

    # Random provider for generating unique values
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }

    # Time provider for time-based operations
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }

    # Null provider for provisioner-like operations
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }

    # Local provider for local operations
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }

    # Template provider for rendering templates
    template = {
      source  = "hashicorp/template"
      version = "~> 2.2"
    }

    # TLS provider for certificate operations
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }

    # HTTP provider for HTTP operations
    http = {
      source  = "hashicorp/http"
      version = "~> 3.0"
    }

    # External provider for external data sources
    external = {
      source  = "hashicorp/external"
      version = "~> 2.0"
    }
  }

  # Optional: Configure backend for state management
  # Uncomment and configure the backend block below for production deployments
  
  # backend "azurerm" {
  #   resource_group_name  = "terraform-state-rg"
  #   storage_account_name = "terraformstate"
  #   container_name       = "tfstate"
  #   key                  = "blockchain-supply-chain.terraform.tfstate"
  # }

  # Alternative backend configurations:
  
  # Remote backend for Terraform Cloud
  # backend "remote" {
  #   hostname     = "app.terraform.io"
  #   organization = "your-organization"
  #   workspaces {
  #     name = "blockchain-supply-chain-transparency"
  #   }
  # }

  # S3 backend for cross-cloud deployments
  # backend "s3" {
  #   bucket = "terraform-state-bucket"
  #   key    = "blockchain-supply-chain/terraform.tfstate"
  #   region = "us-east-1"
  # }

  # Local backend (default if no backend is specified)
  # backend "local" {
  #   path = "terraform.tfstate"
  # }
}

# ==============================================================================
# PROVIDER CONFIGURATIONS
# ==============================================================================

# Configure the Azure Provider features
provider "azurerm" {
  # Enable specific features for Azure resources
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

    # Cognitive Services configuration
    cognitive_account {
      purge_soft_delete_on_destroy = true
    }

    # Template deployment configuration
    template_deployment {
      delete_nested_items_during_deletion = true
    }

    # Virtual Machine configuration
    virtual_machine {
      delete_os_disk_on_deletion     = true
      graceful_shutdown              = false
      skip_shutdown_and_force_delete = false
    }

    # Virtual Machine Scale Set configuration
    virtual_machine_scale_set {
      roll_instances_when_required = true
    }

    # Log Analytics Workspace configuration
    log_analytics_workspace {
      permanently_delete_on_destroy = true
    }

    # Application Insights configuration
    application_insights {
      disable_generated_rule = false
    }

    # API Management configuration
    api_management {
      purge_soft_delete_on_destroy = true
      recover_soft_deleted         = true
    }

    # Machine Learning configuration
    machine_learning {
      purge_soft_deleted_workspace_on_destroy = true
    }

    # Managed Disk configuration
    managed_disk {
      expand_without_downtime = true
    }

    # PostgreSQL configuration
    postgresql_flexible_server {
      restart_server_on_configuration_value_change = true
    }

    # Recovery Services Vault configuration
    recovery_services_vault {
      purge_protected_items_from_vault_on_destroy = true
    }

    # Subscription configuration
    subscription {
      prevent_cancellation_on_destroy = false
    }
  }

  # Optional: Configure specific subscription, client, tenant, or environment
  # subscription_id = var.subscription_id
  # client_id       = var.client_id
  # client_secret   = var.client_secret
  # tenant_id       = var.tenant_id
  
  # Optional: Configure Azure environment (default is public)
  # environment = "public"  # Options: public, usgovernment, china, germany

  # Optional: Configure additional features
  # skip_provider_registration = false
  # disable_correlation_request_id = false
  # disable_terraform_partner_id = false
  
  # Optional: Configure custom metadata
  # metadata_host = "metadata.azure.com"
  # msi_endpoint  = "http://169.254.169.254/metadata/identity/oauth2/token"
  
  # Optional: Configure partner ID for usage attribution
  # partner_id = "your-partner-id"
}

# Configure the Azure Active Directory Provider
provider "azuread" {
  # Optional: Configure specific tenant
  # tenant_id = var.tenant_id
  
  # Optional: Configure client credentials
  # client_id     = var.client_id
  # client_secret = var.client_secret
  
  # Optional: Configure environment
  # environment = "public"  # Options: public, usgovernment, china, germany
  
  # Optional: Configure additional features
  # use_msi                = false
  # use_cli                = true
  # use_oidc               = false
  # disable_terraform_partner_id = false
}

# Configure the Random Provider
provider "random" {
  # Random provider typically doesn't require configuration
}

# Configure the Time Provider
provider "time" {
  # Time provider typically doesn't require configuration
}

# Configure the Null Provider
provider "null" {
  # Null provider typically doesn't require configuration
}

# Configure the Local Provider
provider "local" {
  # Local provider typically doesn't require configuration
}

# Configure the Template Provider
provider "template" {
  # Template provider typically doesn't require configuration
}

# Configure the TLS Provider
provider "tls" {
  # TLS provider typically doesn't require configuration
}

# Configure the HTTP Provider
provider "http" {
  # HTTP provider typically doesn't require configuration
}

# Configure the External Provider
provider "external" {
  # External provider typically doesn't require configuration
}

# ==============================================================================
# PROVIDER VERSION COMPATIBILITY
# ==============================================================================

# Version compatibility matrix:
# - Terraform >= 1.0: Supports all modern provider features
# - AzureRM ~> 3.0: Latest stable version with all Azure services
# - AzureAD ~> 2.0: Latest stable version with Azure AD v2 features
# - Random ~> 3.0: Latest stable version with improved random generation
# - Time ~> 0.9: Latest stable version with comprehensive time functions
# - Null ~> 3.0: Latest stable version with improved null resource handling
# - Local ~> 2.0: Latest stable version with file system operations
# - Template ~> 2.2: Latest stable version with template rendering
# - TLS ~> 4.0: Latest stable version with modern TLS features
# - HTTP ~> 3.0: Latest stable version with HTTP/HTTPS operations
# - External ~> 2.0: Latest stable version with external data sources

# ==============================================================================
# EXPERIMENTAL FEATURES
# ==============================================================================

# Enable experimental features if needed
# terraform {
#   experiments = [
#     # Add experimental features here
#   ]
# }

# ==============================================================================
# CLOUD PROVIDER FEATURE FLAGS
# ==============================================================================

# Configure cloud provider specific features
locals {
  # Feature flags for conditional resource creation
  feature_flags = {
    enable_private_endpoints       = var.enable_private_endpoints
    enable_defender_for_cloud     = var.enable_defender_for_cloud
    enable_policy_compliance      = var.enable_policy_compliance
    enable_resource_locks         = var.enable_resource_locks
    enable_backup                 = var.enable_backup
    enable_geo_backup             = var.enable_geo_backup
    enable_cost_optimization      = var.enable_cost_optimization
    enable_monitoring_alerts      = var.enable_monitoring_alerts
    auto_shutdown_enabled         = var.auto_shutdown_enabled
  }

  # Provider-specific configurations
  azure_features = {
    confidential_ledger_regions = [
      "East US", "West US 2", "North Europe", "West Europe", 
      "Southeast Asia", "UK South", "Australia East"
    ]
    
    cosmos_db_capabilities = [
      "EnableServerless", "EnableTable", "EnableGremlin", 
      "EnableCassandra", "EnableMongo", "EnableMongoDB"
    ]
    
    api_management_skus = [
      "Consumption_0", "Developer_1", "Basic_1", "Basic_2",
      "Standard_1", "Standard_2", "Premium_1", "Premium_2"
    ]
  }
}

# ==============================================================================
# VERSION HISTORY
# ==============================================================================

# Version 1.0.0 - Initial release
# - Basic infrastructure setup
# - Core Azure services configuration
# - Provider version constraints

# Version 1.1.0 - Enhanced features
# - Added monitoring and alerting
# - Improved security configurations
# - Enhanced backup and recovery options

# Version 1.2.0 - Production readiness
# - Added compliance and governance features
# - Enhanced cost optimization
# - Improved error handling and validation

# Version 1.3.0 - Advanced features
# - Added private endpoint support
# - Enhanced networking configurations
# - Improved disaster recovery capabilities

# ==============================================================================
# TERRAFORM UPGRADE NOTES
# ==============================================================================

# When upgrading Terraform versions:
# 1. Review the CHANGELOG for breaking changes
# 2. Update provider versions as needed
# 3. Test in a non-production environment first
# 4. Run 'terraform plan' to check for changes
# 5. Update this file with new version constraints

# When upgrading provider versions:
# 1. Check provider documentation for breaking changes
# 2. Update resource configurations as needed
# 3. Test thoroughly in development environment
# 4. Consider using provider version pinning for stability

# ==============================================================================
# MIGRATION NOTES
# ==============================================================================

# For migrations from older versions:
# - Terraform 0.x to 1.x: Review upgrade guide
# - AzureRM 2.x to 3.x: Update deprecated resource attributes
# - AzureAD 1.x to 2.x: Update authentication methods
# - Provider syntax changes: Update resource configurations