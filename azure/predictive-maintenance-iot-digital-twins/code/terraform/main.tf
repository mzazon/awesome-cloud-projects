# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Data source to get current user information
data "azurerm_client_config" "current" {}

# Local values for computed names
locals {
  resource_suffix = random_string.suffix.result
  
  # Compute resource names with suffix if not provided
  digital_twins_name      = var.digital_twins_name != "" ? var.digital_twins_name : "adt-iot-${local.resource_suffix}"
  iot_central_name        = var.iot_central_name != "" ? var.iot_central_name : "iotc-${local.resource_suffix}"
  iot_central_subdomain   = var.iot_central_subdomain != "" ? var.iot_central_subdomain : "iotc-${local.resource_suffix}"
  event_hub_namespace_name = var.event_hub_namespace_name != "" ? var.event_hub_namespace_name : "ehns-iot-${local.resource_suffix}"
  data_explorer_cluster_name = var.data_explorer_cluster_name != "" ? var.data_explorer_cluster_name : "adxiot${local.resource_suffix}"
  function_app_name       = var.function_app_name != "" ? var.function_app_name : "func-iot-${local.resource_suffix}"
  storage_account_name    = var.storage_account_name != "" ? var.storage_account_name : "stiotfunc${local.resource_suffix}"
  time_series_insights_name = var.time_series_insights_name != "" ? var.time_series_insights_name : "tsi-iot-${local.resource_suffix}"
  log_analytics_workspace_name = var.log_analytics_workspace_name != "" ? var.log_analytics_workspace_name : "law-iot-${local.resource_suffix}"
  
  # User object ID for RBAC assignments
  user_object_id = var.user_object_id != null ? var.user_object_id : data.azurerm_client_config.current.object_id
  
  # Common tags
  common_tags = merge(var.tags, {
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
  })
}

# Resource Group
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  tags     = local.common_tags
}

# Log Analytics Workspace (for diagnostic logs)
resource "azurerm_log_analytics_workspace" "main" {
  count               = var.enable_diagnostic_logs ? 1 : 0
  name                = local.log_analytics_workspace_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  tags                = local.common_tags
}

# Storage Account for Function App
resource "azurerm_storage_account" "function_storage" {
  name                     = local.storage_account_name
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_account_replication_type
  
  # Security settings
  enable_https_traffic_only = true
  min_tls_version          = "TLS1_2"
  
  tags = local.common_tags
}

# Azure Digital Twins Instance
resource "azurerm_digital_twins_instance" "main" {
  name                = local.digital_twins_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  tags                = local.common_tags
}

# Role assignment for Digital Twins Data Owner
resource "azurerm_role_assignment" "digital_twins_data_owner" {
  scope                = azurerm_digital_twins_instance.main.id
  role_definition_name = "Azure Digital Twins Data Owner"
  principal_id         = local.user_object_id
}

# Event Hub Namespace
resource "azurerm_eventhub_namespace" "main" {
  name                = local.event_hub_namespace_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = var.event_hub_namespace_sku
  capacity            = var.event_hub_capacity
  
  tags = local.common_tags
}

# Event Hub
resource "azurerm_eventhub" "telemetry" {
  name                = var.event_hub_name
  namespace_name      = azurerm_eventhub_namespace.main.name
  resource_group_name = azurerm_resource_group.main.name
  partition_count     = var.event_hub_partition_count
  message_retention   = var.event_hub_message_retention
}

# Event Hub Authorization Rule
resource "azurerm_eventhub_authorization_rule" "main" {
  name                = "RootManageSharedAccessKey"
  namespace_name      = azurerm_eventhub_namespace.main.name
  eventhub_name       = azurerm_eventhub.telemetry.name
  resource_group_name = azurerm_resource_group.main.name
  listen              = true
  send                = true
  manage              = true
}

# Digital Twins Endpoint for Event Hub
resource "azurerm_digital_twins_endpoint_eventhub" "main" {
  name                                 = "telemetry-endpoint"
  digital_twins_id                     = azurerm_digital_twins_instance.main.id
  eventhub_primary_connection_string   = azurerm_eventhub_authorization_rule.main.primary_connection_string
  eventhub_secondary_connection_string = azurerm_eventhub_authorization_rule.main.secondary_connection_string
}

# Azure Data Explorer Cluster
resource "azurerm_kusto_cluster" "main" {
  name                = local.data_explorer_cluster_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  sku {
    name     = var.data_explorer_sku
    capacity = var.data_explorer_capacity
  }
  
  tags = local.common_tags
}

# Azure Data Explorer Database
resource "azurerm_kusto_database" "main" {
  name                = var.data_explorer_database_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  cluster_name        = azurerm_kusto_cluster.main.name
  
  hot_cache_period   = var.data_explorer_hot_cache_period
  soft_delete_period = var.data_explorer_soft_delete_period
}

