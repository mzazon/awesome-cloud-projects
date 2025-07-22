# Main Terraform configuration for Azure Real-Time Fraud Detection Pipeline
# This configuration deploys a complete fraud detection solution using:
# - Azure Event Hubs for data ingestion
# - Azure Stream Analytics for real-time processing
# - Azure Machine Learning for fraud detection models
# - Azure Functions for alert processing
# - Azure Cosmos DB for data storage

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = var.random_suffix_length
  special = false
  upper   = false
}

# Local values for consistent resource naming and tagging
locals {
  # Naming convention: {service}-{project}-{suffix}
  resource_suffix = random_string.suffix.result
  
  # Common tags applied to all resources
  common_tags = merge({
    Environment   = var.environment
    Project      = var.project_name
    ManagedBy    = "Terraform"
    Purpose      = "fraud-detection"
    DeployedDate = timestamp()
  }, var.cost_center != "" ? { CostCenter = var.cost_center } : {},
     var.owner != "" ? { Owner = var.owner } : {},
     var.additional_tags)
  
  # Resource names with consistent naming convention
  resource_group_name        = "${var.resource_group_name}-${local.resource_suffix}"
  event_hub_namespace_name   = "eh-fraud-${local.resource_suffix}"
  event_hub_name            = "transactions"
  stream_analytics_job_name = "asa-fraud-detection-${local.resource_suffix}"
  ml_workspace_name         = "ml-fraud-${local.resource_suffix}"
  function_app_name         = "func-fraud-alerts-${local.resource_suffix}"
  cosmosdb_account_name     = "cosmos-fraud-${local.resource_suffix}"
  storage_account_name      = "stfraud${local.resource_suffix}"
  app_insights_name         = "ai-fraud-${local.resource_suffix}"
  log_analytics_name        = "law-fraud-${local.resource_suffix}"
}

#
# Resource Group
#
resource "azurerm_resource_group" "fraud_detection" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.common_tags
}

#
# Storage Account for Function App and ML Workspace
#
resource "azurerm_storage_account" "fraud_storage" {
  name                     = local.storage_account_name
  resource_group_name      = azurerm_resource_group.fraud_detection.name
  location                 = azurerm_resource_group.fraud_detection.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_account_replication_type
  account_kind             = "StorageV2"
  
  # Security settings
  min_tls_version                = "TLS1_2"
  allow_nested_items_to_be_public = false
  
  # Network access rules
  dynamic "network_rules" {
    for_each = length(var.allowed_ip_ranges) > 0 ? [1] : []
    content {
      default_action             = "Deny"
      ip_rules                  = var.allowed_ip_ranges
      virtual_network_subnet_ids = []
    }
  }
  
  tags = local.common_tags
}

#
# Log Analytics Workspace for monitoring and diagnostics
#
resource "azurerm_log_analytics_workspace" "fraud_logs" {
  count               = var.enable_log_analytics ? 1 : 0
  name                = local.log_analytics_name
  resource_group_name = azurerm_resource_group.fraud_detection.name
  location            = azurerm_resource_group.fraud_detection.location
  sku                 = "PerGB2018"
  retention_in_days   = var.log_analytics_retention_days
  
  tags = local.common_tags
}

#
# Application Insights for application monitoring
#
resource "azurerm_application_insights" "fraud_insights" {
  count               = var.enable_application_insights ? 1 : 0
  name                = local.app_insights_name
  resource_group_name = azurerm_resource_group.fraud_detection.name
  location            = azurerm_resource_group.fraud_detection.location
  application_type    = "web"
  workspace_id        = var.enable_log_analytics ? azurerm_log_analytics_workspace.fraud_logs[0].id : null
  
  tags = local.common_tags
}

#
# Event Hubs Namespace for transaction data ingestion
#
resource "azurerm_eventhub_namespace" "fraud_events" {
  name                     = local.event_hub_namespace_name
  resource_group_name      = azurerm_resource_group.fraud_detection.name
  location                 = azurerm_resource_group.fraud_detection.location
  sku                      = var.eventhub_namespace_sku
  capacity                 = var.eventhub_namespace_sku == "Premium" ? 1 : null
  auto_inflate_enabled     = false
  maximum_throughput_units = var.eventhub_max_throughput_units
  
  tags = local.common_tags
}

