# Main Terraform configuration for Azure smart manufacturing digital twins solution
# This file creates a comprehensive IoT ecosystem with Digital Twins, IoT Hub, Time Series Insights, and Machine Learning

# Data sources for current Azure context
data "azurerm_client_config" "current" {}

data "azuread_client_config" "current" {}

# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}

# Local values for resource naming and common configurations
locals {
  # Generate unique suffix based on configuration
  suffix = var.use_random_suffix ? random_string.suffix.result : ""
  
  # Base name for all resources
  base_name = var.resource_prefix != "" ? "${var.resource_prefix}-${var.project_name}" : var.project_name
  
  # Resource names with consistent naming convention
  resource_group_name         = "rg-${local.base_name}-${var.environment}${local.suffix != "" ? "-${local.suffix}" : ""}"
  iot_hub_name               = "iothub-${local.base_name}-${var.environment}${local.suffix != "" ? "-${local.suffix}" : ""}"
  digital_twins_name         = "dt-${local.base_name}-${var.environment}${local.suffix != "" ? "-${local.suffix}" : ""}"
  storage_account_name       = "st${replace("${local.base_name}${var.environment}${local.suffix}", "-", "")}"
  tsi_environment_name       = "tsi-${local.base_name}-${var.environment}${local.suffix != "" ? "-${local.suffix}" : ""}"
  ml_workspace_name          = "mlws-${local.base_name}-${var.environment}${local.suffix != "" ? "-${local.suffix}" : ""}"
  app_insights_name          = "appi-${local.base_name}-${var.environment}${local.suffix != "" ? "-${local.suffix}" : ""}"
  key_vault_name             = "kv-${replace("${local.base_name}-${var.environment}${local.suffix != "" ? "-${local.suffix}" : ""}", "-", "")}"
  log_analytics_name         = "log-${local.base_name}-${var.environment}${local.suffix != "" ? "-${local.suffix}" : ""}"
  
  # Common tags applied to all resources
  common_tags = merge({
    Environment        = var.environment
    Project           = var.project_name
    Purpose           = "smart-manufacturing-digital-twins"
    ManagedBy         = "terraform"
    CreatedDate       = timestamp()
    AutoDelete        = var.auto_delete_resources ? "true" : "false"
    AutoDeleteHours   = var.auto_delete_resources ? tostring(var.auto_delete_hours) : "never"
  }, var.additional_tags)
}

# Resource Group for all manufacturing digital twins resources
resource "azurerm_resource_group" "main" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.common_tags
}

# Log Analytics Workspace for centralized logging and monitoring
resource "azurerm_log_analytics_workspace" "main" {
  name                = local.log_analytics_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  tags                = local.common_tags
}

# Application Insights for application performance monitoring
resource "azurerm_application_insights" "main" {
  name                = local.app_insights_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = "other"
  tags                = local.common_tags
}

# Storage Account for Time Series Insights and general data storage
resource "azurerm_storage_account" "main" {
  name                     = local.storage_account_name
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_account_replication
  account_kind             = "StorageV2"
  
  # Enable Data Lake Storage Gen2 capabilities
  is_hns_enabled = var.enable_hierarchical_namespace
  
  # Enable advanced threat protection
  enable_https_traffic_only = true
  min_tls_version          = "TLS1_2"
  
  # Network security configuration
  public_network_access_enabled = true
  
  # Blob properties for optimal performance
  blob_properties {
    delete_retention_policy {
      days = 7
    }
    container_delete_retention_policy {
      days = 7
    }
    versioning_enabled = true
  }
  
  tags = local.common_tags
}

# Key Vault for secure credential and secret management
resource "azurerm_key_vault" "main" {
  name                = local.key_vault_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"
  
  # Enable advanced security features
  enabled_for_disk_encryption     = true
  enabled_for_deployment          = true
  enabled_for_template_deployment = true
  purge_protection_enabled        = false
  soft_delete_retention_days      = 7
  
  # Network access configuration
  public_network_access_enabled = true
  
  # Access policy for current user/service principal
  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id
    
    secret_permissions = [
      "Get", "Set", "List", "Delete", "Purge", "Recover"
    ]
    
    key_permissions = [
      "Get", "Create", "Delete", "List", "Update", "Import", "Backup", "Restore", "Recover"
    ]
    
    certificate_permissions = [
      "Get", "Create", "Delete", "List", "Update", "Import"
    ]
  }
  
  tags = local.common_tags
}

