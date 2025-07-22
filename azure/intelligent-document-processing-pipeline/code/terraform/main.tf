# Main Terraform Configuration for Real-time Document Processing
# This file creates the complete infrastructure for processing documents in real-time
# using Azure Event Hubs, Cosmos DB for MongoDB, and Azure Functions

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local values for consistent resource naming
locals {
  resource_suffix = random_string.suffix.result
  resource_group_name = var.resource_group_name != null ? var.resource_group_name : "rg-${var.project_name}-${var.environment}-${local.resource_suffix}"
  
  # Resource names with consistent naming convention
  eventhub_namespace_name = "eh-${var.project_name}-${var.environment}-${local.resource_suffix}"
  eventhub_name          = "document-events"
  cosmos_account_name    = "cosmos-${var.project_name}-${var.environment}-${local.resource_suffix}"
  function_app_name      = "func-${var.project_name}-${var.environment}-${local.resource_suffix}"
  storage_account_name   = "st${var.project_name}${var.environment}${local.resource_suffix}"
  ai_document_name       = "ai-${var.project_name}-${var.environment}-${local.resource_suffix}"
  app_insights_name      = "appi-${var.project_name}-${var.environment}-${local.resource_suffix}"
  log_analytics_name     = "log-${var.project_name}-${var.environment}-${local.resource_suffix}"
  
  # Common tags
  common_tags = merge(var.tags, {
    environment = var.environment
    project     = var.project_name
    created_by  = "terraform"
  })
}

# Resource Group
resource "azurerm_resource_group" "main" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.common_tags
}

# Log Analytics Workspace for monitoring
resource "azurerm_log_analytics_workspace" "main" {
  name                = local.log_analytics_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_analytics_retention_in_days
  tags                = local.common_tags
}

# Application Insights for Function App monitoring
resource "azurerm_application_insights" "main" {
  name                = local.app_insights_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = var.application_insights_type
  tags                = local.common_tags
}

# Event Hub Namespace
resource "azurerm_eventhub_namespace" "main" {
  name                = local.eventhub_namespace_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = var.eventhub_namespace_sku
  capacity            = var.eventhub_namespace_capacity
  
  # Enable auto-inflate for Standard and Premium SKUs
  auto_inflate_enabled     = var.eventhub_namespace_sku != "Basic"
  maximum_throughput_units = var.eventhub_namespace_sku != "Basic" ? 20 : null
  
  tags = local.common_tags
}

# Event Hub for document events
resource "azurerm_eventhub" "document_events" {
  name                = local.eventhub_name
  namespace_name      = azurerm_eventhub_namespace.main.name
  resource_group_name = azurerm_resource_group.main.name
  partition_count     = var.eventhub_partition_count
  message_retention   = var.eventhub_message_retention
  
  # Enable capture for long-term storage (optional)
  capture_description {
    enabled  = false
    encoding = "Avro"
  }
}

# Consumer Group for Functions
resource "azurerm_eventhub_consumer_group" "functions" {
  name                = "functions-consumer"
  namespace_name      = azurerm_eventhub_namespace.main.name
  eventhub_name       = azurerm_eventhub.document_events.name
  resource_group_name = azurerm_resource_group.main.name
  user_metadata       = "Consumer group for Azure Functions processing"
}

# Authorization Rule for Functions access
resource "azurerm_eventhub_authorization_rule" "functions" {
  name                = "functions-access"
  namespace_name      = azurerm_eventhub_namespace.main.name
  eventhub_name       = azurerm_eventhub.document_events.name
  resource_group_name = azurerm_resource_group.main.name
  listen              = true
  send                = false
  manage              = false
}

# Cosmos DB Account with MongoDB API
resource "azurerm_cosmosdb_account" "main" {
  name                = local.cosmos_account_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  offer_type          = var.cosmosdb_offer_type
  kind                = "MongoDB"
  
  # MongoDB API configuration
  mongo_server_version = "4.2"
  
  # Enable automatic failover
  enable_automatic_failover         = var.cosmosdb_enable_automatic_failover
  enable_multiple_write_locations   = var.cosmosdb_enable_multiple_write_locations
  
  # Consistency policy
  consistency_policy {
    consistency_level       = var.cosmosdb_consistency_level
    max_interval_in_seconds = 5
    max_staleness_prefix    = 100
  }
  
  # Primary location
  geo_location {
    location          = azurerm_resource_group.main.location
    failover_priority = 0
  }
  
  # Additional capabilities
  capabilities {
    name = "EnableMongo"
  }
  
  capabilities {
    name = "EnableServerless"
  }
  
  # Network access configuration
  public_network_access_enabled = var.enable_public_access
  
  # IP range filter if specified
  dynamic "ip_range_filter" {
    for_each = length(var.allowed_ip_ranges) > 0 ? [1] : []
    content {
      ip_range_filter = join(",", var.allowed_ip_ranges)
    }
  }
  
  tags = local.common_tags
}

