# Azure Serverless Graph Analytics Infrastructure
# This Terraform configuration creates a complete serverless graph analytics solution
# using Azure Cosmos DB for Apache Gremlin and Azure Functions

# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Create Resource Group for all graph analytics resources
resource "azurerm_resource_group" "graph_analytics" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags

  lifecycle {
    create_before_destroy = true
  }
}

# Create Application Insights for monitoring and observability
resource "azurerm_application_insights" "graph_analytics" {
  name                = "${var.app_insights_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.graph_analytics.location
  resource_group_name = azurerm_resource_group.graph_analytics.name
  application_type    = "web"
  retention_in_days   = var.log_retention_days
  tags                = var.tags

  lifecycle {
    create_before_destroy = true
  }
}

# Create Log Analytics Workspace for centralized logging
resource "azurerm_log_analytics_workspace" "graph_analytics" {
  count               = var.enable_monitoring ? 1 : 0
  name                = "law-${var.app_insights_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.graph_analytics.location
  resource_group_name = azurerm_resource_group.graph_analytics.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  tags                = var.tags

  lifecycle {
    create_before_destroy = true
  }
}

# Create Azure Cosmos DB Account with Gremlin API
resource "azurerm_cosmosdb_account" "graph_analytics" {
  name                          = "${var.cosmos_account_name}-${random_string.suffix.result}"
  location                      = azurerm_resource_group.graph_analytics.location
  resource_group_name           = azurerm_resource_group.graph_analytics.name
  offer_type                    = "Standard"
  kind                          = "GlobalDocumentDB"
  enable_automatic_failover     = var.cosmos_enable_automatic_failover
  enable_multiple_write_locations = var.cosmos_enable_multiple_write_locations
  
  # Enable Gremlin API capability
  capabilities {
    name = "EnableGremlin"
  }

  # Configure consistency policy for optimal graph query performance
  consistency_policy {
    consistency_level       = var.cosmos_consistency_level
    max_interval_in_seconds = 300
    max_staleness_prefix    = 100000
  }

  # Primary geo location configuration
  geo_location {
    location          = var.location
    failover_priority = 0
  }

  # Enable backup with continuous mode for point-in-time recovery
  backup {
    type                = "Continuous"
    interval_in_minutes = 240
    retention_in_hours  = 8
  }

  tags = var.tags

  lifecycle {
    create_before_destroy = true
    ignore_changes = [
      # Ignore changes to capabilities as they can't be modified after creation
      capabilities
    ]
  }
}

# Create Cosmos DB Gremlin Database
resource "azurerm_cosmosdb_gremlin_database" "graph_analytics" {
  name                = var.cosmos_database_name
  resource_group_name = azurerm_resource_group.graph_analytics.name
  account_name        = azurerm_cosmosdb_account.graph_analytics.name

  # Enable autoscale throughput for cost optimization
  autoscale_settings {
    max_throughput = var.cosmos_throughput * 10
  }

  depends_on = [azurerm_cosmosdb_account.graph_analytics]
}

# Create Cosmos DB Gremlin Graph Container
resource "azurerm_cosmosdb_gremlin_graph" "relationship_graph" {
  name                = var.cosmos_graph_name
  resource_group_name = azurerm_resource_group.graph_analytics.name
  account_name        = azurerm_cosmosdb_account.graph_analytics.name
  database_name       = azurerm_cosmosdb_gremlin_database.graph_analytics.name
  partition_key_path  = "/partitionKey"
  throughput          = var.cosmos_throughput

  # Configure indexing policy for optimal graph query performance
  index_policy {
    automatic      = true
    indexing_mode  = "consistent"
    included_paths = ["/*"]
    excluded_paths = ["/\"_etag\"/?"]
  }

  # Configure conflict resolution for multi-master scenarios
  conflict_resolution_policy {
    mode                     = "LastWriterWins"
    conflict_resolution_path = "/_ts"
  }

  depends_on = [azurerm_cosmosdb_gremlin_database.graph_analytics]
}