# IoT Hub for device connectivity and message routing
resource "azurerm_iothub" "main" {
  name                = local.iot_hub_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  
  # SKU configuration for production workloads
  sku {
    name     = var.iot_hub_sku.name
    capacity = var.iot_hub_sku.capacity
  }
  
  # Message routing configuration
  endpoint {
    type                       = "AzureIotHub.StorageContainer"
    connection_string          = azurerm_storage_account.main.primary_blob_connection_string
    name                       = "storage-endpoint"
    batch_frequency_in_seconds = 60
    max_chunk_size_in_bytes    = 10485760
    container_name             = azurerm_storage_container.iot_data.name
    encoding                   = "JSON"
    file_name_format           = "{iothub}/{partition}/{YYYY}/{MM}/{DD}/{HH}/{mm}"
  }
  
  # Default route to storage
  route {
    name           = "telemetry-to-storage"
    source         = "DeviceMessages"
    condition      = "true"
    endpoint_names = ["storage-endpoint"]
    enabled        = true
  }
  
  # Event Hub compatible endpoint configuration
  event_hub_partition_count   = var.iot_hub_partition_count
  event_hub_retention_in_days = var.iot_hub_retention_days
  
  tags = local.common_tags
}

# Storage container for IoT Hub data routing
resource "azurerm_storage_container" "iot_data" {
  name                  = "iot-telemetry-data"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
  
  depends_on = [azurerm_storage_account.main]
}

# Storage container for Time Series Insights
resource "azurerm_storage_container" "tsi_data" {
  name                  = "tsi-cold-storage"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
  
  depends_on = [azurerm_storage_account.main]
}

# Azure Digital Twins instance for manufacturing equipment modeling
resource "azurerm_digital_twins_instance" "main" {
  name                = local.digital_twins_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  
  # Managed identity configuration
  identity {
    type = var.digital_twins_identity_type
  }
  
  tags = local.common_tags
}

# Time Series Insights Gen2 environment for historical analytics
resource "azurerm_iot_time_series_insights_gen2_environment" "main" {
  name                = local.tsi_environment_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  # SKU configuration
  sku_name = var.tsi_sku.name
  
  # Time series ID configuration for device identification
  id_properties = var.tsi_time_series_id_properties
  
  # Storage configuration using the dedicated storage account
  storage {
    name = azurerm_storage_account.main.name
    key  = azurerm_storage_account.main.primary_access_key
  }
  
  # Warm store configuration for fast queries
  warm_store_data_retention_time = var.tsi_warm_store_retention
  
  tags = local.common_tags
  
  depends_on = [
    azurerm_storage_account.main,
    azurerm_storage_container.tsi_data
  ]
}

# Time Series Insights event source connected to IoT Hub
resource "azurerm_iot_time_series_insights_event_source_iothub" "main" {
  name                     = "iot-hub-event-source"
  location                 = azurerm_resource_group.main.location
  environment_id           = azurerm_iot_time_series_insights_gen2_environment.main.id
  iothub_name              = azurerm_iothub.main.name
  consumer_group_name      = azurerm_iothub_consumer_group.tsi.name
  shared_access_key_name   = "iothubowner"
  shared_access_key        = azurerm_iothub.main.shared_access_policy[0].primary_key
  event_source_resource_id = azurerm_iothub.main.id
  
  tags = local.common_tags
  
  depends_on = [
    azurerm_iot_time_series_insights_gen2_environment.main,
    azurerm_iothub_consumer_group.tsi
  ]
}

# IoT Hub consumer group for Time Series Insights
resource "azurerm_iothub_consumer_group" "tsi" {
  name                   = "tsi-consumer-group"
  iothub_name            = azurerm_iothub.main.name
  eventhub_endpoint_name = "events"
  resource_group_name    = azurerm_resource_group.main.name
}

# Machine Learning Workspace for predictive analytics
resource "azurerm_machine_learning_workspace" "main" {
  name                    = local.ml_workspace_name
  location                = azurerm_resource_group.main.location
  resource_group_name     = azurerm_resource_group.main.name
  application_insights_id = azurerm_application_insights.main.id
  key_vault_id            = azurerm_key_vault.main.id
  storage_account_id      = azurerm_storage_account.main.id
  
  # Workspace configuration
  sku_name                   = var.ml_workspace_sku
  public_network_access_enabled = var.ml_workspace_public_network_access == "Enabled"
  
  # Managed identity for secure access to other resources
  identity {
    type = "SystemAssigned"
  }
  
  tags = local.common_tags
  
  depends_on = [
    azurerm_application_insights.main,
    azurerm_key_vault.main,
    azurerm_storage_account.main
  ]
}