# Cosmos DB MongoDB Database
resource "azurerm_cosmosdb_mongo_database" "main" {
  name                = "DocumentProcessingDB"
  resource_group_name = azurerm_resource_group.main.name
  account_name        = azurerm_cosmosdb_account.main.name
}

# Cosmos DB MongoDB Collection
resource "azurerm_cosmosdb_mongo_collection" "documents" {
  name                = "ProcessedDocuments"
  resource_group_name = azurerm_resource_group.main.name
  account_name        = azurerm_cosmosdb_account.main.name
  database_name       = azurerm_cosmosdb_mongo_database.main.name
  
  # Throughput configuration
  throughput = var.cosmosdb_throughput
  
  # Shard key for horizontal scaling
  shard_key = "documentId"
  
  # Default TTL (optional)
  default_ttl_seconds = -1
  
  # Indexes for query optimization
  index {
    keys   = ["documentId"]
    unique = true
  }
  
  index {
    keys   = ["processingDate"]
    unique = false
  }
  
  index {
    keys   = ["metadata.type"]
    unique = false
  }
}

# Storage Account for Function App
resource "azurerm_storage_account" "functions" {
  name                     = local.storage_account_name
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_account_replication_type
  account_kind             = "StorageV2"
  
  # Security configuration
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  
  # Enable blob versioning for better data protection
  versioning_enabled = true
  
  # Enable change feed for audit trail
  change_feed_enabled = true
  
  tags = local.common_tags
}

# AI Document Intelligence Service
resource "azurerm_cognitive_account" "document_intelligence" {
  name                = local.ai_document_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  kind                = "FormRecognizer"
  sku_name            = var.ai_document_sku
  
  # Custom subdomain for enhanced security
  custom_subdomain_name = local.ai_document_name
  
  # Network access configuration
  public_network_access_enabled = var.enable_public_access
  
  # Identity configuration for secure access
  identity {
    type = "SystemAssigned"
  }
  
  tags = local.common_tags
}

# App Service Plan for Function App
resource "azurerm_service_plan" "functions" {
  name                = "plan-${local.function_app_name}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  os_type             = "Linux"
  sku_name            = var.function_app_plan_type == "Consumption" ? "Y1" : "P1v2"
  
  tags = local.common_tags
}

# Function App for document processing
resource "azurerm_linux_function_app" "main" {
  name                = local.function_app_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  service_plan_id     = azurerm_service_plan.functions.id
  
  # Storage account configuration
  storage_account_name       = azurerm_storage_account.functions.name
  storage_account_access_key = azurerm_storage_account.functions.primary_access_key
  
  # Runtime configuration
  site_config {
    always_on = var.function_app_plan_type != "Consumption"
    
    application_stack {
      node_version = var.function_app_runtime_version
    }
    
    # Enable Application Insights
    application_insights_key               = azurerm_application_insights.main.instrumentation_key
    application_insights_connection_string = azurerm_application_insights.main.connection_string
  }
  
  # Application settings
  app_settings = {
    "FUNCTIONS_WORKER_RUNTIME"     = var.function_app_runtime
    "WEBSITE_NODE_DEFAULT_VERSION" = "~${var.function_app_runtime_version}"
    "FUNCTIONS_EXTENSION_VERSION"  = "~4"
    
    # Event Hub connection
    "EventHubConnection" = azurerm_eventhub_authorization_rule.functions.primary_connection_string
    
    # Cosmos DB connection
    "CosmosDBConnection" = azurerm_cosmosdb_account.main.connection_strings[0]
    
    # AI Document Intelligence configuration
    "AIDocumentKey"      = azurerm_cognitive_account.document_intelligence.primary_access_key
    "AIDocumentEndpoint" = azurerm_cognitive_account.document_intelligence.endpoint
    
    # Application Insights
    "APPINSIGHTS_INSTRUMENTATIONKEY" = azurerm_application_insights.main.instrumentation_key
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = azurerm_application_insights.main.connection_string
  }
  
  # Managed identity for secure access
  identity {
    type = "SystemAssigned"
  }
  
  tags = local.common_tags
}