# Create Storage Account for Function App
resource "azurerm_storage_account" "function_storage" {
  name                     = "${var.storage_account_name}${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.graph_analytics.name
  location                 = azurerm_resource_group.graph_analytics.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_replication_type
  account_kind             = "StorageV2"
  
  # Enable secure transfer and disable public blob access
  enable_https_traffic_only = true
  allow_nested_items_to_be_public = false
  
  # Configure blob properties for optimal performance
  blob_properties {
    versioning_enabled = true
    delete_retention_policy {
      days = 7
    }
    container_delete_retention_policy {
      days = 7
    }
  }

  tags = var.tags

  lifecycle {
    create_before_destroy = true
  }
}

# Create App Service Plan for Function App (Consumption Plan)
resource "azurerm_service_plan" "function_plan" {
  name                = "plan-${var.function_app_name}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.graph_analytics.name
  location            = azurerm_resource_group.graph_analytics.location
  os_type             = "Linux"
  sku_name            = "Y1" # Consumption plan for serverless execution
  tags                = var.tags

  lifecycle {
    create_before_destroy = true
  }
}

# Create Azure Function App for serverless graph processing
resource "azurerm_linux_function_app" "graph_processor" {
  name                = "${var.function_app_name}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.graph_analytics.name
  location            = azurerm_resource_group.graph_analytics.location
  service_plan_id     = azurerm_service_plan.function_plan.id
  storage_account_name = azurerm_storage_account.function_storage.name
  storage_account_access_key = azurerm_storage_account.function_storage.primary_access_key

  # Configure Function App runtime and version
  site_config {
    application_stack {
      node_version = var.function_runtime_version
    }
    
    # Enable Application Insights integration
    application_insights_key               = azurerm_application_insights.graph_analytics.instrumentation_key
    application_insights_connection_string = azurerm_application_insights.graph_analytics.connection_string
    
    # Configure CORS for web applications
    cors {
      allowed_origins     = ["*"]
      support_credentials = false
    }
    
    # Enable health checks
    health_check_path = "/api/health"
  }

  # Configure application settings for Cosmos DB integration
  app_settings = {
    "FUNCTIONS_WORKER_RUNTIME"              = var.function_runtime
    "WEBSITE_RUN_FROM_PACKAGE"              = "1"
    "COSMOS_ENDPOINT"                       = azurerm_cosmosdb_account.graph_analytics.endpoint
    "COSMOS_KEY"                            = azurerm_cosmosdb_account.graph_analytics.primary_key
    "DATABASE_NAME"                         = azurerm_cosmosdb_gremlin_database.graph_analytics.name
    "GRAPH_NAME"                            = azurerm_cosmosdb_gremlin_graph.relationship_graph.name
    "APPINSIGHTS_INSTRUMENTATIONKEY"        = azurerm_application_insights.graph_analytics.instrumentation_key
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = azurerm_application_insights.graph_analytics.connection_string
    "EVENT_GRID_TOPIC_ENDPOINT"             = azurerm_eventgrid_topic.graph_events.endpoint
    "EVENT_GRID_TOPIC_KEY"                  = azurerm_eventgrid_topic.graph_events.primary_access_key
    "ENABLE_ORYX_BUILD"                     = "true"
    "SCM_DO_BUILD_DURING_DEPLOYMENT"       = "1"
  }

  # Configure authentication and authorization
  auth_settings {
    enabled = false # Set to true in production with appropriate identity provider
  }

  tags = var.tags

  depends_on = [
    azurerm_storage_account.function_storage,
    azurerm_service_plan.function_plan,
    azurerm_application_insights.graph_analytics,
    azurerm_cosmosdb_account.graph_analytics
  ]

  lifecycle {
    create_before_destroy = true
    ignore_changes = [
      # Ignore changes to app settings that may be updated by deployments
      app_settings["WEBSITE_RUN_FROM_PACKAGE"]
    ]
  }
}

