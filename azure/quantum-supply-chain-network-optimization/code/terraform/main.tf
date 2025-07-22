# =============================================================================
# Azure Quantum Supply Chain Network Optimization - Main Infrastructure
# =============================================================================

# Generate a random suffix for resource names to ensure uniqueness
resource "random_id" "suffix" {
  byte_length = 3
}

# Create the main resource group
resource "azurerm_resource_group" "main" {
  name     = "rg-quantum-supplychain-${random_id.suffix.hex}"
  location = var.location

  tags = {
    purpose      = "quantum-optimization"
    environment  = var.environment
    project      = "supply-chain-optimization"
    created_by   = "terraform"
  }
}

# =============================================================================
# Storage Account for Azure Functions and general storage
# =============================================================================

resource "azurerm_storage_account" "main" {
  name                     = "stsupplychain${random_id.suffix.hex}"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"

  min_tls_version                = "TLS1_2"
  allow_nested_items_to_be_public = false

  tags = azurerm_resource_group.main.tags
}

# =============================================================================
# Azure Quantum Workspace
# =============================================================================

resource "azurerm_quantum_workspace" "main" {
  name                = "quantum-workspace-${random_id.suffix.hex}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  storage_account_id  = azurerm_storage_account.main.id

  tags = azurerm_resource_group.main.tags
}

# =============================================================================
# Azure Digital Twins Instance
# =============================================================================

resource "azurerm_digital_twins_instance" "main" {
  name                = "dt-supplychain-${random_id.suffix.hex}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  identity {
    type = "SystemAssigned"
  }

  tags = azurerm_resource_group.main.tags
}

# =============================================================================
# Cosmos DB Account for optimization results storage
# =============================================================================

resource "azurerm_cosmosdb_account" "main" {
  name                = "cosmos-supplychain-${random_id.suffix.hex}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  offer_type          = "Standard"
  kind                = "GlobalDocumentDB"

  consistency_policy {
    consistency_level       = "Session"
    max_interval_in_seconds = 300
    max_staleness_prefix    = 100000
  }

  geo_location {
    location          = azurerm_resource_group.main.location
    failover_priority = 0
  }

  capabilities {
    name = "EnableServerless"
  }

  tags = azurerm_resource_group.main.tags
}

# Cosmos DB Database for supply chain data
resource "azurerm_cosmosdb_sql_database" "main" {
  name                = "supply-chain-db"
  resource_group_name = azurerm_resource_group.main.name
  account_name        = azurerm_cosmosdb_account.main.name
}

# Cosmos DB Container for optimization results
resource "azurerm_cosmosdb_sql_container" "optimization_results" {
  name                  = "optimization-results"
  resource_group_name   = azurerm_resource_group.main.name
  account_name          = azurerm_cosmosdb_account.main.name
  database_name         = azurerm_cosmosdb_sql_database.main.name
  partition_key_path    = "/supplier_id"
  partition_key_version = 1
}

# =============================================================================
# Event Hub Namespace and Hub for real-time data ingestion
# =============================================================================

resource "azurerm_eventhub_namespace" "main" {
  name                = "eh-supplychain-${random_id.suffix.hex}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "Standard"
  capacity            = 1

  tags = azurerm_resource_group.main.tags
}

resource "azurerm_eventhub" "supply_chain_events" {
  name                = "supply-chain-events"
  namespace_name      = azurerm_eventhub_namespace.main.name
  resource_group_name = azurerm_resource_group.main.name
  partition_count     = 4
  message_retention   = 1
}

# Event Hub authorization rule for Stream Analytics
resource "azurerm_eventhub_authorization_rule" "stream_analytics" {
  name                = "stream-analytics-rule"
  namespace_name      = azurerm_eventhub_namespace.main.name
  eventhub_name       = azurerm_eventhub.supply_chain_events.name
  resource_group_name = azurerm_resource_group.main.name
  listen              = true
  send                = false
  manage              = false
}

# =============================================================================
# Stream Analytics Job for real-time data processing
# =============================================================================

resource "azurerm_stream_analytics_job" "main" {
  name                                     = "asa-supplychain-${random_id.suffix.hex}"
  resource_group_name                      = azurerm_resource_group.main.name
  location                                 = azurerm_resource_group.main.location
  compatibility_level                      = "1.2"
  data_locale                              = "en-GB"
  events_late_arrival_max_delay_in_seconds = 60
  events_out_of_order_max_delay_in_seconds = 50
  events_out_of_order_policy               = "Adjust"
  output_error_policy                      = "Drop"
  streaming_units                          = 1

  transformation_query = <<QUERY
WITH FilteredEvents AS (
  SELECT
    supplier_id,
    warehouse_id,
    inventory_level,
    location,
    timestamp,
    event_type
  FROM [supply-chain-input]
  WHERE event_type IN ('inventory_update', 'location_change', 'demand_forecast')
),
AggregatedData AS (
  SELECT
    supplier_id,
    warehouse_id,
    AVG(inventory_level) AS avg_inventory,
    MAX(timestamp) AS last_update,
    COUNT(*) AS event_count
  FROM FilteredEvents
  GROUP BY supplier_id, warehouse_id, TumblingWindow(minute, 5)
)
SELECT * INTO [digital-twins-output] FROM AggregatedData;

SELECT * INTO [optimization-trigger] FROM FilteredEvents
WHERE inventory_level < 100 OR event_type = 'demand_forecast';
QUERY

  tags = azurerm_resource_group.main.tags
}

