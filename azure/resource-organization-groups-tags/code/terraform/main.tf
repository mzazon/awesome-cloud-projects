# Main Terraform configuration for Azure resource organization with resource groups and tags
# This implementation demonstrates best practices for resource organization, tagging strategies,
# and cost management across development, production, and shared environments

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Get current client configuration for subscription ID and tenant ID
data "azurerm_client_config" "current" {}

# Local values for consistent resource naming and tagging
locals {
  # Generate unique suffix for resource names
  resource_suffix = random_id.suffix.hex
  
  # Common naming convention
  resource_group_prefix = "rg-${var.environment_prefix}"
  storage_prefix        = "st"
  app_service_prefix    = "asp"
  
  # Base tags applied to all resource groups and resources
  common_tags = merge({
    purpose       = var.environment_prefix
    project       = var.project_name
    managedBy     = var.managed_by
    lastUpdated   = formatdate("YYYY-MM-DD", timestamp())
    automation    = "enabled"
    subscription  = data.azurerm_client_config.current.subscription_id
  }, var.additional_tags)
  
  # Environment-specific tag configurations
  dev_tags = merge(local.common_tags, {
    environment = "development"
    department  = var.department
    costcenter  = var.cost_center_dev
    owner       = var.owner_dev
  })
  
  prod_tags = merge(local.common_tags, {
    environment    = "production"
    department     = var.department
    costcenter     = var.cost_center_prod
    owner          = var.owner_prod
    sla            = var.enable_production_compliance ? var.sla_tier : null
    backup         = var.enable_production_compliance ? "daily" : null
    compliance     = var.enable_production_compliance ? var.compliance_framework : null
    auditRequired  = var.enable_production_compliance ? "true" : "false"
  })
  
  shared_tags = merge(local.common_tags, {
    environment = "shared"
    department  = "platform"
    costcenter  = var.cost_center_shared
    owner       = var.owner_shared
    scope       = "multi-environment"
  })
}

# Development Environment Resource Group
# This resource group contains all development-related resources with appropriate tagging
# for cost allocation, governance, and operational automation
resource "azurerm_resource_group" "development" {
  name     = "${local.resource_group_prefix}-dev-${local.resource_suffix}"
  location = var.location
  tags     = local.dev_tags
}

# Production Environment Resource Group  
# Production resource group includes enhanced governance tags for compliance,
# monitoring, and operational requirements following enterprise security standards
resource "azurerm_resource_group" "production" {
  name     = "${local.resource_group_prefix}-prod-${local.resource_suffix}"
  location = var.location
  tags     = local.prod_tags
}

# Shared Resources Group
# Contains infrastructure components used across multiple environments,
# optimizing costs by avoiding resource duplication while maintaining clear ownership
resource "azurerm_resource_group" "shared" {
  name     = "${local.resource_group_prefix}-shared-${local.resource_suffix}"
  location = var.location
  tags     = local.shared_tags
}

# Development Environment Storage Account
# Demonstrates resource-specific tagging that complements resource group tags
# for detailed cost allocation and governance automation
resource "azurerm_storage_account" "development" {
  name                     = "${local.storage_prefix}dev${local.resource_suffix}"
  resource_group_name      = azurerm_resource_group.development.name
  location                 = azurerm_resource_group.development.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_replication_type_dev
  account_kind             = "StorageV2"
  
  # Enable secure transfer and disable public access for security
  enable_https_traffic_only = true
  allow_nested_items_to_be_public = false
  
  # Resource-specific tags for operational metadata
  tags = merge(local.dev_tags, {
    tier      = "standard"
    dataclass = "non-sensitive"
    purpose   = "development-storage"
  })
  
  depends_on = [azurerm_resource_group.development]
}

# Production Environment Storage Account
# Production storage includes enhanced security configuration and additional
# tags for compliance, monitoring, and operational requirements
resource "azurerm_storage_account" "production" {
  name                     = "${local.storage_prefix}prod${local.resource_suffix}"
  resource_group_name      = azurerm_resource_group.production.name
  location                 = azurerm_resource_group.production.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_replication_type_prod
  account_kind             = "StorageV2"
  
  # Enhanced security configuration for production
  enable_https_traffic_only = true
  allow_nested_items_to_be_public = false
  min_tls_version = "TLS1_2"
  
  # Enable advanced threat protection for production
  blob_properties {
    delete_retention_policy {
      days = var.backup_retention_days
    }
    container_delete_retention_policy {
      days = var.backup_retention_days
    }
  }
  
  # Production-specific tags with enhanced compliance metadata
  tags = merge(local.prod_tags, {
    tier        = "premium"
    dataclass   = "sensitive"
    encryption  = "enabled"
    backup      = "enabled"
    purpose     = "production-storage"
  })
  
  depends_on = [azurerm_resource_group.production]
}

# Development Environment App Service Plan
# Basic tier App Service Plan for development workloads with cost optimization
resource "azurerm_service_plan" "development" {
  name                = "${local.app_service_prefix}-dev-${local.resource_suffix}"
  resource_group_name = azurerm_resource_group.development.name
  location            = azurerm_resource_group.development.location
  os_type             = "Linux"
  sku_name            = var.app_service_plan_sku_dev
  
  # Development-specific tags for workload identification
  tags = merge(local.dev_tags, {
    tier      = "basic"
    workload  = "web-app"
    purpose   = "development-compute"
  })
  
  depends_on = [azurerm_resource_group.development]
}

# Production Environment App Service Plan
# Premium tier App Service Plan for production workloads with enhanced monitoring
# and performance characteristics required for production environments
resource "azurerm_service_plan" "production" {
  name                = "${local.app_service_prefix}-prod-${local.resource_suffix}" 
  resource_group_name = azurerm_resource_group.production.name
  location            = azurerm_resource_group.production.location
  os_type             = "Linux"
  sku_name            = var.app_service_plan_sku_prod
  
  # Production-specific tags with enhanced operational metadata
  tags = merge(local.prod_tags, {
    tier        = "premium"
    workload    = "web-app"
    monitoring  = "enabled"
    purpose     = "production-compute"
  })
  
  depends_on = [azurerm_resource_group.production]
}

# Shared Virtual Network (Optional - for demonstration)
# Example of shared infrastructure that could be used across environments
# This demonstrates how shared resources are tagged for cost allocation
resource "azurerm_virtual_network" "shared" {
  name                = "vnet-shared-${local.resource_suffix}"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.shared.location
  resource_group_name = azurerm_resource_group.shared.name
  
  # Create subnets for different environments within shared network
  subnet {
    name           = "subnet-dev"
    address_prefix = "10.0.1.0/24"
  }
  
  subnet {
    name           = "subnet-prod"
    address_prefix = "10.0.2.0/24"
  }
  
  subnet {
    name           = "subnet-shared"
    address_prefix = "10.0.3.0/24"
  }
  
  # Shared infrastructure tags for cross-environment cost allocation
  tags = merge(local.shared_tags, {
    resourceType = "networking"
    purpose      = "shared-connectivity"
  })
  
  depends_on = [azurerm_resource_group.shared]
}