# Data connection from Event Hub to Azure Data Explorer
resource "azurerm_kusto_eventhub_data_connection" "main" {
  name                = "iot-telemetry-connection"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  cluster_name        = azurerm_kusto_cluster.main.name
  database_name       = azurerm_kusto_database.main.name
  
  eventhub_id    = azurerm_eventhub.telemetry.id
  consumer_group = "$Default"
  
  table_name        = "TelemetryData"
  mapping_rule_name = "TelemetryMapping"
  data_format       = "JSON"
  compression       = "None"
}

# IoT Central Application
resource "azurerm_iotcentral_application" "main" {
  name                = local.iot_central_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sub_domain          = local.iot_central_subdomain
  
  sku      = var.iot_central_sku
  template = var.iot_central_template
  
  tags = local.common_tags
}

# Service Plan for Function App
resource "azurerm_service_plan" "function_app" {
  name                = "asp-${local.function_app_name}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  os_type             = "Linux"
  sku_name            = var.function_app_service_plan_sku
  tags                = local.common_tags
}

# Function App
resource "azurerm_linux_function_app" "main" {
  name                = local.function_app_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  
  storage_account_name       = azurerm_storage_account.function_storage.name
  storage_account_access_key = azurerm_storage_account.function_storage.primary_access_key
  service_plan_id            = azurerm_service_plan.function_app.id
  
  site_config {
    application_stack {
      dotnet_version = "6.0"
    }
  }
  
  app_settings = {
    "ADT_SERVICE_URL"                    = "https://${azurerm_digital_twins_instance.main.host_name}"
    "EventHubConnection"                 = azurerm_eventhub_authorization_rule.main.primary_connection_string
    "AzureWebJobsStorage"               = azurerm_storage_account.function_storage.primary_connection_string
    "FUNCTIONS_EXTENSION_VERSION"        = "~4"
    "FUNCTIONS_WORKER_RUNTIME"           = "dotnet"
    "WEBSITE_RUN_FROM_PACKAGE"          = "1"
  }
  
  identity {
    type = "SystemAssigned"
  }
  
  tags = local.common_tags
}

# Role assignment for Function App to access Digital Twins
resource "azurerm_role_assignment" "function_app_digital_twins" {
  scope                = azurerm_digital_twins_instance.main.id
  role_definition_name = "Azure Digital Twins Data Owner"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id
}

# Time Series Insights Gen2 Environment
resource "azurerm_iot_time_series_insights_gen2_environment" "main" {
  name                = local.time_series_insights_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku_name            = var.time_series_insights_sku
  id_properties       = ["deviceId"]
  
  storage {
    name = azurerm_storage_account.function_storage.name
    key  = azurerm_storage_account.function_storage.primary_access_key
  }
  
  tags = local.common_tags
}

# Diagnostic Settings for Digital Twins (if enabled)
resource "azurerm_monitor_diagnostic_setting" "digital_twins" {
  count              = var.enable_diagnostic_logs ? 1 : 0
  name               = "digital-twins-diagnostics"
  target_resource_id = azurerm_digital_twins_instance.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main[0].id
  
  enabled_log {
    category = "DigitalTwinsOperation"
  }
  
  enabled_log {
    category = "EventRoutesOperation"
  }
  
  enabled_log {
    category = "ModelsOperation"
  }
  
  enabled_log {
    category = "QueryOperation"
  }
  
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Diagnostic Settings for Event Hub Namespace (if enabled)
resource "azurerm_monitor_diagnostic_setting" "event_hub" {
  count              = var.enable_diagnostic_logs ? 1 : 0
  name               = "eventhub-diagnostics"
  target_resource_id = azurerm_eventhub_namespace.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main[0].id
  
  enabled_log {
    category = "ArchiveLogs"
  }
  
  enabled_log {
    category = "OperationalLogs"
  }
  
  enabled_log {
    category = "AutoScaleLogs"
  }
  
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Diagnostic Settings for Data Explorer Cluster (if enabled)
resource "azurerm_monitor_diagnostic_setting" "data_explorer" {
  count              = var.enable_diagnostic_logs ? 1 : 0
  name               = "data-explorer-diagnostics"
  target_resource_id = azurerm_kusto_cluster.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main[0].id
  
  enabled_log {
    category = "IngestionLogs"
  }
  
  enabled_log {
    category = "QueryLogs"
  }
  
  enabled_log {
    category = "TableUsageStatistics"
  }
  
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Diagnostic Settings for Function App (if enabled)
resource "azurerm_monitor_diagnostic_setting" "function_app" {
  count              = var.enable_diagnostic_logs ? 1 : 0
  name               = "function-app-diagnostics"
  target_resource_id = azurerm_linux_function_app.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main[0].id
  
  enabled_log {
    category = "FunctionAppLogs"
  }
  
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}