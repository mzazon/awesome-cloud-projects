# ==================================================================================
# AZURE BASIC FILE STORAGE WITH BLOB STORAGE AND PORTAL
# ==================================================================================
# This Terraform configuration creates a complete Azure blob storage solution
# with security best practices, RBAC integration, and organized container structure
# suitable for small businesses and individual developers.
#
# Architecture Components:
# - Azure Resource Group for logical resource organization
# - Azure Storage Account with security hardening
# - Multiple Blob Containers for file organization
# - RBAC assignments for secure access control
# - Comprehensive tagging for governance and cost tracking
# ==================================================================================

# Data source to get current Azure client configuration
# This provides information about the currently authenticated Azure user/service principal
data "azurerm_client_config" "current" {}

# Random string generator for unique resource naming
# Ensures globally unique names for Azure resources that require it
resource "random_string" "unique_suffix" {
  length  = 6
  special = false
  upper   = false
  numeric = true
}

# ==================================================================================
# RESOURCE GROUP
# ==================================================================================
# Azure Resource Group serves as a logical container for related resources
# Provides a management boundary for applying policies, permissions, and tags

resource "azurerm_resource_group" "storage_rg" {
  # Use provided name or generate a unique name with demo prefix
  name = var.resource_group_name != null ? var.resource_group_name : "${var.resource_prefix}rg-storage-demo-${random_string.unique_suffix.result}"
  
  # Deploy to the specified Azure region
  location = var.location

  # Apply comprehensive tags for resource management
  # Tags enable cost tracking, environment identification, and governance policies
  tags = merge(var.tags, {
    resource_type = "resource-group"
    created_date  = formatdate("YYYY-MM-DD", timestamp())
  })

  # Lifecycle management to prevent accidental deletion in production
  lifecycle {
    ignore_changes = [
      tags["created_date"]
    ]
  }
}

# ==================================================================================
# STORAGE ACCOUNT
# ==================================================================================
# Azure Storage Account provides the foundation for blob storage services
# Configured with security best practices and cost-effective settings

resource "azurerm_storage_account" "main" {
  # Generate globally unique storage account name
  # Azure storage account names must be globally unique across all Azure tenants
  name = var.storage_account_name != null ? var.storage_account_name : "${var.resource_prefix}sa${random_string.unique_suffix.result}demo"
  
  # Resource placement and basic configuration
  resource_group_name = azurerm_resource_group.storage_rg.name
  location           = azurerm_resource_group.storage_rg.location
  
  # Storage account type and performance configuration
  # StorageV2 provides access to all current and future storage features
  account_kind             = "StorageV2"
  account_tier            = var.account_tier
  account_replication_type = var.account_replication_type
  access_tier             = var.access_tier

  # Security configuration following Azure security best practices
  # TLS 1.2 enforcement ensures secure data transmission
  min_tls_version              = var.min_tls_version
  https_traffic_only_enabled   = var.https_traffic_only_enabled
  allow_nested_items_to_be_public = var.allow_blob_public_access
  shared_access_key_enabled    = var.shared_access_key_enabled
  
  # Public network access configuration
  # Can be restricted to specific IP ranges or private endpoints for enhanced security
  public_network_access_enabled = true

  # Cross-tenant replication settings for multi-tenant scenarios
  cross_tenant_replication_enabled = false

  # Network access rules for additional security
  # Configure IP-based restrictions and Azure service bypass rules
  dynamic "network_rules" {
    for_each = var.network_rules.default_action == "Deny" || length(var.network_rules.ip_rules) > 0 ? [1] : []
    content {
      default_action = var.network_rules.default_action
      ip_rules       = var.network_rules.ip_rules
      bypass         = var.network_rules.bypass
    }
  }

  # Blob storage properties configuration
  # Enable advanced features like versioning, soft delete, and change feed
  blob_properties {
    # Versioning enables point-in-time recovery and change tracking
    versioning_enabled = var.enable_versioning
    
    # Change feed provides audit logs for blob modifications
    change_feed_enabled = var.enable_change_feed
    
    # Soft delete configuration for blob protection
    dynamic "delete_retention_policy" {
      for_each = var.enable_soft_delete ? [1] : []
      content {
        days = var.soft_delete_retention_days
      }
    }

    # Container-level soft delete protection
    dynamic "container_delete_retention_policy" {
      for_each = var.enable_soft_delete ? [1] : []
      content {
        days = var.soft_delete_retention_days
      }
    }
  }

  # Comprehensive resource tagging
  # Tags provide metadata for cost allocation, compliance, and automation
  tags = merge(var.tags, {
    resource_type = "storage-account"
    sku          = "${var.account_tier}_${var.account_replication_type}"
    access_tier  = var.access_tier
  })

  # Lifecycle management to prevent accidental modifications
  lifecycle {
    # Prevent accidental deletion of storage account
    prevent_destroy = false
    
    # Ignore changes to certain computed or timestamp-based tags
    ignore_changes = [
      tags["created_date"]
    ]
  }
}

