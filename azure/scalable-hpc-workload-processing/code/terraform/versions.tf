# Terraform and Provider Version Requirements
# This file specifies the required versions for Terraform and the Azure provider

terraform {
  required_version = ">= 1.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
  }
}

# Configure the Azure Provider
provider "azurerm" {
  features {
    # Enable enhanced features for resource management
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    
    # Storage account features
    storage {
      prevent_deletion_if_contains_resources = false
    }
    
    # Virtual machine features
    virtual_machine {
      delete_os_disk_on_deletion     = true
      graceful_shutdown              = false
      skip_shutdown_and_force_delete = false
    }
    
    # Key vault features for secure key management
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
    
    # Log analytics features
    log_analytics_workspace {
      permanently_delete_on_destroy = true
    }
    
    # Application insights features
    application_insights {
      disable_generated_rule = false
    }
    
    # Cognitive services features
    cognitive_account {
      purge_soft_delete_on_destroy = true
    }
    
    # Template deployment features
    template_deployment {
      delete_nested_items_during_deletion = true
    }
  }
}

# Random provider for generating unique resource names
provider "random" {
  # No specific configuration required
}

# Data sources for current Azure configuration
data "azurerm_client_config" "current" {}

data "azurerm_subscription" "current" {}

# Local values for common configurations
locals {
  # Common tags applied to all resources
  common_tags = {
    Environment   = var.environment
    ManagedBy     = "Terraform"
    Purpose       = "HPC-Workload-Processing"
    CreatedDate   = formatdate("YYYY-MM-DD", timestamp())
    Project       = "Azure-HPC-Elastic-SAN"
    Owner         = "Infrastructure-Team"
    CostCenter    = "HPC-Computing"
    Compliance    = "Internal"
  }
  
  # Resource naming convention
  resource_suffix = var.random_suffix != "" ? var.random_suffix : random_string.suffix.result
  
  # Elastic SAN configuration
  elastic_san_total_capacity = var.elastic_san_base_size_tib + var.elastic_san_extended_capacity_tib
  
  # Batch pool configuration
  batch_pool_auto_scale_enabled = var.enable_auto_scaling
  
  # Monitoring configuration
  monitoring_enabled = var.enable_monitoring
  
  # Diagnostic settings configuration
  diagnostic_settings_enabled = var.enable_diagnostic_settings
}

# Random string for resource name uniqueness
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
  
  keepers = {
    # Generate a new suffix when the resource group name changes
    resource_group_name = var.resource_group_name
  }
}

# Random password for demonstration purposes (use Azure Key Vault in production)
resource "random_password" "hpc_user_password" {
  length  = 16
  special = true
  upper   = true
  lower   = true
  numeric = true
  
  # Ensure at least one character from each class
  min_special = 1
  min_upper   = 1
  min_lower   = 1
  min_numeric = 1
}

# Data source for available Azure regions
data "azurerm_locations" "available" {
  location_filter {
    include_regions = ["East US", "West US 2", "North Europe", "West Europe", "East Asia", "Southeast Asia"]
  }
}

# Data source for available VM sizes in the region
data "azurerm_virtual_machine_sizes" "available" {
  location = var.location
}

# Validation for Elastic SAN availability in the region
# Note: Elastic SAN is available in limited regions
locals {
  elastic_san_supported_regions = [
    "East US",
    "West US 2",
    "North Europe",
    "West Europe",
    "East Asia",
    "Southeast Asia",
    "Australia East",
    "Japan East",
    "UK South",
    "Canada Central",
    "Central US",
    "South Central US",
    "West Central US",
    "East US 2",
    "West US 3",
    "North Central US",
    "South India",
    "West India",
    "Central India",
    "Korea Central",
    "Korea South",
    "Brazil South",
    "France Central",
    "Germany West Central",
    "Switzerland North",
    "UAE North",
    "South Africa North"
  ]
  
  is_elastic_san_supported = contains(local.elastic_san_supported_regions, var.location)
}

# Validation check for Elastic SAN region support
resource "null_resource" "elastic_san_region_check" {
  count = local.is_elastic_san_supported ? 0 : 1
  
  provisioner "local-exec" {
    command = "echo 'WARNING: Azure Elastic SAN may not be available in the selected region: ${var.location}. Please verify region availability.' && exit 1"
  }
}

# Output current configuration for reference
output "terraform_configuration" {
  description = "Current Terraform and provider configuration"
  value = {
    terraform_version = ">=1.0"
    azurerm_version   = "~>3.0"
    random_version    = "~>3.1"
    current_subscription = data.azurerm_subscription.current.subscription_id
    current_tenant       = data.azurerm_client_config.current.tenant_id
    deployment_region    = var.location
    elastic_san_supported = local.is_elastic_san_supported
    resource_suffix      = local.resource_suffix
    common_tags          = local.common_tags
  }
}