# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Current client configuration
data "azurerm_client_config" "current" {}

# =============================================
# PROVIDER TENANT RESOURCES
# =============================================

# Provider resource group
resource "azurerm_resource_group" "provider" {
  name     = "rg-${var.project_name}-provider-${var.environment}"
  location = var.location

  tags = merge(var.tags, {
    Role = "Provider"
    Type = "ResourceGroup"
  })
}

# Provider storage account for data sharing
resource "azurerm_storage_account" "provider" {
  name                     = "st${var.project_name}prov${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.provider.name
  location                 = azurerm_resource_group.provider.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_replication_type
  account_kind             = "StorageV2"
  
  # Enable Data Lake Storage Gen2 for hierarchical namespace
  is_hns_enabled = var.enable_hierarchical_namespace
  
  # Security configurations
  min_tls_version                = "TLS1_2"
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = true
  
  # Enable soft delete and versioning
  blob_properties {
    versioning_enabled  = var.enable_versioning
    last_access_time_enabled = true
    
    delete_retention_policy {
      days = var.soft_delete_retention_days
    }
    
    container_delete_retention_policy {
      days = var.soft_delete_retention_days
    }
  }

  tags = merge(var.tags, {
    Role = "Provider"
    Type = "StorageAccount"
  })
}

# Provider storage container for shared datasets
resource "azurerm_storage_container" "provider_shared_datasets" {
  name                  = "shared-datasets"
  storage_account_name  = azurerm_storage_account.provider.name
  container_access_type = "private"
}

# Provider Data Share account
resource "azurerm_data_share_account" "provider" {
  name                = "ds-${var.project_name}-provider-${random_string.suffix.result}"
  location            = azurerm_resource_group.provider.location
  resource_group_name = azurerm_resource_group.provider.name

  # Configure managed identity for cross-tenant access
  identity {
    type = "SystemAssigned"
  }

  tags = merge(var.tags, {
    Role = "Provider"
    Type = "DataShareAccount"
  })
}

# Provider Purview account
resource "azurerm_purview_account" "provider" {
  name                = "purview-${var.project_name}-prov-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.provider.name
  location            = azurerm_resource_group.provider.location
  
  # Configure managed identity
  identity {
    type = "SystemAssigned"
  }
  
  # Managed resource group for Purview
  managed_resource_group_name = var.purview_managed_resource_group_name != null ? var.purview_managed_resource_group_name : "rg-${var.project_name}-purview-managed-${random_string.suffix.result}"

  tags = merge(var.tags, {
    Role = "Provider"
    Type = "PurviewAccount"
  })
}

# =============================================
# CONSUMER TENANT RESOURCES
# =============================================

# Consumer resource group
resource "azurerm_resource_group" "consumer" {
  name     = "rg-${var.project_name}-consumer-${var.environment}"
  location = var.location

  tags = merge(var.tags, {
    Role = "Consumer"
    Type = "ResourceGroup"
  })
}

# Consumer storage account for receiving shared data
resource "azurerm_storage_account" "consumer" {
  name                     = "st${var.project_name}cons${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.consumer.name
  location                 = azurerm_resource_group.consumer.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_replication_type
  account_kind             = "StorageV2"
  
  # Enable Data Lake Storage Gen2 for hierarchical namespace
  is_hns_enabled = var.enable_hierarchical_namespace
  
  # Security configurations
  min_tls_version                = "TLS1_2"
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = true
  
  # Enable soft delete and versioning
  blob_properties {
    versioning_enabled  = var.enable_versioning
    last_access_time_enabled = true
    
    delete_retention_policy {
      days = var.soft_delete_retention_days
    }
    
    container_delete_retention_policy {
      days = var.soft_delete_retention_days
    }
  }

  tags = merge(var.tags, {
    Role = "Consumer"
    Type = "StorageAccount"
  })
}

# Consumer Data Share account
resource "azurerm_data_share_account" "consumer" {
  name                = "ds-${var.project_name}-consumer-${random_string.suffix.result}"
  location            = azurerm_resource_group.consumer.location
  resource_group_name = azurerm_resource_group.consumer.name

  # Configure managed identity for cross-tenant access
  identity {
    type = "SystemAssigned"
  }

  tags = merge(var.tags, {
    Role = "Consumer"
    Type = "DataShareAccount"
  })
}

# Consumer Purview account
resource "azurerm_purview_account" "consumer" {
  name                = "purview-${var.project_name}-cons-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.consumer.name
  location            = azurerm_resource_group.consumer.location
  
  # Configure managed identity
  identity {
    type = "SystemAssigned"
  }
  
  # Managed resource group for Purview
  managed_resource_group_name = var.purview_managed_resource_group_name != null ? "${var.purview_managed_resource_group_name}-consumer" : "rg-${var.project_name}-purview-managed-consumer-${random_string.suffix.result}"

  tags = merge(var.tags, {
    Role = "Consumer"
    Type = "PurviewAccount"
  })
}

# =============================================
# DATA SHARE CONFIGURATION
# =============================================

# Create data share in provider account
resource "azurerm_data_share" "main" {
  name       = var.data_share_name
  account_id = azurerm_data_share_account.provider.id
  kind       = "CopyBased"
  
  description = var.data_share_description
  terms      = var.data_share_terms

  depends_on = [
    azurerm_data_share_account.provider
  ]
}