#
# Event Hub for transaction streams
#
resource "azurerm_eventhub" "transactions" {
  name                = local.event_hub_name
  namespace_name      = azurerm_eventhub_namespace.fraud_events.name
  resource_group_name = azurerm_resource_group.fraud_detection.name
  partition_count     = var.eventhub_partition_count
  message_retention   = var.eventhub_message_retention
  
  # Enable capture for long-term storage if needed
  capture_description {
    enabled             = false
    encoding            = "Avro"
    interval_in_seconds = 60
    size_limit_in_bytes = 314572800
    
    destination {
      name                = "EventHubArchive.AzureBlockBlob"
      archive_name_format = "{Namespace}/{EventHub}/{PartitionId}/{Year}/{Month}/{Day}/{Hour}/{Minute}/{Second}"
      blob_container_name = "eventhub-capture"
      storage_account_id  = azurerm_storage_account.fraud_storage.id
    }
  }
}

#
# Event Hub Authorization Rule for Stream Analytics
#
resource "azurerm_eventhub_authorization_rule" "stream_analytics_access" {
  name                = "StreamAnalyticsAccess"
  namespace_name      = azurerm_eventhub_namespace.fraud_events.name
  eventhub_name       = azurerm_eventhub.transactions.name
  resource_group_name = azurerm_resource_group.fraud_detection.name
  listen              = true
  send                = true
  manage              = false
}

#
# Cosmos DB Account for storing transaction data and fraud alerts
#
resource "azurerm_cosmosdb_account" "fraud_cosmos" {
  name                = local.cosmosdb_account_name
  resource_group_name = azurerm_resource_group.fraud_detection.name
  location            = azurerm_resource_group.fraud_detection.location
  offer_type          = "Standard"
  kind                = "GlobalDocumentDB"
  
  # Consistency policy
  consistency_policy {
    consistency_level       = var.cosmosdb_consistency_level
    max_interval_in_seconds = var.cosmosdb_consistency_level == "BoundedStaleness" ? 86400 : null
    max_staleness_prefix    = var.cosmosdb_consistency_level == "BoundedStaleness" ? 300000 : null
  }
  
  # Geo-redundancy settings
  enable_automatic_failover         = var.cosmosdb_enable_automatic_failover
  enable_multiple_write_locations   = var.cosmosdb_enable_multiple_write_locations
  
  # Primary region
  geo_location {
    location          = azurerm_resource_group.fraud_detection.location
    failover_priority = 0
  }
  
  # Backup configuration
  backup {
    type                = "Periodic"
    interval_in_minutes = 240
    retention_in_hours  = 8
  }
  
  tags = local.common_tags
}

#
# Cosmos DB SQL Database for fraud detection
#
resource "azurerm_cosmosdb_sql_database" "fraud_database" {
  name                = "fraud-detection"
  resource_group_name = azurerm_cosmosdb_account.fraud_cosmos.resource_group_name
  account_name        = azurerm_cosmosdb_account.fraud_cosmos.name
}

#
# Cosmos DB Container for transactions
#
resource "azurerm_cosmosdb_sql_container" "transactions" {
  name                = "transactions"
  resource_group_name = azurerm_cosmosdb_account.fraud_cosmos.resource_group_name
  account_name        = azurerm_cosmosdb_account.fraud_cosmos.name
  database_name       = azurerm_cosmosdb_sql_database.fraud_database.name
  partition_key_path  = "/transactionId"
  throughput          = var.cosmosdb_throughput
  
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
  
  # TTL for automatic cleanup of old transactions
  default_ttl = 2592000 # 30 days
}

#
# Cosmos DB Container for fraud alerts
#
resource "azurerm_cosmosdb_sql_container" "fraud_alerts" {
  name                = "fraud-alerts"
  resource_group_name = azurerm_cosmosdb_account.fraud_cosmos.resource_group_name
  account_name        = azurerm_cosmosdb_account.fraud_cosmos.name
  database_name       = azurerm_cosmosdb_sql_database.fraud_database.name
  partition_key_path  = "/alertId"
  throughput          = var.cosmosdb_throughput
  
  # Indexing policy optimized for alert queries
  indexing_policy {
    indexing_mode = "consistent"
    
    included_path {
      path = "/*"
    }
    
    # Composite indexes for common query patterns
    composite_index {
      index {
        path  = "/timestamp"
        order = "descending"
      }
      index {
        path  = "/fraudScore"
        order = "descending"
      }
    }
  }
  
  # TTL for alert retention (1 year)
  default_ttl = 31536000
}

#
# Azure Machine Learning Workspace for fraud detection models
#
resource "azurerm_machine_learning_workspace" "fraud_ml" {
  name                    = local.ml_workspace_name
  resource_group_name     = azurerm_resource_group.fraud_detection.name
  location                = azurerm_resource_group.fraud_detection.location
  storage_account_id      = azurerm_storage_account.fraud_storage.id
  application_insights_id = var.enable_application_insights ? azurerm_application_insights.fraud_insights[0].id : null
  
  # Identity configuration for secure access
  identity {
    type = "SystemAssigned"
  }
  
  # High business impact for enhanced security
  high_business_impact = false
  
  tags = local.common_tags
}

