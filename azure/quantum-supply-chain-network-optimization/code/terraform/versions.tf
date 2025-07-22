# =============================================================================
# Terraform and Provider Version Requirements
# =============================================================================

terraform {
  required_version = ">= 1.5.0"
  
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.80"
    }
    
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
  }
  
  # Optional: Configure remote state backend
  # Uncomment and configure the backend block below for production deployments
  # backend "azurerm" {
  #   resource_group_name   = "terraform-state-rg"
  #   storage_account_name  = "terraformstatestorage"
  #   container_name        = "terraform-state"
  #   key                   = "quantum-supply-chain-optimization.tfstate"
  # }
}

# =============================================================================
# Azure Provider Configuration
# =============================================================================

provider "azurerm" {
  features {
    # Configure provider features based on your requirements
    
    # Resource Group features
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    
    # Key Vault features
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
    
    # Storage Account features
    storage {
      prevent_deletion_if_contains_resources = false
    }
    
    # Cosmos DB features
    cosmos_db {
      prevent_deletion_if_contains_resources = false
    }
    
    # Application Insights features
    application_insights {
      disable_generated_rule = false
    }
    
    # Log Analytics features
    log_analytics_workspace {
      permanently_delete_on_destroy = true
    }
    
    # Template Deployment features
    template_deployment {
      delete_nested_items_during_deletion = true
    }
  }
  
  # Optional: Configure specific subscription, tenant, and client details
  # These can also be set via environment variables or Azure CLI authentication
  # subscription_id = var.subscription_id
  # tenant_id       = var.tenant_id
  # client_id       = var.client_id
  # client_secret   = var.client_secret
  
  # Skip provider registration for faster deployment (optional)
  # skip_provider_registration = true
}

# =============================================================================
# Random Provider Configuration
# =============================================================================

provider "random" {
  # No specific configuration required for random provider
}

# =============================================================================
# Time Provider Configuration
# =============================================================================

provider "time" {
  # No specific configuration required for time provider
}

# =============================================================================
# Provider Version Notes
# =============================================================================

# AzureRM Provider Version Notes:
# - Version 3.80+ includes support for Azure Quantum workspaces
# - Version 3.80+ includes improved Digital Twins support
# - Version 3.80+ includes enhanced Function App configurations
# - Version 3.80+ includes Stream Analytics job improvements
# - Version 3.80+ includes Cosmos DB serverless support
# - Version 3.80+ includes Application Insights connection strings
# - Version 3.80+ includes Log Analytics workspace improvements

# Random Provider Version Notes:
# - Version 3.6+ includes improved random_id resource
# - Version 3.6+ includes enhanced random string generation
# - Version 3.6+ includes better state management for random resources

# Time Provider Version Notes:
# - Version 0.9+ includes time_sleep resource for delays
# - Version 0.9+ includes time_offset resource for time calculations
# - Version 0.9+ includes improved time-based resource management

# =============================================================================
# Terraform Version Requirements Explanation
# =============================================================================

# Terraform 1.5.0+ is required for:
# - Enhanced variable validation
# - Improved configuration language features
# - Better error handling and debugging
# - Enhanced provider management
# - Improved state management capabilities
# - Better support for complex data structures
# - Enhanced module system capabilities

# =============================================================================
# Azure CLI Version Requirements
# =============================================================================

# This Terraform configuration requires Azure CLI version 2.45.0 or later
# for full compatibility with Azure Quantum and Digital Twins services.
# 
# To check your Azure CLI version:
# az --version
# 
# To upgrade Azure CLI:
# az upgrade
# 
# To install Azure CLI extensions (if needed):
# az extension add --name quantum
# az extension add --name digitaltwins

# =============================================================================
# Authentication Requirements
# =============================================================================

# This configuration supports multiple authentication methods:
# 
# 1. Azure CLI Authentication (Recommended for development):
#    az login
#    az account set --subscription "your-subscription-id"
# 
# 2. Service Principal Authentication:
#    Set environment variables:
#    - ARM_CLIENT_ID
#    - ARM_CLIENT_SECRET
#    - ARM_SUBSCRIPTION_ID
#    - ARM_TENANT_ID
# 
# 3. Managed Identity Authentication (for Azure VMs):
#    No additional configuration required when running on Azure VMs
#    with managed identity enabled
# 
# 4. Azure DevOps Service Connection:
#    Configure service connection in Azure DevOps pipelines

# =============================================================================
# Permissions Requirements
# =============================================================================

# The executing principal (user, service principal, or managed identity) 
# must have the following Azure RBAC roles or equivalent permissions:
# 
# - Contributor or Owner on the subscription/resource group
# - Quantum Workspace Contributor (for Azure Quantum resources)
# - Digital Twins Data Owner (for Azure Digital Twins resources)
# - Storage Account Contributor (for storage resources)
# - Cosmos DB Account Contributor (for Cosmos DB resources)
# - Event Hub Data Owner (for Event Hub resources)
# - Stream Analytics Contributor (for Stream Analytics resources)
# - Application Insights Contributor (for monitoring resources)
# - Log Analytics Contributor (for Log Analytics resources)

# =============================================================================
# Feature Flags and Experimental Features
# =============================================================================

# Some Azure services used in this configuration may be in preview
# or require feature flags to be enabled:
# 
# 1. Azure Quantum workspace features:
#    - Quantum computing providers may require registration
#    - Some optimization algorithms may be in preview
# 
# 2. Azure Digital Twins features:
#    - Advanced query capabilities may require feature flags
#    - Some integration features may be in preview
# 
# 3. Azure Functions features:
#    - Python 3.11 support may require feature flags
#    - Some integration features may be in preview
# 
# To check available features:
# az feature list --namespace Microsoft.Quantum
# az feature list --namespace Microsoft.DigitalTwins
# az feature list --namespace Microsoft.Web

# =============================================================================
# Regional Availability
# =============================================================================

# Not all Azure services are available in all regions. 
# The following services have limited regional availability:
# 
# - Azure Quantum: Available in East US, West US, North Europe, West Europe
# - Azure Digital Twins: Available in most regions
# - Azure Functions: Available in all regions
# - Azure Cosmos DB: Available in all regions
# - Azure Event Hubs: Available in all regions
# - Azure Stream Analytics: Available in all regions
# 
# Please verify service availability in your target region before deployment.

# =============================================================================
# Cost Considerations
# =============================================================================

# This configuration deploys services with cost implications:
# 
# - Azure Quantum: Pay-per-use pricing for quantum computing resources
# - Azure Digital Twins: Based on API operations and data transfer
# - Azure Functions: Consumption plan (pay-per-execution)
# - Azure Cosmos DB: Serverless pricing model
# - Azure Event Hubs: Standard tier pricing
# - Azure Stream Analytics: Pay-per-streaming-unit
# - Azure Application Insights: Pay-per-data-ingestion
# - Azure Log Analytics: Pay-per-data-ingestion
# 
# Review Azure pricing calculator for accurate cost estimates:
# https://azure.microsoft.com/en-us/pricing/calculator/