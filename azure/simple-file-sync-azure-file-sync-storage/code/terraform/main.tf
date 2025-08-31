# Azure File Sync Infrastructure Deployment
# This configuration creates a complete Azure File Sync solution including:
# - Resource Group
# - Storage Account with Azure Files
# - Azure File Share
# - Storage Sync Service
# - Sync Group and Cloud Endpoint
# - Sample files for demonstration

# Generate random suffix for globally unique resource names
resource "random_string" "suffix" {
  count   = var.use_random_suffix ? 1 : 0
  length  = var.random_suffix_length
  special = false
  upper   = false
  numeric = true
}

# Local values for resource naming and configuration
locals {
  # Generate unique suffix
  random_suffix = var.use_random_suffix ? random_string.suffix[0].result : ""
  
  # Resource names with optional random suffix
  resource_group_name         = var.resource_group_name != null ? var.resource_group_name : "rg-filesync-${local.random_suffix}"
  storage_account_name        = var.storage_account_name != null ? "${var.storage_account_name}${local.random_suffix}" : "filesync${local.random_suffix}"
  storage_sync_service_name   = var.storage_sync_service_name != null ? "${var.storage_sync_service_name}-${local.random_suffix}" : "filesync-service-${local.random_suffix}"
  cloud_endpoint_name         = var.cloud_endpoint_name != null ? "${var.cloud_endpoint_name}-${local.random_suffix}" : "cloud-endpoint-${local.random_suffix}"
  
  # Combined tags
  common_tags = merge(var.common_tags, var.additional_tags, {
    "Created-By"    = "Terraform"
    "Creation-Date" = formatdate("YYYY-MM-DD", timestamp())
  })
  
  # Sample files with timestamp
  sample_files_with_timestamp = var.create_sample_files ? {
    for key, file in var.sample_files : key => {
      content = replace(file.content, "timestamp placeholder", formatdate("YYYY-MM-DD hh:mm:ss", timestamp()))
      path    = file.path
    }
  } : {}
}

# Azure Resource Group
# Container for all Azure File Sync resources
resource "azurerm_resource_group" "filesync" {
  name     = local.resource_group_name
  location = var.location
  
  tags = local.common_tags
}

# Azure Storage Account
# Provides the foundation for Azure Files and File Sync
resource "azurerm_storage_account" "filesync" {
  name                = local.storage_account_name
  resource_group_name = azurerm_resource_group.filesync.name
  location            = azurerm_resource_group.filesync.location
  
  # Storage configuration
  account_tier              = var.storage_account_tier
  account_replication_type  = var.storage_account_replication_type
  account_kind              = "StorageV2"
  
  # Security and access configuration
  https_traffic_only_enabled       = var.enable_https_traffic_only
  min_tls_version                  = var.min_tls_version
  allow_nested_items_to_be_public  = var.allow_nested_items_to_be_public
  shared_access_key_enabled        = true # Required for Azure File Sync
  
  # Advanced features
  large_file_share_enabled = var.enable_large_file_share
  
  # Network access configuration
  network_rules {
    default_action = "Allow"
    bypass         = ["AzureServices"]
  }
  
  # Cross-tenant replication settings
  cross_tenant_replication_enabled = false
  allowed_copy_scope               = var.allowed_copy_scope
  
  tags = merge(local.common_tags, {
    "Resource-Type" = "Storage Account"
    "Purpose"       = "Azure File Sync Backend"
  })
  
  depends_on = [azurerm_resource_group.filesync]
}

# Azure File Share
# SMB-compatible file share that serves as the cloud endpoint
resource "azurerm_storage_share" "filesync" {
  name                 = var.file_share_name
  storage_account_name = azurerm_storage_account.filesync.name
  quota                = var.file_share_quota
  access_tier          = var.file_share_access_tier
  
  # Enable snapshot support for backup and recovery
  enabled_protocol = "SMB"
  
  metadata = {
    "created-by" = "terraform"
    "purpose"    = "file-sync-demo"
    "recipe"     = "simple-file-sync-azure-file-sync-storage"
  }
  
  depends_on = [azurerm_storage_account.filesync]
}

# Sample Files for Demonstration
# Create sample files in the Azure file share to demonstrate sync capabilities
resource "azurerm_storage_share_file" "sample_files" {
  for_each = local.sample_files_with_timestamp
  
  name             = each.value.path
  storage_share_id = azurerm_storage_share.filesync.id
  source           = "data:text/plain;base64,${base64encode(each.value.content)}"
  
  metadata = {
    "created-by" = "terraform"
    "file-type"  = "sample"
    "purpose"    = "demonstration"
  }
  
  depends_on = [azurerm_storage_share.filesync]
}

# Azure File Sync Service
# Central orchestration service for hybrid file synchronization
resource "azurerm_storage_sync" "filesync" {
  name                = local.storage_sync_service_name
  resource_group_name = azurerm_resource_group.filesync.name
  location            = azurerm_resource_group.filesync.location
  
  tags = merge(local.common_tags, {
    "Resource-Type" = "Storage Sync Service"
    "Purpose"       = "File Synchronization"
  })
  
  depends_on = [azurerm_resource_group.filesync]
}

# Sync Group
# Defines the synchronization topology and relationships
resource "azurerm_storage_sync_group" "filesync" {
  name            = var.sync_group_name
  storage_sync_id = azurerm_storage_sync.filesync.id
  
  depends_on = [azurerm_storage_sync.filesync]
}

# Cloud Endpoint
# Connects the Azure file share to the sync group
resource "azurerm_storage_sync_cloud_endpoint" "filesync" {
  name                  = local.cloud_endpoint_name
  storage_sync_group_id = azurerm_storage_sync_group.filesync.id
  file_share_name       = azurerm_storage_share.filesync.name
  storage_account_id    = azurerm_storage_account.filesync.id
  
  depends_on = [
    azurerm_storage_sync_group.filesync,
    azurerm_storage_share.filesync
  ]
}

# Create a local data source for current subscription and tenant information
data "azurerm_client_config" "current" {}

# Output resource information for server registration and management
# This information is needed for Azure File Sync agent installation and configuration