#
# ML Compute Instance for model development
#
resource "azurerm_machine_learning_compute_instance" "fraud_compute" {
  name                          = "fraud-compute"
  machine_learning_workspace_id = azurerm_machine_learning_workspace.fraud_ml.id
  virtual_machine_size          = var.ml_compute_instance_size
  
  # Assign access to specific users if needed
  authorization_type = "personal"
  
  tags = local.common_tags
}

#
# Service Plan for Function App
#
resource "azurerm_service_plan" "fraud_functions" {
  name                = "asp-fraud-${local.resource_suffix}"
  resource_group_name = azurerm_resource_group.fraud_detection.name
  location            = azurerm_resource_group.fraud_detection.location
  os_type             = "Linux"
  sku_name            = var.function_app_service_plan_sku
  
  tags = local.common_tags
}

#
# Function App for fraud alert processing
#
resource "azurerm_linux_function_app" "fraud_alerts" {
  name                = local.function_app_name
  resource_group_name = azurerm_resource_group.fraud_detection.name
  location            = azurerm_resource_group.fraud_detection.location
  service_plan_id     = azurerm_service_plan.fraud_functions.id
  
  storage_account_name       = azurerm_storage_account.fraud_storage.name
  storage_account_access_key = azurerm_storage_account.fraud_storage.primary_access_key
  
  # Function runtime configuration
  site_config {
    application_stack {
      node_version = "18"
    }
    
    # CORS configuration for development
    cors {
      allowed_origins = ["*"]
    }
  }
  
  # Application settings including connection strings
  app_settings = merge({
    "FUNCTIONS_WORKER_RUNTIME"       = "node"
    "WEBSITE_NODE_DEFAULT_VERSION"   = "~18"
    "FUNCTIONS_EXTENSION_VERSION"    = var.function_app_runtime_version
    "CosmosDBConnectionString"       = azurerm_cosmosdb_account.fraud_cosmos.connection_strings[0]
    "APPINSIGHTS_INSTRUMENTATIONKEY" = var.enable_application_insights ? azurerm_application_insights.fraud_insights[0].instrumentation_key : ""
  }, var.enable_application_insights ? {
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = azurerm_application_insights.fraud_insights[0].connection_string
  } : {})
  
  # Identity for secure access to other Azure services
  identity {
    type = "SystemAssigned"
  }
  
  tags = local.common_tags
}

#
# Stream Analytics Job for real-time fraud detection
#
resource "azurerm_stream_analytics_job" "fraud_detection" {
  name                                     = local.stream_analytics_job_name
  resource_group_name                      = azurerm_resource_group.fraud_detection.name
  location                                 = azurerm_resource_group.fraud_detection.location
  compatibility_level                      = var.stream_analytics_compatibility_level
  data_locale                             = "en-US"
  events_late_arrival_max_delay_in_seconds = 60
  events_out_of_order_max_delay_in_seconds = 50
  events_out_of_order_policy              = "Adjust"
  output_error_policy                     = "Drop"
  streaming_units                         = var.stream_analytics_streaming_units
  
  # Transformation query for fraud detection
  transformation_query = <<QUERY
WITH TransactionAnalysis AS (
    SELECT
        transactionId,
        userId,
        amount,
        merchantId,
        location,
        timestamp,
        -- Calculate rolling averages for comparison
        AVG(amount) OVER (
            PARTITION BY userId 
            ORDER BY timestamp ASC
            RANGE INTERVAL '24' HOUR PRECEDING
        ) as avg_daily_amount,
        COUNT(*) OVER (
            PARTITION BY userId 
            ORDER BY timestamp ASC
            RANGE INTERVAL '1' HOUR PRECEDING
        ) as hourly_transaction_count,
        -- Detect velocity patterns
        COUNT(*) OVER (
            PARTITION BY userId 
            ORDER BY timestamp ASC
            RANGE INTERVAL '10' MINUTE PRECEDING
        ) as velocity_count
    FROM [TransactionInput]
),

FraudScoring AS (
    SELECT
        *,
        CASE 
            WHEN amount > (avg_daily_amount * 10) THEN 50
            WHEN hourly_transaction_count > 20 THEN 40
            WHEN velocity_count > 5 THEN 60
            ELSE 0
        END as fraud_score,
        CASE 
            WHEN amount > (avg_daily_amount * 10) THEN 'UNUSUAL_AMOUNT'
            WHEN hourly_transaction_count > 20 THEN 'HIGH_FREQUENCY'
            WHEN velocity_count > 5 THEN 'RAPID_FIRE'
            ELSE 'NORMAL'
        END as fraud_reason
    FROM TransactionAnalysis
)

-- Store all transactions
SELECT * INTO [TransactionOutput] FROM FraudScoring;

-- Send high-risk transactions to alert system
SELECT 
    transactionId,
    userId,
    amount,
    merchantId,
    location,
    fraud_score,
    fraud_reason,
    timestamp
INTO [AlertOutput] 
FROM FraudScoring
WHERE fraud_score > 30;
QUERY
  
  tags = local.common_tags
}