# Stream Analytics Input - Event Hub
resource "azurerm_stream_analytics_stream_input_eventhub" "main" {
  name                         = "supply-chain-input"
  stream_analytics_job_name    = azurerm_stream_analytics_job.main.name
  resource_group_name          = azurerm_resource_group.main.name
  eventhub_consumer_group_name = "$Default"
  eventhub_name                = azurerm_eventhub.supply_chain_events.name
  servicebus_namespace         = azurerm_eventhub_namespace.main.name
  shared_access_policy_key     = azurerm_eventhub_authorization_rule.stream_analytics.primary_key
  shared_access_policy_name    = azurerm_eventhub_authorization_rule.stream_analytics.name

  serialization {
    type     = "Json"
    encoding = "UTF8"
  }
}

# =============================================================================
# Application Insights for monitoring and analytics
# =============================================================================

resource "azurerm_application_insights" "main" {
  name                = "insights-supplychain-${random_id.suffix.hex}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  application_type    = "web"

  tags = azurerm_resource_group.main.tags
}

# =============================================================================
# Log Analytics Workspace for comprehensive monitoring
# =============================================================================

resource "azurerm_log_analytics_workspace" "main" {
  name                = "la-supplychain-${random_id.suffix.hex}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "PerGB2018"
  retention_in_days   = 30

  tags = azurerm_resource_group.main.tags
}

# =============================================================================
# Azure Functions App for quantum optimization orchestration
# =============================================================================

resource "azurerm_service_plan" "main" {
  name                = "asp-optimizer-${random_id.suffix.hex}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  os_type             = "Linux"
  sku_name            = "Y1"

  tags = azurerm_resource_group.main.tags
}

resource "azurerm_linux_function_app" "main" {
  name                = "func-optimizer-${random_id.suffix.hex}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  service_plan_id     = azurerm_service_plan.main.id

  storage_account_name       = azurerm_storage_account.main.name
  storage_account_access_key = azurerm_storage_account.main.primary_access_key

  identity {
    type = "SystemAssigned"
  }

  site_config {
    application_stack {
      python_version = "3.9"
    }

    application_insights_key               = azurerm_application_insights.main.instrumentation_key
    application_insights_connection_string = azurerm_application_insights.main.connection_string
  }

  app_settings = {
    "FUNCTIONS_WORKER_RUNTIME"         = "python"
    "AZURE_QUANTUM_WORKSPACE"          = azurerm_quantum_workspace.main.name
    "AZURE_DIGITAL_TWINS_ENDPOINT"     = "https://${azurerm_digital_twins_instance.main.host_name}"
    "COSMOS_CONNECTION_STRING"         = azurerm_cosmosdb_account.main.connection_strings[0]
    "SUBSCRIPTION_ID"                  = data.azurerm_client_config.current.subscription_id
    "RESOURCE_GROUP"                   = azurerm_resource_group.main.name
    "LOCATION"                         = azurerm_resource_group.main.location
    "APPINSIGHTS_INSTRUMENTATIONKEY"   = azurerm_application_insights.main.instrumentation_key
  }

  tags = azurerm_resource_group.main.tags
}

# =============================================================================
# RBAC Assignments for Function App to access other services
# =============================================================================

# Grant Function App access to Digital Twins
resource "azurerm_role_assignment" "function_to_digital_twins" {
  scope                = azurerm_digital_twins_instance.main.id
  role_definition_name = "Azure Digital Twins Data Owner"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id
}

# Grant Function App access to Quantum Workspace
resource "azurerm_role_assignment" "function_to_quantum" {
  scope                = azurerm_quantum_workspace.main.id
  role_definition_name = "Quantum Workspace Contributor"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id
}

# Grant Function App access to Cosmos DB
resource "azurerm_role_assignment" "function_to_cosmos" {
  scope                = azurerm_cosmosdb_account.main.id
  role_definition_name = "Cosmos DB Account Reader Role"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id
}

# =============================================================================
# Monitoring and Alerts
# =============================================================================

# Action Group for supply chain alerts
resource "azurerm_monitor_action_group" "supply_chain_alerts" {
  name                = "supply-chain-alerts"
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "schalerts"

  email_receiver {
    name          = "admin-email"
    email_address = var.admin_email
  }

  tags = azurerm_resource_group.main.tags
}

# Metric Alert for low inventory levels
resource "azurerm_monitor_metric_alert" "low_inventory" {
  name                = "low-inventory-alert"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_linux_function_app.main.id]
  description         = "Alert when inventory levels are critically low"
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "FunctionExecutionCount"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 5
  }

  action {
    action_group_id = azurerm_monitor_action_group.supply_chain_alerts.id
  }

  tags = azurerm_resource_group.main.tags
}

# =============================================================================
# Diagnostic Settings for comprehensive monitoring
# =============================================================================

resource "azurerm_monitor_diagnostic_setting" "digital_twins" {
  name                       = "dt-diagnostics"
  target_resource_id         = azurerm_digital_twins_instance.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  enabled_log {
    category = "DigitalTwinsOperation"
  }

  enabled_log {
    category = "EventRoutesOperation"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

resource "azurerm_monitor_diagnostic_setting" "function_app" {
  name                       = "func-diagnostics"
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

# =============================================================================
# Data Sources
# =============================================================================

data "azurerm_client_config" "current" {}