# Sample IoT device registrations for testing and demonstration
resource "azurerm_iothub_device" "sample_devices" {
  count = var.create_sample_devices ? length(var.sample_devices) : 0
  
  name                = var.sample_devices[count.index].device_id
  iothub_name         = azurerm_iothub.main.name
  resource_group_name = azurerm_resource_group.main.name
  
  tags = merge(local.common_tags, {
    DeviceType = var.sample_devices[count.index].device_type
    Purpose    = "simulation-and-testing"
  })
}

# Role assignments for Digital Twins access
resource "azurerm_role_assignment" "digital_twins_data_owner" {
  count = var.enable_rbac_assignments ? 1 : 0
  
  scope                = azurerm_digital_twins_instance.main.id
  role_definition_name = "Azure Digital Twins Data Owner"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Additional role assignments for specified principals
resource "azurerm_role_assignment" "additional_digital_twins_access" {
  count = var.enable_rbac_assignments ? length(var.additional_rbac_principals) : 0
  
  scope                = azurerm_digital_twins_instance.main.id
  role_definition_name = "Azure Digital Twins Data Reader"
  principal_id         = var.additional_rbac_principals[count.index]
}

# Role assignment for Digital Twins to access IoT Hub
resource "azurerm_role_assignment" "digital_twins_iot_hub" {
  count = var.enable_rbac_assignments ? 1 : 0
  
  scope                = azurerm_iothub.main.id
  role_definition_name = "IoT Hub Data Contributor"
  principal_id         = azurerm_digital_twins_instance.main.identity[0].principal_id
}

# Role assignment for Machine Learning workspace to access storage
resource "azurerm_role_assignment" "ml_storage_access" {
  count = var.enable_rbac_assignments ? 1 : 0
  
  scope                = azurerm_storage_account.main.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_machine_learning_workspace.main.identity[0].principal_id
}

# Diagnostic settings for IoT Hub
resource "azurerm_monitor_diagnostic_setting" "iot_hub" {
  count = var.enable_diagnostics ? 1 : 0
  
  name                       = "iot-hub-diagnostics"
  target_resource_id         = azurerm_iothub.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
  enabled_log {
    category = "Connections"
  }
  
  enabled_log {
    category = "DeviceTelemetry"
  }
  
  enabled_log {
    category = "C2DCommands"
  }
  
  enabled_log {
    category = "DeviceIdentityOperations"
  }
  
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Diagnostic settings for Digital Twins
resource "azurerm_monitor_diagnostic_setting" "digital_twins" {
  count = var.enable_diagnostics ? 1 : 0
  
  name                       = "digital-twins-diagnostics"
  target_resource_id         = azurerm_digital_twins_instance.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
  enabled_log {
    category = "DigitalTwinsOperation"
  }
  
  enabled_log {
    category = "EventRoutesOperation"
  }
  
  enabled_log {
    category = "ModelsOperation"
  }
  
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Diagnostic settings for Machine Learning workspace
resource "azurerm_monitor_diagnostic_setting" "ml_workspace" {
  count = var.enable_diagnostics ? 1 : 0
  
  name                       = "ml-workspace-diagnostics"
  target_resource_id         = azurerm_machine_learning_workspace.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
  enabled_log {
    category = "AmlComputeClusterEvent"
  }
  
  enabled_log {
    category = "AmlComputeJobEvent"
  }
  
  enabled_log {
    category = "AmlRunStatusChangedEvent"
  }
  
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Key Vault secret for IoT Hub connection string
resource "azurerm_key_vault_secret" "iot_hub_connection" {
  name         = "iot-hub-connection-string"
  value        = azurerm_iothub.main.shared_access_policy[0].connection_string
  key_vault_id = azurerm_key_vault.main.id
  
  tags = local.common_tags
  
  depends_on = [azurerm_key_vault.main]
}

# Key Vault secret for storage account connection string
resource "azurerm_key_vault_secret" "storage_connection" {
  name         = "storage-account-connection-string"
  value        = azurerm_storage_account.main.primary_connection_string
  key_vault_id = azurerm_key_vault.main.id
  
  tags = local.common_tags
  
  depends_on = [azurerm_key_vault.main]
}

# Time delay for resource propagation
resource "time_sleep" "wait_for_rbac" {
  depends_on = [
    azurerm_role_assignment.digital_twins_data_owner,
    azurerm_role_assignment.digital_twins_iot_hub,
    azurerm_role_assignment.ml_storage_access
  ]
  
  create_duration = "60s"
}