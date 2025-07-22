# Main Terraform Configuration for Real-Time Financial Market Data Processing
# This file creates the complete infrastructure for processing financial market data
# using Azure Data Explorer, Event Hubs, Functions, and Event Grid

# Data Sources for Current Environment
data "azurerm_client_config" "current" {}

data "azuread_client_config" "current" {}

# Random Suffix for Unique Resource Names
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Generate unique resource names with random suffix
  random_suffix = lower(random_id.suffix.hex)
  
  # Resource names with fallback to auto-generated names
  resource_group_name       = var.resource_group_name != "" ? var.resource_group_name : "rg-${var.project_name}-${var.environment}-${local.random_suffix}"
  adx_cluster_name         = var.adx_cluster_name != "" ? var.adx_cluster_name : "adx-${var.project_name}-${local.random_suffix}"
  eventhub_namespace_name  = var.eventhub_namespace_name != "" ? var.eventhub_namespace_name : "evhns-${var.project_name}-${local.random_suffix}"
  function_app_name        = var.function_app_name != "" ? var.function_app_name : "func-${var.project_name}-${local.random_suffix}"
  storage_account_name     = var.storage_account_name != "" ? var.storage_account_name : "st${replace(var.project_name, "-", "")}${local.random_suffix}"
  event_grid_topic_name    = var.event_grid_topic_name != "" ? var.event_grid_topic_name : "egt-${var.project_name}-alerts-${local.random_suffix}"
  app_insights_name        = var.application_insights_name != "" ? var.application_insights_name : "appi-${var.project_name}-${local.random_suffix}"
  log_analytics_name       = var.log_analytics_workspace_name != "" ? var.log_analytics_workspace_name : "law-${var.project_name}-${local.random_suffix}"
  
  # Common tags applied to all resources
  common_tags = merge(var.tags, {
    Environment      = var.environment
    Project         = var.project_name
    DeployedBy      = "Terraform"
    LastModified    = timestamp()
  })
}

# Resource Group
# Central container for all financial market data processing resources
resource "azurerm_resource_group" "main" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.common_tags
}

# Log Analytics Workspace
# Centralized logging and monitoring for all components
resource "azurerm_log_analytics_workspace" "main" {
  name                = local.log_analytics_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = var.log_analytics_workspace_sku
  retention_in_days   = var.log_analytics_retention_in_days
  tags                = local.common_tags
}

# Application Insights
# Application performance monitoring and telemetry collection
resource "azurerm_application_insights" "main" {
  name                = local.app_insights_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = var.application_insights_application_type
  tags                = local.common_tags
}

# Storage Account
# Required for Azure Functions runtime and logging
resource "azurerm_storage_account" "main" {
  name                     = local.storage_account_name
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_account_replication_type
  account_kind             = "StorageV2"
  
  # Security configuration
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  
  # Enable blob encryption
  blob_properties {
    delete_retention_policy {
      days = 7
    }
    versioning_enabled = true
  }
  
  tags = local.common_tags
}

# Event Hubs Namespace
# High-throughput data ingestion for market data and trading events
resource "azurerm_eventhub_namespace" "main" {
  name                          = local.eventhub_namespace_name
  location                      = azurerm_resource_group.main.location
  resource_group_name           = azurerm_resource_group.main.name
  sku                          = var.eventhub_namespace_sku
  capacity                     = var.eventhub_namespace_capacity
  auto_inflate_enabled         = var.eventhub_auto_inflate_enabled
  maximum_throughput_units     = var.eventhub_auto_inflate_enabled ? var.eventhub_auto_inflate_maximum_throughput_units : null
  
  # Security configuration
  public_network_access_enabled = !var.enable_private_endpoints
  minimum_tls_version          = "1.2"
  
  tags = local.common_tags
}

# Event Hub for Market Data
# Dedicated hub for high-frequency market data streams (OHLCV, tick data)
resource "azurerm_eventhub" "market_data" {
  name                = "market-data-hub"
  namespace_name      = azurerm_eventhub_namespace.main.name
  resource_group_name = azurerm_resource_group.main.name
  partition_count     = var.market_data_hub_partition_count
  message_retention   = var.eventhub_message_retention
  
  # Capture configuration for data archival (optional)
  capture_description {
    enabled             = false
    encoding            = "Avro"
    interval_in_seconds = 300
    size_limit_in_bytes = 314572800
    
    destination {
      name                = "EventHubArchive.AzureBlockBlob"
      archive_name_format = "{Namespace}/{EventHub}/{PartitionId}/{Year}/{Month}/{Day}/{Hour}/{Minute}/{Second}"
      blob_container_name = "market-data-archive"
      storage_account_id  = azurerm_storage_account.main.id
    }
  }
}

