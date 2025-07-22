# Main Terraform Configuration for Azure Intelligent Financial Trading Signal Analysis
# This file contains the primary infrastructure resources for the trading signal analysis system

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local values for resource naming and configuration
locals {
  # Resource naming with unique suffix
  resource_prefix = "${var.project_name}-${var.environment}"
  unique_suffix   = random_string.suffix.result
  
  # Resource names following Azure naming conventions
  resource_group_name          = var.resource_group_name
  ai_services_name            = "${local.resource_prefix}-ai-${local.unique_suffix}"
  storage_account_name        = replace("${local.resource_prefix}st${local.unique_suffix}", "-", "")
  event_hub_namespace_name    = "${local.resource_prefix}-ehns-${local.unique_suffix}"
  event_hub_name              = "market-data-hub"
  stream_analytics_job_name   = "${local.resource_prefix}-saj"
  cosmos_db_account_name      = "${local.resource_prefix}-cosmos-${local.unique_suffix}"
  cosmos_db_database_name     = "TradingSignals"
  cosmos_db_container_name    = "Signals"
  function_app_name           = "${local.resource_prefix}-func-${local.unique_suffix}"
  service_bus_namespace_name  = "${local.resource_prefix}-sb-${local.unique_suffix}"
  service_bus_topic_name      = "trading-signals"
  app_service_plan_name       = "${local.resource_prefix}-asp-${local.unique_suffix}"
  log_analytics_workspace_name = "${local.resource_prefix}-law-${local.unique_suffix}"
  
  # Common tags for all resources
  common_tags = merge({
    Environment    = var.environment
    Project        = var.project_name
    Owner          = var.owner
    CostCenter     = var.cost_center
    Purpose        = "trading-signals"
    DeployedWith   = "terraform"
    CreatedDate    = formatdate("YYYY-MM-DD", timestamp())
  }, var.common_tags)
}

# Data source for current Azure client configuration
data "azurerm_client_config" "current" {}

# Resource Group
resource "azurerm_resource_group" "main" {
  name     = local.resource_group_name
  location = var.location
  
  tags = local.common_tags
}

# Log Analytics Workspace for monitoring and diagnostics
resource "azurerm_log_analytics_workspace" "main" {
  name                = local.log_analytics_workspace_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  
  tags = local.common_tags
}

# Storage Account for content processing and data lake
resource "azurerm_storage_account" "main" {
  name                     = local.storage_account_name
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_replication_type
  account_kind             = "StorageV2"
  access_tier              = "Hot"
  
  # Enable security features
  enable_https_traffic_only      = true
  min_tls_version               = "TLS1_2"
  allow_nested_items_to_be_public = false
  
  # Enable blob storage features
  blob_properties {
    cors_rule {
      allowed_headers    = ["*"]
      allowed_methods    = ["GET", "HEAD", "POST", "PUT"]
      allowed_origins    = ["*"]
      exposed_headers    = ["*"]
      max_age_in_seconds = 3600
    }
    
    # Enable versioning for data governance
    versioning_enabled = true
    
    # Configure lifecycle management
    delete_retention_policy {
      days = 30
    }
    
    container_delete_retention_policy {
      days = 30
    }
  }
  
  tags = local.common_tags
}

