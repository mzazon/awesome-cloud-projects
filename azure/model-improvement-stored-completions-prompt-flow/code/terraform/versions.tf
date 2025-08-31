# Version constraints for Model Improvement Pipeline with Stored Completions and Prompt Flow
# This file defines the required Terraform version and provider versions for reproducible deployments

terraform {
  # Minimum Terraform version required for this configuration
  # Uses features available in Terraform 1.0 and later
  required_version = ">= 1.0"

  # Provider version constraints for stability and feature compatibility
  required_providers {
    # Azure Resource Manager provider for managing Azure resources
    # Version 3.80+ includes support for:
    # - Azure OpenAI Service with stored completions
    # - Machine Learning workspace v2 features
    # - Enhanced Function App configuration options
    # - Improved diagnostic settings support
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.80"
    }

    # Random provider for generating unique resource names
    # Version 3.4+ provides enhanced string generation capabilities
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4"
    }
  }

  # Optional: Configure backend for remote state storage
  # Uncomment and configure based on your state management strategy
  
  # Example: Azure Storage backend configuration
  # backend "azurerm" {
  #   resource_group_name  = "terraform-state-rg"
  #   storage_account_name = "terraformstatestorage"
  #   container_name      = "tfstate"
  #   key                 = "model-improvement-pipeline.terraform.tfstate"
  # }

  # Example: Terraform Cloud backend configuration
  # backend "remote" {
  #   organization = "your-organization"
  #   workspaces {
  #     name = "model-improvement-pipeline"
  #   }
  # }

  # Example: S3 backend configuration (for multi-cloud scenarios)
  # backend "s3" {
  #   bucket = "your-terraform-state-bucket"
  #   key    = "azure/model-improvement-pipeline/terraform.tfstate"
  #   region = "us-west-2"
  # }
}

# Provider configuration block (defined in main.tf)
# The azurerm provider configuration includes:
# - Feature flags for resource management behavior
# - Authentication configuration (uses Azure CLI, Managed Service Identity, or Service Principal)
# - Subscription and tenant ID detection

# Note: Provider authentication methods (in order of precedence):
# 1. Service Principal with Client Secret (recommended for CI/CD)
#    - Set ARM_CLIENT_ID, ARM_CLIENT_SECRET, ARM_SUBSCRIPTION_ID, ARM_TENANT_ID
# 2. Service Principal with Client Certificate
#    - Set ARM_CLIENT_ID, ARM_CLIENT_CERTIFICATE_PATH, ARM_SUBSCRIPTION_ID, ARM_TENANT_ID
# 3. Managed Service Identity (for Azure-hosted environments)
#    - Set ARM_USE_MSI=true, ARM_SUBSCRIPTION_ID, ARM_TENANT_ID
# 4. Azure CLI authentication (default for local development)
#    - Run 'az login' before terraform commands

# Version compatibility notes:
# - Terraform 1.0+: Stable configuration language, enhanced state management
# - AzureRM 3.80+: Support for latest Azure services and API versions
# - Random 3.4+: Enhanced random string generation with improved entropy

# Breaking changes to be aware of:
# - AzureRM 4.x (when available): May include breaking changes to resource schemas
# - Terraform 2.x (future): May include language and behavior changes
# - Monitor provider changelogs for deprecation notices

# Upgrade recommendations:
# - Test configuration with new provider versions in non-production environments
# - Review provider changelog before upgrading minor versions
# - Plan for major version upgrades during maintenance windows
# - Use version constraints to prevent unexpected updates in production