#
# Stream Analytics Input - Event Hub
#
resource "azurerm_stream_analytics_stream_input_eventhub" "transaction_input" {
  name                         = "TransactionInput"
  stream_analytics_job_name    = azurerm_stream_analytics_job.fraud_detection.name
  resource_group_name          = azurerm_resource_group.fraud_detection.name
  eventhub_consumer_group_name = "$Default"
  eventhub_name                = azurerm_eventhub.transactions.name
  servicebus_namespace         = azurerm_eventhub_namespace.fraud_events.name
  shared_access_policy_key     = azurerm_eventhub_authorization_rule.stream_analytics_access.primary_key
  shared_access_policy_name    = azurerm_eventhub_authorization_rule.stream_analytics_access.name
  
  serialization {
    type     = "Json"
    encoding = "UTF8"
  }
}

#
# Stream Analytics Output - Cosmos DB for transactions
#
resource "azurerm_stream_analytics_output_cosmosdb" "transaction_output" {
  name                    = "TransactionOutput"
  stream_analytics_job_name = azurerm_stream_analytics_job.fraud_detection.name
  resource_group_name     = azurerm_resource_group.fraud_detection.name
  cosmosdb_account_key    = azurerm_cosmosdb_account.fraud_cosmos.primary_key
  cosmosdb_sql_database_id = azurerm_cosmosdb_sql_database.fraud_database.id
  container_name          = azurerm_cosmosdb_sql_container.transactions.name
  document_id             = "transactionId"
}

#
# Stream Analytics Output - Function App for alerts
#
resource "azurerm_stream_analytics_output_function" "alert_output" {
  name                      = "AlertOutput"
  stream_analytics_job_name = azurerm_stream_analytics_job.fraud_detection.name
  resource_group_name       = azurerm_resource_group.fraud_detection.name
  function_app              = azurerm_linux_function_app.fraud_alerts.name
  function_name             = "ProcessFraudAlert"
  api_key                   = azurerm_linux_function_app.fraud_alerts.default_hostname
  max_batch_count           = 100
  max_batch_size            = 262144
}

#
# Role Assignments for secure access between services
#

# Grant Function App access to Cosmos DB
resource "azurerm_cosmosdb_sql_role_assignment" "function_cosmos_access" {
  resource_group_name = azurerm_resource_group.fraud_detection.name
  account_name        = azurerm_cosmosdb_account.fraud_cosmos.name
  role_definition_id  = "${azurerm_cosmosdb_account.fraud_cosmos.id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002" # Built-in Data Contributor role
  principal_id        = azurerm_linux_function_app.fraud_alerts.identity[0].principal_id
  scope               = azurerm_cosmosdb_account.fraud_cosmos.id
}

# Grant ML Workspace access to storage account
resource "azurerm_role_assignment" "ml_storage_access" {
  scope                = azurerm_storage_account.fraud_storage.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_machine_learning_workspace.fraud_ml.identity[0].principal_id
}

#
# Diagnostic Settings for monitoring (if Log Analytics is enabled)
#
resource "azurerm_monitor_diagnostic_setting" "eventhub_diagnostics" {
  count              = var.enable_log_analytics ? 1 : 0
  name               = "eventhub-diagnostics"
  target_resource_id = azurerm_eventhub_namespace.fraud_events.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.fraud_logs[0].id
  
  enabled_log {
    category = "ArchiveLogs"
  }
  
  enabled_log {
    category = "OperationalLogs"
  }
  
  metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_diagnostic_setting" "stream_analytics_diagnostics" {
  count              = var.enable_log_analytics ? 1 : 0
  name               = "stream-analytics-diagnostics"
  target_resource_id = azurerm_stream_analytics_job.fraud_detection.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.fraud_logs[0].id
  
  enabled_log {
    category = "Execution"
  }
  
  enabled_log {
    category = "Authoring"
  }
  
  metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_diagnostic_setting" "function_app_diagnostics" {
  count              = var.enable_log_analytics ? 1 : 0
  name               = "function-app-diagnostics"
  target_resource_id = azurerm_linux_function_app.fraud_alerts.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.fraud_logs[0].id
  
  enabled_log {
    category = "FunctionAppLogs"
  }
  
  metric {
    category = "AllMetrics"
  }
}