# Create Event Grid Topic for event-driven architecture
resource "azurerm_eventgrid_topic" "graph_events" {
  name                = "${var.event_grid_topic_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.graph_analytics.location
  resource_group_name = azurerm_resource_group.graph_analytics.name
  
  # Configure Event Grid advanced features
  input_schema         = "EventGridSchema"
  public_network_access_enabled = true
  local_auth_enabled   = true
  
  # Configure input mapping for custom event schemas
  input_mapping_fields {
    topic      = "topic"
    event_type = "eventType"
  }

  tags = var.tags

  lifecycle {
    create_before_destroy = true
  }
}

# Create Event Grid Subscription for GraphWriter Function
resource "azurerm_eventgrid_event_subscription" "graph_writer_subscription" {
  name  = "graph-writer-subscription"
  scope = azurerm_eventgrid_topic.graph_events.id

  # Configure Azure Function endpoint
  azure_function_endpoint {
    function_id                       = "${azurerm_linux_function_app.graph_processor.id}/functions/GraphWriter"
    max_events_per_batch              = 1
    preferred_batch_size_in_kilobytes = 64
  }

  # Configure event filtering
  included_event_types = ["GraphDataEvent"]
  
  # Configure retry policy for reliable event delivery
  retry_policy {
    max_delivery_attempts = 3
    event_time_to_live    = 1440 # 24 hours
  }

  # Configure dead letter endpoint for failed events
  storage_blob_dead_letter_destination {
    storage_account_id          = azurerm_storage_account.function_storage.id
    storage_blob_container_name = azurerm_storage_container.dead_letter.name
  }

  depends_on = [
    azurerm_linux_function_app.graph_processor,
    azurerm_eventgrid_topic.graph_events,
    azurerm_storage_container.dead_letter
  ]
}

# Create Event Grid Subscription for Analytics Function
resource "azurerm_eventgrid_event_subscription" "analytics_subscription" {
  name  = "analytics-subscription"
  scope = azurerm_eventgrid_topic.graph_events.id

  # Configure Azure Function endpoint
  azure_function_endpoint {
    function_id                       = "${azurerm_linux_function_app.graph_processor.id}/functions/AnalyticsProcessor"
    max_events_per_batch              = 10
    preferred_batch_size_in_kilobytes = 1024
  }

  # Configure event filtering for analytics events
  included_event_types = ["GraphAnalyticsEvent", "GraphDataEvent"]
  
  # Configure subject filtering for specific event types
  subject_filter {
    subject_begins_with = "analytics/"
  }

  # Configure retry policy
  retry_policy {
    max_delivery_attempts = 3
    event_time_to_live    = 1440
  }

  # Configure dead letter endpoint
  storage_blob_dead_letter_destination {
    storage_account_id          = azurerm_storage_account.function_storage.id
    storage_blob_container_name = azurerm_storage_container.dead_letter.name
  }

  depends_on = [
    azurerm_linux_function_app.graph_processor,
    azurerm_eventgrid_topic.graph_events,
    azurerm_storage_container.dead_letter
  ]
}

# Create Storage Container for dead letter queue
resource "azurerm_storage_container" "dead_letter" {
  name                  = "deadletter"
  storage_account_name  = azurerm_storage_account.function_storage.name
  container_access_type = "private"

  depends_on = [azurerm_storage_account.function_storage]
}

# Create Storage Container for function code deployment
resource "azurerm_storage_container" "function_code" {
  name                  = "function-releases"
  storage_account_name  = azurerm_storage_account.function_storage.name
  container_access_type = "private"

  depends_on = [azurerm_storage_account.function_storage]
}

# Configure diagnostic settings for Cosmos DB monitoring
resource "azurerm_monitor_diagnostic_setting" "cosmos_diagnostics" {
  count              = var.enable_monitoring ? 1 : 0
  name               = "cosmos-diagnostics"
  target_resource_id = azurerm_cosmosdb_account.graph_analytics.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.graph_analytics[0].id

  # Enable all relevant log categories for graph analytics
  enabled_log {
    category = "DataPlaneRequests"
  }
  
  enabled_log {
    category = "QueryRuntimeStatistics"
  }
  
  enabled_log {
    category = "PartitionKeyStatistics"
  }
  
  enabled_log {
    category = "PartitionKeyRUConsumption"
  }
  
  enabled_log {
    category = "ControlPlaneRequests"
  }

  # Enable metrics for performance monitoring
  metric {
    category = "Requests"
    enabled  = true
  }

  depends_on = [
    azurerm_cosmosdb_account.graph_analytics,
    azurerm_log_analytics_workspace.graph_analytics
  ]
}