# Create dataset in the share pointing to blob container
resource "azurerm_data_share_dataset_blob_storage" "main" {
  name               = "shared-container-dataset"
  data_share_id      = azurerm_data_share.main.id
  container_name     = azurerm_storage_container.provider_shared_datasets.name
  storage_account_id = azurerm_storage_account.provider.id
  file_path          = null # Share entire container
  folder_path        = null # Share entire container

  depends_on = [
    azurerm_data_share.main,
    azurerm_storage_container.provider_shared_datasets
  ]
}

# =============================================
# IAM ROLE ASSIGNMENTS
# =============================================

# Grant provider Purview managed identity access to provider storage
resource "azurerm_role_assignment" "provider_purview_storage" {
  scope                = azurerm_storage_account.provider.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = azurerm_purview_account.provider.identity[0].principal_id
}

# Grant consumer Purview managed identity access to consumer storage
resource "azurerm_role_assignment" "consumer_purview_storage" {
  scope                = azurerm_storage_account.consumer.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = azurerm_purview_account.consumer.identity[0].principal_id
}

# Grant Data Share provider managed identity access to provider storage
resource "azurerm_role_assignment" "provider_datashare_storage" {
  scope                = azurerm_storage_account.provider.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = azurerm_data_share_account.provider.identity[0].principal_id
}

# Grant Data Share consumer managed identity access to consumer storage
resource "azurerm_role_assignment" "consumer_datashare_storage" {
  scope                = azurerm_storage_account.consumer.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_data_share_account.consumer.identity[0].principal_id
}

# =============================================
# NETWORKING (OPTIONAL PRIVATE ENDPOINTS)
# =============================================

# Virtual network for private endpoints (if enabled)
resource "azurerm_virtual_network" "main" {
  count               = var.enable_private_endpoints ? 1 : 0
  name                = "vnet-${var.project_name}-${var.environment}"
  location            = azurerm_resource_group.provider.location
  resource_group_name = azurerm_resource_group.provider.name
  address_space       = var.virtual_network_address_space

  tags = merge(var.tags, {
    Type = "VirtualNetwork"
  })
}

# Subnet for storage private endpoints
resource "azurerm_subnet" "storage" {
  count                = var.enable_private_endpoints ? 1 : 0
  name                 = "snet-storage"
  resource_group_name  = azurerm_resource_group.provider.name
  virtual_network_name = azurerm_virtual_network.main[0].name
  address_prefixes     = [var.subnet_address_prefixes["storage"]]

  private_endpoint_network_policies_enabled = false
}

# Subnet for Purview private endpoints
resource "azurerm_subnet" "purview" {
  count                = var.enable_private_endpoints ? 1 : 0
  name                 = "snet-purview"
  resource_group_name  = azurerm_resource_group.provider.name
  virtual_network_name = azurerm_virtual_network.main[0].name
  address_prefixes     = [var.subnet_address_prefixes["purview"]]

  private_endpoint_network_policies_enabled = false
}

# =============================================
# MONITORING AND DIAGNOSTICS
# =============================================

# Log Analytics workspace for diagnostic logs (if enabled)
resource "azurerm_log_analytics_workspace" "main" {
  count               = var.enable_diagnostic_settings && var.log_analytics_workspace_id == null ? 1 : 0
  name                = "law-${var.project_name}-${var.environment}"
  location            = azurerm_resource_group.provider.location
  resource_group_name = azurerm_resource_group.provider.name
  sku                 = "PerGB2018"
  retention_in_days   = 30

  tags = merge(var.tags, {
    Type = "LogAnalyticsWorkspace"
  })
}

# Diagnostic settings for provider storage account
resource "azurerm_monitor_diagnostic_setting" "provider_storage" {
  count                      = var.enable_diagnostic_settings ? 1 : 0
  name                       = "diag-${azurerm_storage_account.provider.name}"
  target_resource_id         = azurerm_storage_account.provider.id
  log_analytics_workspace_id = var.log_analytics_workspace_id != null ? var.log_analytics_workspace_id : azurerm_log_analytics_workspace.main[0].id

  enabled_log {
    category = "StorageRead"
  }

  enabled_log {
    category = "StorageWrite"
  }

  enabled_log {
    category = "StorageDelete"
  }

  metric {
    category = "Transaction"
    enabled  = true
  }

  metric {
    category = "Capacity"
    enabled  = true
  }
}

# Diagnostic settings for consumer storage account
resource "azurerm_monitor_diagnostic_setting" "consumer_storage" {
  count                      = var.enable_diagnostic_settings ? 1 : 0
  name                       = "diag-${azurerm_storage_account.consumer.name}"
  target_resource_id         = azurerm_storage_account.consumer.id
  log_analytics_workspace_id = var.log_analytics_workspace_id != null ? var.log_analytics_workspace_id : azurerm_log_analytics_workspace.main[0].id

  enabled_log {
    category = "StorageRead"
  }

  enabled_log {
    category = "StorageWrite"
  }

  enabled_log {
    category = "StorageDelete"
  }

  metric {
    category = "Transaction"
    enabled  = true
  }

  metric {
    category = "Capacity"
    enabled  = true
  }
}

# =============================================
# SAMPLE DATA (OPTIONAL)
# =============================================

# Sample blob for testing data sharing
resource "azurerm_storage_blob" "sample_data" {
  name                   = "sample-dataset.csv"
  storage_account_name   = azurerm_storage_account.provider.name
  storage_container_name = azurerm_storage_container.provider_shared_datasets.name
  type                   = "Block"
  source_content         = "id,name,value\n1,Sample Record 1,100\n2,Sample Record 2,200\n3,Sample Record 3,300"
  content_type           = "text/csv"
}