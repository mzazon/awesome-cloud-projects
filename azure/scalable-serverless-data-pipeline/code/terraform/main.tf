# Main Terraform configuration for Azure Serverless Data Pipeline

# Get current client configuration for Key Vault access policies
data "azurerm_client_config" "current" {}

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Create Resource Group
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

# Create Storage Account with Data Lake Gen2 capabilities
resource "azurerm_storage_account" "data_lake" {
  name                     = "st${var.project_name}${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_account_replication_type
  account_kind             = "StorageV2"
  is_hns_enabled           = true  # Enable hierarchical namespace for Data Lake Gen2
  
  # Enable HTTPS traffic only for security
  enable_https_traffic_only = true
  
  # Enable blob encryption
  blob_properties {
    delete_retention_policy {
      days = 7
    }
    container_delete_retention_policy {
      days = 7
    }
  }
  
  tags = var.tags
}

# Create Data Lake containers for medallion architecture
resource "azurerm_storage_data_lake_gen2_filesystem" "containers" {
  for_each           = toset(var.data_lake_containers)
  name               = each.value
  storage_account_id = azurerm_storage_account.data_lake.id
}

# Create directories within raw container for organized data structure
resource "azurerm_storage_data_lake_gen2_path" "streaming_data" {
  path               = "streaming-data"
  filesystem_name    = azurerm_storage_data_lake_gen2_filesystem.containers["raw"].name
  storage_account_id = azurerm_storage_account.data_lake.id
  resource           = "directory"
}

# Create Azure Key Vault for secure credential management
resource "azurerm_key_vault" "main" {
  name                = "kv-${var.project_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  
  # Use Standard SKU for cost optimization
  sku_name = "standard"
  
  # Enable soft delete and purge protection
  soft_delete_retention_days = var.key_vault_retention_days
  purge_protection_enabled   = false  # Set to true for production
  
  # Access policies for current user/service principal
  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id
    
    secret_permissions = [
      "Get",
      "List",
      "Set",
      "Delete",
      "Purge"
    ]
  }
  
  tags = var.tags
}

# Store storage account connection string in Key Vault
resource "azurerm_key_vault_secret" "storage_connection_string" {
  name         = "storage-connection-string"
  value        = azurerm_storage_account.data_lake.primary_connection_string
  key_vault_id = azurerm_key_vault.main.id
  
  depends_on = [azurerm_key_vault.main]
}

# Create Azure Synapse Analytics Workspace
resource "azurerm_synapse_workspace" "main" {
  name                = "syn-${var.project_name}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  
  # Storage configuration for Synapse workspace
  storage_data_lake_gen2_filesystem_id = azurerm_storage_data_lake_gen2_filesystem.containers["raw"].id
  
  # SQL administrator credentials
  sql_administrator_login          = var.synapse_sql_admin_login
  sql_administrator_login_password = var.synapse_sql_admin_password
  
  # Enable managed virtual network for security
  managed_virtual_network_enabled = true
  
  # Configure identity for Key Vault access
  identity {
    type = "SystemAssigned"
  }
  
  tags = var.tags
}

# Create Synapse firewall rules if enabled
resource "azurerm_synapse_firewall_rule" "firewall_rules" {
  count = var.enable_firewall_rules ? length(var.allowed_ip_ranges) : 0
  
  name                 = var.allowed_ip_ranges[count.index].name
  synapse_workspace_id = azurerm_synapse_workspace.main.id
  start_ip_address     = var.allowed_ip_ranges[count.index].start_ip
  end_ip_address       = var.allowed_ip_ranges[count.index].end_ip
}

# Grant Key Vault access to Synapse managed identity
resource "azurerm_key_vault_access_policy" "synapse_key_vault_access" {
  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = azurerm_synapse_workspace.main.identity[0].tenant_id
  object_id    = azurerm_synapse_workspace.main.identity[0].principal_id
  
  secret_permissions = [
    "Get",
    "List"
  ]
}

# Create Azure Data Factory
resource "azurerm_data_factory" "main" {
  name                = "adf-${var.project_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  # Enable managed identity
  identity {
    type = "SystemAssigned"
  }
  
  tags = var.tags
}

# Grant Key Vault access to Data Factory managed identity
resource "azurerm_key_vault_access_policy" "data_factory_key_vault_access" {
  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = azurerm_data_factory.main.identity[0].tenant_id
  object_id    = azurerm_data_factory.main.identity[0].principal_id
  
  secret_permissions = [
    "Get",
    "List"
  ]
}