# Diagnostic Settings for Event Hub Namespace
resource "azurerm_monitor_diagnostic_setting" "eventhub" {
  count = var.enable_diagnostic_logs ? 1 : 0
  
  name                       = "eventhub-diagnostics"
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

# Diagnostic Settings for Cosmos DB
resource "azurerm_monitor_diagnostic_setting" "cosmosdb" {
  count = var.enable_diagnostic_logs ? 1 : 0
  
  name                       = "cosmosdb-diagnostics"
  target_resource_id         = azurerm_cosmosdb_account.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
  enabled_log {
    category = "DataPlaneRequests"
  }
  
  enabled_log {
    category = "MongoRequests"
  }
  
  enabled_log {
    category = "QueryRuntimeStatistics"
  }
  
  metric {
    category = "Requests"
    enabled  = true
  }
}

# Diagnostic Settings for Function App
resource "azurerm_monitor_diagnostic_setting" "function_app" {
  count = var.enable_diagnostic_logs ? 1 : 0
  
  name                       = "function-app-diagnostics"
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

# Action Group for monitoring alerts
resource "azurerm_monitor_action_group" "main" {
  count = var.enable_monitoring_alerts ? 1 : 0
  
  name                = "ag-${var.project_name}-${var.environment}"
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "docproc"
  
  # Email notification (configure as needed)
  email_receiver {
    name          = "admin"
    email_address = "admin@example.com"
  }
  
  tags = local.common_tags
}

# Metric Alert for Function App errors
resource "azurerm_monitor_metric_alert" "function_errors" {
  count = var.enable_monitoring_alerts ? 1 : 0
  
  name                = "function-errors-${var.project_name}-${var.environment}"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_linux_function_app.main.id]
  description         = "Alert when function app error rate is high"
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT15M"
  
  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "FunctionExecutionCount"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 10
    
    dimension {
      name     = "status"
      operator = "Include"
      values   = ["4xx", "5xx"]
    }
  }
  
  action {
    action_group_id = azurerm_monitor_action_group.main[0].id
  }
  
  tags = local.common_tags
}

# Metric Alert for Event Hub throttling
resource "azurerm_monitor_metric_alert" "eventhub_throttling" {
  count = var.enable_monitoring_alerts ? 1 : 0
  
  name                = "eventhub-throttling-${var.project_name}-${var.environment}"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_eventhub_namespace.main.id]
  description         = "Alert when Event Hub is being throttled"
  severity            = 1
  frequency           = "PT1M"
  window_size         = "PT5M"
  
  criteria {
    metric_namespace = "Microsoft.EventHub/namespaces"
    metric_name      = "ThrottledRequests"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 0
  }
  
  action {
    action_group_id = azurerm_monitor_action_group.main[0].id
  }
  
  tags = local.common_tags
}

# Metric Alert for Cosmos DB RU consumption
resource "azurerm_monitor_metric_alert" "cosmosdb_ru_consumption" {
  count = var.enable_monitoring_alerts ? 1 : 0
  
  name                = "cosmosdb-ru-consumption-${var.project_name}-${var.environment}"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_cosmosdb_account.main.id]
  description         = "Alert when Cosmos DB RU consumption is high"
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT15M"
  
  criteria {
    metric_namespace = "Microsoft.DocumentDB/databaseAccounts"
    metric_name      = "NormalizedRUConsumption"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 80
  }
  
  action {
    action_group_id = azurerm_monitor_action_group.main[0].id
  }
  
  tags = local.common_tags
}

# Role Assignment for Function App to access Cosmos DB
resource "azurerm_role_assignment" "function_cosmosdb" {
  scope                = azurerm_cosmosdb_account.main.id
  role_definition_name = "DocumentDB Account Contributor"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id
}

# Role Assignment for Function App to access AI Document Intelligence
resource "azurerm_role_assignment" "function_ai_document" {
  scope                = azurerm_cognitive_account.document_intelligence.id
  role_definition_name = "Cognitive Services User"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id
}