# Event Hub for Trading Events
# Dedicated hub for trading orders, executions, and portfolio events
resource "azurerm_eventhub" "trading_events" {
  name                = "trading-events-hub"
  namespace_name      = azurerm_eventhub_namespace.main.name
  resource_group_name = azurerm_resource_group.main.name
  partition_count     = var.trading_events_hub_partition_count
  message_retention   = var.eventhub_message_retention
}

# Consumer Group for Trading Events
# Dedicated consumer group for Functions processing trading events
resource "azurerm_eventhub_consumer_group" "trading_events" {
  name                = "trading-consumer-group"
  namespace_name      = azurerm_eventhub_namespace.main.name
  eventhub_name       = azurerm_eventhub.trading_events.name
  resource_group_name = azurerm_resource_group.main.name
  user_metadata       = "Trading events processor consumer group"
}

# Azure Data Explorer Cluster
# High-performance analytics engine for time-series market data analysis
resource "azurerm_kusto_cluster" "main" {
  name                = local.adx_cluster_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  sku {
    name     = var.adx_sku_name
    capacity = var.adx_capacity
  }
  
  # Security and access configuration
  public_network_access_enabled = !var.enable_private_endpoints
  disk_encryption_enabled       = true
  streaming_ingestion_enabled   = true
  purge_enabled                = false
  
  # Auto-stop configuration for cost optimization (dev environments)
  auto_stop_enabled = var.environment == "dev" ? true : false
  
  # Identity configuration for secure access to other Azure services
  identity {
    type = "SystemAssigned"
  }
  
  tags = local.common_tags
}

# Azure Data Explorer Database
# Database optimized for financial time-series data storage and analysis
resource "azurerm_kusto_database" "main" {
  name                = var.adx_database_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  cluster_name        = azurerm_kusto_cluster.main.name
  
  # Storage and retention configuration optimized for financial data
  hot_cache_period   = var.adx_hot_cache_period
  soft_delete_period = var.adx_soft_delete_period
}

# Data Connection from Event Hubs to Azure Data Explorer
# Real-time streaming ingestion of market data into ADX
resource "azurerm_kusto_eventhub_data_connection" "market_data" {
  name                = "market-data-connection"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  cluster_name        = azurerm_kusto_cluster.main.name
  database_name       = azurerm_kusto_database.main.name
  
  eventhub_id         = azurerm_eventhub.market_data.id
  consumer_group      = "$Default"
  table_name          = "MarketDataRaw"
  mapping_rule_name   = "MarketDataMapping"
  data_format         = "JSON"
  compression         = "None"
  
  # Event system properties for metadata
  event_system_properties = [
    "x-opt-enqueued-time",
    "x-opt-sequence-number",
    "x-opt-partition-key"
  ]
}

# Event Grid Topic
# Event-driven messaging for trading alerts and notifications
resource "azurerm_eventgrid_topic" "main" {
  name                = local.event_grid_topic_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  input_schema        = var.event_grid_input_schema
  
  # Security configuration
  public_network_access_enabled = !var.enable_private_endpoints
  
  tags = local.common_tags
}

# App Service Plan for Azure Functions
# Compute resources for serverless market data processing
resource "azurerm_service_plan" "main" {
  name                = "asp-${var.project_name}-${var.environment}-${local.random_suffix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  os_type             = "Linux"
  sku_name            = var.function_app_service_plan_sku
  tags                = local.common_tags
}

# Linux Function App
# Serverless compute for processing market data events and generating alerts
resource "azurerm_linux_function_app" "main" {
  name                = local.function_app_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  
  storage_account_name       = azurerm_storage_account.main.name
  storage_account_access_key = azurerm_storage_account.main.primary_access_key
  service_plan_id           = azurerm_service_plan.main.id
  
  # Runtime configuration
  site_config {
    application_stack {
      python_version = var.function_app_runtime_version
    }
    
    # CORS configuration for web access
    cors {
      allowed_origins = ["https://portal.azure.com"]
    }
    
    # Security headers
    ftps_state = "Disabled"
    http2_enabled = true
    minimum_tls_version = "1.2"
  }
  
  # Application settings for connecting to Azure services
  app_settings = {
    "FUNCTIONS_WORKER_RUNTIME"                = "python"
    "FUNCTIONS_EXTENSION_VERSION"             = "~4"
    "WEBSITE_RUN_FROM_PACKAGE"               = "1"
    "APPINSIGHTS_INSTRUMENTATIONKEY"         = azurerm_application_insights.main.instrumentation_key
    "APPLICATIONINSIGHTS_CONNECTION_STRING"   = azurerm_application_insights.main.connection_string
    
    # Event Hubs configuration
    "EventHubConnectionString"               = azurerm_eventhub_namespace.main.default_primary_connection_string
    "MarketDataHubName"                     = azurerm_eventhub.market_data.name
    "TradingEventsHubName"                  = azurerm_eventhub.trading_events.name
    
    # Azure Data Explorer configuration
    "ADX_CLUSTER_URI"                       = azurerm_kusto_cluster.main.uri
    "ADX_DATABASE"                          = azurerm_kusto_database.main.name
    "ADX_CLIENT_ID"                         = azurerm_kusto_cluster.main.identity[0].principal_id
    
    # Event Grid configuration
    "EventGridEndpoint"                     = azurerm_eventgrid_topic.main.endpoint
    "EventGridKey"                          = azurerm_eventgrid_topic.main.primary_access_key
    "EventGridTopicName"                    = azurerm_eventgrid_topic.main.name
    
    # Application configuration
    "ENVIRONMENT"                           = var.environment
    "PROJECT_NAME"                          = var.project_name
  }
  
  # Identity configuration for secure access to Azure services
  identity {
    type = "SystemAssigned"
  }
  
  tags = local.common_tags
}