# Create Data Factory Linked Service for Key Vault
resource "azurerm_data_factory_linked_service_key_vault" "key_vault" {
  name            = "ls_keyvault"
  data_factory_id = azurerm_data_factory.main.id
  key_vault_id    = azurerm_key_vault.main.id
  
  depends_on = [azurerm_key_vault_access_policy.data_factory_key_vault_access]
}

# Create Data Factory Linked Service for Azure Data Lake Storage
resource "azurerm_data_factory_linked_service_data_lake_storage_gen2" "storage" {
  name            = "ls_storage"
  data_factory_id = azurerm_data_factory.main.id
  url             = azurerm_storage_account.data_lake.primary_dfs_endpoint
  
  # Use Key Vault for secure credential management
  service_principal_linked_key_vault_key {
    linked_service_name = azurerm_data_factory_linked_service_key_vault.key_vault.name
    secret_name         = azurerm_key_vault_secret.storage_connection_string.name
  }
  
  depends_on = [azurerm_data_factory_linked_service_key_vault.key_vault]
}

# Create Data Factory Dataset for JSON source data
resource "azurerm_data_factory_dataset_json" "streaming_source" {
  name            = "ds_streaming_source"
  data_factory_id = azurerm_data_factory.main.id
  linked_service_name = azurerm_data_factory_linked_service_data_lake_storage_gen2.storage.name
  
  azure_blob_fs_location {
    file_system  = "raw"
    path         = "streaming-data"
  }
}

# Create Data Factory Dataset for Parquet sink data
resource "azurerm_data_factory_dataset_parquet" "curated_sink" {
  name            = "ds_curated_sink"
  data_factory_id = azurerm_data_factory.main.id
  linked_service_name = azurerm_data_factory_linked_service_data_lake_storage_gen2.storage.name
  
  azure_blob_fs_location {
    file_system  = "curated"
    path         = "processed-data"
  }
}

# Create Log Analytics Workspace for monitoring if enabled
resource "azurerm_log_analytics_workspace" "main" {
  count               = var.enable_monitoring ? 1 : 0
  name                = "law-${var.project_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  
  tags = var.tags
}

# Create diagnostic settings for Data Factory monitoring
resource "azurerm_monitor_diagnostic_setting" "data_factory" {
  count                      = var.enable_monitoring ? 1 : 0
  name                       = "adf-diagnostics"
  target_resource_id         = azurerm_data_factory.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main[0].id
  
  enabled_log {
    category_group = "allLogs"
    
    retention_policy {
      enabled = true
      days    = 30
    }
  }
  
  metric {
    category = "AllMetrics"
    enabled  = true
    
    retention_policy {
      enabled = true
      days    = 30
    }
  }
}

# Create diagnostic settings for Synapse workspace monitoring
resource "azurerm_monitor_diagnostic_setting" "synapse" {
  count                      = var.enable_monitoring ? 1 : 0
  name                       = "synapse-diagnostics"
  target_resource_id         = azurerm_synapse_workspace.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main[0].id
  
  enabled_log {
    category_group = "allLogs"
    
    retention_policy {
      enabled = true
      days    = 30
    }
  }
  
  metric {
    category = "AllMetrics"
    enabled  = true
    
    retention_policy {
      enabled = true
      days    = 30
    }
  }
}

# Create action group for alerting if monitoring is enabled
resource "azurerm_monitor_action_group" "pipeline_alerts" {
  count               = var.enable_monitoring ? 1 : 0
  name                = "pipeline-alerts"
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "pipelinealert"
  
  # Add email receiver (customize as needed)
  email_receiver {
    name          = "admin"
    email_address = "admin@example.com"
  }
  
  tags = var.tags
}

# Create metric alert for Data Factory pipeline failures
resource "azurerm_monitor_metric_alert" "pipeline_failure" {
  count               = var.enable_monitoring ? 1 : 0
  name                = "pipeline-failure-alert"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_data_factory.main.id]
  description         = "Alert when Data Factory pipeline fails"
  
  criteria {
    metric_namespace = "Microsoft.DataFactory/factories"
    metric_name      = "PipelineFailedRuns"
    aggregation      = "Count"
    operator         = "GreaterThan"
    threshold        = 0
  }
  
  action {
    action_group_id = azurerm_monitor_action_group.pipeline_alerts[0].id
  }
  
  tags = var.tags
}

# Grant Storage Blob Data Contributor role to Data Factory on storage account
resource "azurerm_role_assignment" "data_factory_storage_contributor" {
  scope                = azurerm_storage_account.data_lake.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_data_factory.main.identity[0].principal_id
}

# Grant Storage Blob Data Reader role to Synapse on storage account
resource "azurerm_role_assignment" "synapse_storage_reader" {
  scope                = azurerm_storage_account.data_lake.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = azurerm_synapse_workspace.main.identity[0].principal_id
}