# Configure diagnostic settings for Function App monitoring
resource "azurerm_monitor_diagnostic_setting" "function_diagnostics" {
  count              = var.enable_monitoring ? 1 : 0
  name               = "function-diagnostics"
  target_resource_id = azurerm_linux_function_app.graph_processor.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.graph_analytics[0].id

  # Enable Function App execution logs
  enabled_log {
    category = "FunctionAppLogs"
  }

  # Enable metrics for Function App performance
  metric {
    category = "AllMetrics"
    enabled  = true
  }

  depends_on = [
    azurerm_linux_function_app.graph_processor,
    azurerm_log_analytics_workspace.graph_analytics
  ]
}

# Configure diagnostic settings for Event Grid monitoring
resource "azurerm_monitor_diagnostic_setting" "eventgrid_diagnostics" {
  count              = var.enable_monitoring ? 1 : 0
  name               = "eventgrid-diagnostics"
  target_resource_id = azurerm_eventgrid_topic.graph_events.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.graph_analytics[0].id

  # Enable Event Grid delivery logs
  enabled_log {
    category = "DeliveryFailures"
  }
  
  enabled_log {
    category = "PublishFailures"
  }

  # Enable metrics for Event Grid performance
  metric {
    category = "AllMetrics"
    enabled  = true
  }

  depends_on = [
    azurerm_eventgrid_topic.graph_events,
    azurerm_log_analytics_workspace.graph_analytics
  ]
}

# Create Action Group for alerting (optional)
resource "azurerm_monitor_action_group" "graph_alerts" {
  count               = var.enable_monitoring ? 1 : 0
  name                = "graph-analytics-alerts"
  resource_group_name = azurerm_resource_group.graph_analytics.name
  short_name          = "graphalert"

  # Configure email notification (customize as needed)
  email_receiver {
    name          = "admin"
    email_address = "admin@example.com" # Replace with actual email
  }

  tags = var.tags
}

# Create metric alert for high Cosmos DB RU consumption
resource "azurerm_monitor_metric_alert" "cosmos_ru_alert" {
  count               = var.enable_monitoring ? 1 : 0
  name                = "cosmos-high-ru-consumption"
  resource_group_name = azurerm_resource_group.graph_analytics.name
  scopes              = [azurerm_cosmosdb_account.graph_analytics.id]
  description         = "Alert when Cosmos DB RU consumption is high"
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"

  criteria {
    metric_namespace = "Microsoft.DocumentDB/databaseAccounts"
    metric_name      = "TotalRequestUnits"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = var.cosmos_throughput * 0.8 * 300 # 80% of throughput for 5 minutes
  }

  action {
    action_group_id = azurerm_monitor_action_group.graph_alerts[0].id
  }

  depends_on = [
    azurerm_cosmosdb_account.graph_analytics,
    azurerm_monitor_action_group.graph_alerts
  ]
}

# Create metric alert for Function App errors
resource "azurerm_monitor_metric_alert" "function_error_alert" {
  count               = var.enable_monitoring ? 1 : 0
  name                = "function-app-errors"
  resource_group_name = azurerm_resource_group.graph_analytics.name
  scopes              = [azurerm_linux_function_app.graph_processor.id]
  description         = "Alert when Function App has high error rate"
  severity            = 1
  frequency           = "PT1M"
  window_size         = "PT5M"

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "Http5xx"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 10
  }

  action {
    action_group_id = azurerm_monitor_action_group.graph_alerts[0].id
  }

  depends_on = [
    azurerm_linux_function_app.graph_processor,
    azurerm_monitor_action_group.graph_alerts
  ]
}