# Storage Container for Event Hub Capture (optional)
resource "azurerm_storage_container" "market_data_archive" {
  name                  = "market-data-archive"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

# Role Assignment: Function App to Event Hubs
# Grants Function App access to read from Event Hubs
resource "azurerm_role_assignment" "function_app_eventhubs" {
  scope                = azurerm_eventhub_namespace.main.id
  role_definition_name = "Azure Event Hubs Data Receiver"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id
}

# Role Assignment: Function App to Event Grid
# Grants Function App access to publish events to Event Grid
resource "azurerm_role_assignment" "function_app_eventgrid" {
  scope                = azurerm_eventgrid_topic.main.id
  role_definition_name = "EventGrid Data Sender"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id
}

# Role Assignment: Function App to Azure Data Explorer
# Grants Function App access to query and write data to ADX
resource "azurerm_role_assignment" "function_app_adx_admin" {
  scope                = azurerm_kusto_cluster.main.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id
}

# Role Assignment: ADX to Event Hubs
# Grants Azure Data Explorer access to read from Event Hubs for data ingestion
resource "azurerm_role_assignment" "adx_eventhubs" {
  scope                = azurerm_eventhub_namespace.main.id
  role_definition_name = "Azure Event Hubs Data Receiver"
  principal_id         = azurerm_kusto_cluster.main.identity[0].principal_id
}

# Diagnostic Settings for Event Hubs Namespace
resource "azurerm_monitor_diagnostic_setting" "eventhubs" {
  count                      = var.enable_diagnostic_settings ? 1 : 0
  name                       = "diag-${azurerm_eventhub_namespace.main.name}"
  target_resource_id         = azurerm_eventhub_namespace.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
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

# Diagnostic Settings for Azure Data Explorer
resource "azurerm_monitor_diagnostic_setting" "adx" {
  count                      = var.enable_diagnostic_settings ? 1 : 0
  name                       = "diag-${azurerm_kusto_cluster.main.name}"
  target_resource_id         = azurerm_kusto_cluster.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
  enabled_log {
    category = "Command"
  }
  
  enabled_log {
    category = "Query"
  }
  
  enabled_log {
    category = "IngestionBatching"
  }
  
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Diagnostic Settings for Function App
resource "azurerm_monitor_diagnostic_setting" "function_app" {
  count                      = var.enable_diagnostic_settings ? 1 : 0
  name                       = "diag-${azurerm_linux_function_app.main.name}"
  target_resource_id         = azurerm_linux_function_app.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
  enabled_log {
    category = "FunctionAppLogs"
  }
  
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Budget Alert for Cost Management
resource "azurerm_consumption_budget_resource_group" "main" {
  count           = var.enable_cost_alerts ? 1 : 0
  name            = "budget-${var.project_name}-${var.environment}"
  resource_group_id = azurerm_resource_group.main.id
  
  amount     = var.monthly_budget_limit
  time_grain = "Monthly"
  
  time_period {
    start_date = formatdate("YYYY-MM-01'T'00:00:00'Z'", timestamp())
    end_date   = formatdate("YYYY-MM-01'T'00:00:00'Z'", timeadd(timestamp(), "8760h")) # 1 year
  }
  
  filter {
    dimension {
      name = "ResourceGroupName"
      values = [azurerm_resource_group.main.name]
    }
  }
  
  notification {
    enabled   = true
    threshold = 80
    operator  = "GreaterThan"
    
    contact_emails = [
      "admin@example.com"  # Replace with actual email addresses
    ]
  }
  
  notification {
    enabled   = true
    threshold = 100
    operator  = "GreaterThan"
    
    contact_emails = [
      "admin@example.com"  # Replace with actual email addresses
    ]
  }
}