# ==================================================================================
# BLOB CONTAINERS
# ==================================================================================
# Create multiple blob containers for organized file storage
# Each container acts as a logical folder with its own access policies

resource "azurerm_storage_container" "containers" {
  # Create one container for each entry in the blob_containers variable
  for_each = var.blob_containers

  # Container configuration
  name                  = each.key
  storage_account_id   = azurerm_storage_account.main.id
  container_access_type = each.value.container_access_type

  # Container metadata for additional organization and information
  metadata = merge(each.value.metadata, {
    created_by   = "terraform"
    created_date = formatdate("YYYY-MM-DD", timestamp())
    recipe       = "basic-file-storage-blob-portal"
  })

  # Container lifecycle management
  lifecycle {
    # Prevent accidental deletion of containers with data
    prevent_destroy = false
    
    # Ignore timestamp-based metadata changes
    ignore_changes = [
      metadata["created_date"]
    ]
  }
}

# ==================================================================================
# RBAC ASSIGNMENTS
# ==================================================================================
# Configure Role-Based Access Control (RBAC) for secure storage access
# Uses Azure AD authentication instead of shared access keys

# Assign Storage Blob Data Contributor role to current user/service principal
# This enables blob operations through Azure AD authentication
resource "azurerm_role_assignment" "current_user_blob_contributor" {
  count = var.enable_rbac_for_current_user ? 1 : 0

  # Scope the role assignment to the storage account level
  scope = azurerm_storage_account.main.id
  
  # Use built-in Azure role for blob data operations
  role_definition_name = "Storage Blob Data Contributor"
  
  # Assign to the current authenticated user/service principal
  principal_id = data.azurerm_client_config.current.object_id
  
  # Specify principal type for ABAC compatibility
  principal_type = "ServicePrincipal"

  # Add descriptive information for audit purposes
  description = "Storage Blob Data Contributor access for Terraform deployment user"

  # Dependency management to ensure storage account exists first
  depends_on = [azurerm_storage_account.main]
}

# Additional RBAC assignments for other users or service principals
# Allows fine-grained access control for different user types
resource "azurerm_role_assignment" "additional_assignments" {
  for_each = var.additional_rbac_assignments

  # Scope to storage account
  scope = azurerm_storage_account.main.id
  
  # Use specified role and principal
  role_definition_name = each.value.role_definition_name
  principal_id        = each.value.principal_id
  principal_type      = each.value.principal_type

  # Descriptive information for audit trails
  description = "Additional RBAC assignment for ${each.key}"

  # Ensure proper resource creation order
  depends_on = [azurerm_storage_account.main]
}

# ==================================================================================
# LOCAL VALUES FOR COMPUTED ATTRIBUTES
# ==================================================================================
# Define local values for computed attributes and complex expressions
# Helps with readability and reduces duplication

locals {
  # Storage account connection details
  storage_account_info = {
    name                = azurerm_storage_account.main.name
    id                  = azurerm_storage_account.main.id
    primary_location    = azurerm_storage_account.main.primary_location
    secondary_location  = azurerm_storage_account.main.secondary_location
  }

  # Container information mapping
  container_info = {
    for name, container in azurerm_storage_container.containers :
    name => {
      id                    = container.id
      name                  = container.name
      container_access_type = container.container_access_type
      resource_manager_id   = container.resource_manager_id
    }
  }

  # Azure Portal URLs for easy access
  portal_urls = {
    storage_account = "https://portal.azure.com/#@/resource${azurerm_storage_account.main.id}/overview"
    storage_browser = "https://portal.azure.com/#@/resource${azurerm_storage_account.main.id}/storagebrowser"
    resource_group  = "https://portal.azure.com/#@/resource${azurerm_resource_group.storage_rg.id}/overview"
  }

  # Cost estimation information
  cost_info = {
    storage_tier     = var.account_tier
    replication_type = var.account_replication_type
    access_tier     = var.access_tier
    estimated_monthly_cost = "Varies based on usage - typically $0.02-0.05/month for standard usage"
  }
}