# Storage containers for different content types
resource "azurerm_storage_container" "financial_videos" {
  name                  = "financial-videos"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "research_documents" {
  name                  = "research-documents"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "processed_insights" {
  name                  = "processed-insights"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

# Storage Account Lifecycle Management Policy
resource "azurerm_storage_management_policy" "main" {
  storage_account_id = azurerm_storage_account.main.id

  rule {
    name    = "ArchiveOldContent"
    enabled = true
    
    filters {
      blob_types = ["blockBlob"]
    }
    
    actions {
      base_blob {
        tier_to_cool_after_days_since_modification_greater_than    = 30
        tier_to_archive_after_days_since_modification_greater_than = 90
        delete_after_days_since_modification_greater_than         = 2555  # 7 years
      }
    }
  }
}

# Azure AI Services (Cognitive Services) for Content Understanding
resource "azurerm_cognitive_account" "main" {
  name                = local.ai_services_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  kind                = "CognitiveServices"
  sku_name            = var.cognitive_services_sku
  
  # Enable custom domain for advanced features
  custom_question_answering_search_service_id = null
  
  # Network access configuration
  network_acls {
    default_action = "Allow"
    
    # Configure IP rules for production environments
    ip_rules = []
    
    # Configure virtual network rules if needed
    virtual_network_rules {
      subnet_id = null
    }
  }
  
  # Enable identity for secure access
  identity {
    type = "SystemAssigned"
  }
  
  tags = local.common_tags
}

# Event Hubs Namespace for real-time data ingestion
resource "azurerm_eventhub_namespace" "main" {
  name                     = local.event_hub_namespace_name
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  sku                      = var.event_hub_sku
  capacity                 = var.event_hub_capacity
  auto_inflate_enabled     = true
  maximum_throughput_units = 10
  
  # Enable zone redundancy for high availability
  zone_redundant = var.event_hub_sku == "Premium"
  
  # Network security configuration
  network_rulesets {
    default_action = "Allow"
    
    # Configure trusted service access
    trusted_service_access_enabled = true
    
    # IP rules for production environments
    ip_rule = []
    
    # Virtual network rules
    virtual_network_rule = []
  }
  
  tags = local.common_tags
}

# Event Hub for market data streams
resource "azurerm_eventhub" "market_data" {
  name                = local.event_hub_name
  namespace_name      = azurerm_eventhub_namespace.main.name
  resource_group_name = azurerm_resource_group.main.name
  partition_count     = var.event_hub_partition_count
  message_retention   = var.event_hub_message_retention
  
  # Enable capture for long-term storage
  capture_description {
    enabled             = true
    encoding            = "Avro"
    interval_in_seconds = 300
    size_limit_in_bytes = 314572800
    
    destination {
      archive_name_format = "{Namespace}/{EventHub}/{PartitionId}/{Year}/{Month}/{Day}/{Hour}/{Minute}/{Second}"
      blob_container_name = azurerm_storage_container.processed_insights.name
      name                = "EventHubArchive"
      storage_account_id  = azurerm_storage_account.main.id
    }
  }
}

# Consumer group for Stream Analytics
resource "azurerm_eventhub_consumer_group" "stream_analytics" {
  name                = "stream-analytics-consumer"
  namespace_name      = azurerm_eventhub_namespace.main.name
  eventhub_name       = azurerm_eventhub.market_data.name
  resource_group_name = azurerm_resource_group.main.name
  user_metadata       = "Stream Analytics Consumer Group"
}

# Consumer group for Functions
resource "azurerm_eventhub_consumer_group" "functions" {
  name                = "functions-consumer"
  namespace_name      = azurerm_eventhub_namespace.main.name
  eventhub_name       = azurerm_eventhub.market_data.name
  resource_group_name = azurerm_resource_group.main.name
  user_metadata       = "Functions Consumer Group"
}

# Cosmos DB Account for signal storage
resource "azurerm_cosmosdb_account" "main" {
  name                = local.cosmos_db_account_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  offer_type          = "Standard"
  kind                = "GlobalDocumentDB"
  
  # Enable automatic failover for high availability
  enable_automatic_failover = true
  enable_multiple_write_locations = false
  
  # Configure consistency policy
  consistency_policy {
    consistency_level       = var.cosmos_db_consistency_level
    max_interval_in_seconds = 300
    max_staleness_prefix    = 100000
  }
  
  # Primary region configuration
  geo_location {
    location          = azurerm_resource_group.main.location
    failover_priority = 0
  }
  
  # Enable backup
  backup {
    type                = "Periodic"
    interval_in_minutes = 240
    retention_in_hours  = 8
    storage_redundancy  = "Geo"
  }
  
  # Network access configuration
  is_virtual_network_filter_enabled = false
  public_network_access_enabled     = true
  
  # Enable analytical storage for advanced analytics
  analytical_storage_enabled = true
  
  tags = local.common_tags
}

# Cosmos DB SQL Database
resource "azurerm_cosmosdb_sql_database" "main" {
  name                = local.cosmos_db_database_name
  resource_group_name = azurerm_resource_group.main.name
  account_name        = azurerm_cosmosdb_account.main.name
}

# Cosmos DB SQL Container for trading signals
resource "azurerm_cosmosdb_sql_container" "signals" {
  name                  = local.cosmos_db_container_name
  resource_group_name   = azurerm_resource_group.main.name
  account_name          = azurerm_cosmosdb_account.main.name
  database_name         = azurerm_cosmosdb_sql_database.main.name
  partition_key_path    = "/symbol"
  partition_key_version = 1
  
  # Configure throughput with autoscaling
  autoscale_settings {
    max_throughput = var.cosmos_db_max_throughput
  }
  
  # Configure TTL for automatic cleanup
  default_ttl = 604800  # 7 days in seconds
  
  # Indexing policy for optimal query performance
  indexing_policy {
    indexing_mode = "consistent"
    
    included_path {
      path = "/*"
    }
    
    excluded_path {
      path = "/\"_etag\"/?"
    }
  }
  
  # Unique key for preventing duplicates
  unique_key {
    paths = ["/symbol", "/timestamp"]
  }
}

# App Service Plan for Function App
resource "azurerm_service_plan" "main" {
  name                = local.app_service_plan_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  os_type             = var.function_app_os_type
  sku_name            = var.function_app_sku
  
  # Enable zone redundancy for high availability
  zone_balancing_enabled = var.function_app_sku != "Y1"
  
  tags = local.common_tags
}

# Function App for signal processing
resource "azurerm_windows_function_app" "main" {
  count = var.function_app_os_type == "Windows" ? 1 : 0
  
  name                = local.function_app_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  service_plan_id     = azurerm_service_plan.main.id
  storage_account_name       = azurerm_storage_account.main.name
  storage_account_access_key = azurerm_storage_account.main.primary_access_key
  
  # Enable system-assigned managed identity
  identity {
    type = "SystemAssigned"
  }
  
  # Application settings
  app_settings = {
    "FUNCTIONS_WORKER_RUNTIME"     = var.function_app_runtime
    "FUNCTIONS_EXTENSION_VERSION"  = "~4"
    "WEBSITE_RUN_FROM_PACKAGE"     = "1"
    "WEBSITE_ENABLE_SYNC_UPDATE_SITE" = "true"
    
    # Service connection strings
    "CosmosDB_Endpoint"           = azurerm_cosmosdb_account.main.endpoint
    "CosmosDB_DatabaseName"       = azurerm_cosmosdb_sql_database.main.name
    "CosmosDB_ContainerName"      = azurerm_cosmosdb_sql_container.signals.name
    "EventHub_ConnectionString"   = azurerm_eventhub_namespace.main.default_primary_connection_string
    "EventHub_Name"               = azurerm_eventhub.market_data.name
    "AzureAI_Endpoint"            = azurerm_cognitive_account.main.endpoint
    "Storage_ConnectionString"    = azurerm_storage_account.main.primary_connection_string
    "ServiceBus_ConnectionString" = azurerm_servicebus_namespace.main.default_primary_connection_string
    "ServiceBus_TopicName"        = azurerm_servicebus_topic.trading_signals.name
    
    # Application Insights
    "APPINSIGHTS_INSTRUMENTATIONKEY" = azurerm_application_insights.main.instrumentation_key
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = azurerm_application_insights.main.connection_string
  }
  
  # Site configuration
  site_config {
    always_on = var.function_app_sku != "Y1"
    
    # Enable Application Insights
    application_insights_key               = azurerm_application_insights.main.instrumentation_key
    application_insights_connection_string = azurerm_application_insights.main.connection_string
    
    # Configure runtime
    application_stack {
      dotnet_version = var.function_app_version
    }
    
    # Enable CORS for development
    cors {
      allowed_origins = ["*"]
    }
  }
  
  tags = local.common_tags
}

# Linux Function App (alternative to Windows)
resource "azurerm_linux_function_app" "main" {
  count = var.function_app_os_type == "Linux" ? 1 : 0
  
  name                = local.function_app_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  service_plan_id     = azurerm_service_plan.main.id
  storage_account_name       = azurerm_storage_account.main.name
  storage_account_access_key = azurerm_storage_account.main.primary_access_key
  
  # Enable system-assigned managed identity
  identity {
    type = "SystemAssigned"
  }
  
  # Application settings (same as Windows)
  app_settings = {
    "FUNCTIONS_WORKER_RUNTIME"     = var.function_app_runtime
    "FUNCTIONS_EXTENSION_VERSION"  = "~4"
    "WEBSITE_RUN_FROM_PACKAGE"     = "1"
    "WEBSITE_ENABLE_SYNC_UPDATE_SITE" = "true"
    
    # Service connection strings
    "CosmosDB_Endpoint"           = azurerm_cosmosdb_account.main.endpoint
    "CosmosDB_DatabaseName"       = azurerm_cosmosdb_sql_database.main.name
    "CosmosDB_ContainerName"      = azurerm_cosmosdb_sql_container.signals.name
    "EventHub_ConnectionString"   = azurerm_eventhub_namespace.main.default_primary_connection_string
    "EventHub_Name"               = azurerm_eventhub.market_data.name
    "AzureAI_Endpoint"            = azurerm_cognitive_account.main.endpoint
    "Storage_ConnectionString"    = azurerm_storage_account.main.primary_connection_string
    "ServiceBus_ConnectionString" = azurerm_servicebus_namespace.main.default_primary_connection_string
    "ServiceBus_TopicName"        = azurerm_servicebus_topic.trading_signals.name
    
    # Application Insights
    "APPINSIGHTS_INSTRUMENTATIONKEY" = azurerm_application_insights.main.instrumentation_key
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = azurerm_application_insights.main.connection_string
  }
  
  # Site configuration
  site_config {
    always_on = var.function_app_sku != "Y1"
    
    # Enable Application Insights
    application_insights_key               = azurerm_application_insights.main.instrumentation_key
    application_insights_connection_string = azurerm_application_insights.main.connection_string
    
    # Configure runtime
    application_stack {
      dotnet_version = var.function_app_version
    }
    
    # Enable CORS for development
    cors {
      allowed_origins = ["*"]
    }
  }
  
  tags = local.common_tags
}

# Service Bus Namespace for signal distribution
resource "azurerm_servicebus_namespace" "main" {
  name                = local.service_bus_namespace_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = var.service_bus_sku
  capacity            = var.service_bus_sku == "Premium" ? var.service_bus_capacity : null
  
  # Enable zone redundancy for Premium SKU
  zone_redundant = var.service_bus_sku == "Premium"
  
  tags = local.common_tags
}

# Service Bus Topic for trading signals
resource "azurerm_servicebus_topic" "trading_signals" {
  name                = local.service_bus_topic_name
  namespace_id        = azurerm_servicebus_namespace.main.id
  max_size_in_megabytes = 5120
  default_message_ttl = "P7D"  # 7 days
  
  # Enable duplicate detection
  duplicate_detection_history_time_window = "PT10M"
  
  # Enable partitioning for better performance
  partitioning_enabled = true
  
  # Enable express for smaller messages
  express_enabled = false
}

# Service Bus Subscription for high-priority signals
resource "azurerm_servicebus_subscription" "high_priority" {
  name                                 = "high-priority-signals"
  topic_id                            = azurerm_servicebus_topic.trading_signals.id
  max_delivery_count                  = 3
  default_message_ttl                 = "P7D"
  enable_batched_operations           = true
  requires_session                    = false
  dead_lettering_on_message_expiration = true
  
  # Auto-delete subscription when idle
  auto_delete_on_idle = "P14D"  # 14 days
}

# Service Bus Subscription Rule for strong signals
resource "azurerm_servicebus_subscription_rule" "strong_signals" {
  name            = "strong-signals-only"
  subscription_id = azurerm_servicebus_subscription.high_priority.id
  filter_type     = "SqlFilter"
  sql_filter      = "signal IN ('STRONG_BUY', 'STRONG_SELL')"
}

# Stream Analytics Job for real-time processing
resource "azurerm_stream_analytics_job" "main" {
  name                                     = local.stream_analytics_job_name
  resource_group_name                      = azurerm_resource_group.main.name
  location                                 = azurerm_resource_group.main.location
  compatibility_level                      = "1.2"
  data_locale                             = "en-US"
  events_late_arrival_max_delay_in_seconds = 60
  events_out_of_order_max_delay_in_seconds = 50
  events_out_of_order_policy              = "Adjust"
  output_error_policy                     = "Stop"
  streaming_units                         = var.stream_analytics_streaming_units
  
  # Configure job storage for debugging
  job_storage_account {
    account_name = azurerm_storage_account.main.name
    account_key  = azurerm_storage_account.main.primary_access_key
  }
  
  # Enable identity for secure access
  identity {
    type = "SystemAssigned"
  }
  
  tags = local.common_tags
}

# Stream Analytics Input from Event Hub
resource "azurerm_stream_analytics_stream_input_eventhub" "market_data" {
  name                         = "MarketDataInput"
  stream_analytics_job_name    = azurerm_stream_analytics_job.main.name
  resource_group_name          = azurerm_resource_group.main.name
  eventhub_consumer_group_name = azurerm_eventhub_consumer_group.stream_analytics.name
  eventhub_name                = azurerm_eventhub.market_data.name
  servicebus_namespace         = azurerm_eventhub_namespace.main.name
  shared_access_policy_key     = azurerm_eventhub_namespace.main.default_primary_key
  shared_access_policy_name    = "RootManageSharedAccessKey"
  
  # Configure input serialization
  serialization {
    type     = "Json"
    encoding = "UTF8"
  }
}

# Stream Analytics Output to Cosmos DB
resource "azurerm_stream_analytics_output_cosmosdb" "signals" {
  name                    = "SignalOutput"
  stream_analytics_job_name = azurerm_stream_analytics_job.main.name
  resource_group_name     = azurerm_resource_group.main.name
  cosmosdb_account_key    = azurerm_cosmosdb_account.main.primary_key
  cosmosdb_sql_database_id = azurerm_cosmosdb_sql_database.main.id
  container_name          = azurerm_cosmosdb_sql_container.signals.name
  document_id             = "signal_id"
  partition_key           = "symbol"
}

# Application Insights for monitoring
resource "azurerm_application_insights" "main" {
  name                = "${local.resource_prefix}-ai-${local.unique_suffix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = "web"
  
  # Configure retention
  retention_in_days = var.log_retention_days
  
  # Enable advanced features
  daily_data_cap_in_gb = 10
  
  tags = local.common_tags
}

# Role assignments for Function App to access services
resource "azurerm_role_assignment" "function_cosmos_contributor" {
  scope                = azurerm_cosmosdb_account.main.id
  role_definition_name = "Cosmos DB Built-in Data Contributor"
  principal_id         = var.function_app_os_type == "Windows" ? azurerm_windows_function_app.main[0].identity[0].principal_id : azurerm_linux_function_app.main[0].identity[0].principal_id
}

resource "azurerm_role_assignment" "function_storage_contributor" {
  scope                = azurerm_storage_account.main.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.function_app_os_type == "Windows" ? azurerm_windows_function_app.main[0].identity[0].principal_id : azurerm_linux_function_app.main[0].identity[0].principal_id
}

resource "azurerm_role_assignment" "function_cognitive_user" {
  scope                = azurerm_cognitive_account.main.id
  role_definition_name = "Cognitive Services User"
  principal_id         = var.function_app_os_type == "Windows" ? azurerm_windows_function_app.main[0].identity[0].principal_id : azurerm_linux_function_app.main[0].identity[0].principal_id
}

resource "azurerm_role_assignment" "function_eventhub_receiver" {
  scope                = azurerm_eventhub_namespace.main.id
  role_definition_name = "Azure Event Hubs Data Receiver"
  principal_id         = var.function_app_os_type == "Windows" ? azurerm_windows_function_app.main[0].identity[0].principal_id : azurerm_linux_function_app.main[0].identity[0].principal_id
}

resource "azurerm_role_assignment" "function_servicebus_sender" {
  scope                = azurerm_servicebus_namespace.main.id
  role_definition_name = "Azure Service Bus Data Sender"
  principal_id         = var.function_app_os_type == "Windows" ? azurerm_windows_function_app.main[0].identity[0].principal_id : azurerm_linux_function_app.main[0].identity[0].principal_id
}

# Role assignments for Stream Analytics to access services
resource "azurerm_role_assignment" "stream_analytics_cosmos_contributor" {
  scope                = azurerm_cosmosdb_account.main.id
  role_definition_name = "Cosmos DB Built-in Data Contributor"
  principal_id         = azurerm_stream_analytics_job.main.identity[0].principal_id
}

resource "azurerm_role_assignment" "stream_analytics_eventhub_receiver" {
  scope                = azurerm_eventhub_namespace.main.id
  role_definition_name = "Azure Event Hubs Data Receiver"
  principal_id         = azurerm_stream_analytics_job.main.identity[0].principal_id
}

# Diagnostic settings for monitoring (if enabled)
resource "azurerm_monitor_diagnostic_setting" "storage_account" {
  count = var.enable_diagnostic_logs ? 1 : 0
  
  name               = "storage-diagnostics"
  target_resource_id = azurerm_storage_account.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
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
}

resource "azurerm_monitor_diagnostic_setting" "cosmos_db" {
  count = var.enable_diagnostic_logs ? 1 : 0
  
  name               = "cosmos-diagnostics"
  target_resource_id = azurerm_cosmosdb_account.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
  enabled_log {
    category = "DataPlaneRequests"
  }
  
  enabled_log {
    category = "QueryRuntimeStatistics"
  }
  
  enabled_log {
    category = "PartitionKeyStatistics"
  }
  
  metric {
    category = "Requests"
    enabled  = true
  }
}

resource "azurerm_monitor_diagnostic_setting" "event_hub" {
  count = var.enable_diagnostic_logs ? 1 : 0
  
  name               = "eventhub-diagnostics"
  target_resource_id = azurerm_eventhub_namespace.main.id
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

resource "azurerm_monitor_diagnostic_setting" "stream_analytics" {
  count = var.enable_diagnostic_logs ? 1 : 0
  
  name               = "stream-analytics-diagnostics"
  target_resource_id = azurerm_stream_analytics_job.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
  enabled_log {
    category = "Execution"
  }
  
  enabled_log {
    category = "Authoring"
  }
  
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}