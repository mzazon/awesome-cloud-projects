# Outputs for Azure Intelligent Financial Trading Signal Analysis Infrastructure
# This file defines the output values that will be displayed after deployment

# Resource Group Information
output "resource_group_name" {
  description = "Name of the resource group containing all resources"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Location of the resource group"
  value       = azurerm_resource_group.main.location
}

output "resource_group_id" {
  description = "ID of the resource group"
  value       = azurerm_resource_group.main.id
}

# Azure AI Services (Cognitive Services) Information
output "ai_services_name" {
  description = "Name of the Azure AI Services account"
  value       = azurerm_cognitive_account.main.name
}

output "ai_services_endpoint" {
  description = "Endpoint URL for Azure AI Services"
  value       = azurerm_cognitive_account.main.endpoint
}

output "ai_services_key" {
  description = "Primary key for Azure AI Services"
  value       = azurerm_cognitive_account.main.primary_access_key
  sensitive   = true
}

output "ai_services_id" {
  description = "ID of the Azure AI Services account"
  value       = azurerm_cognitive_account.main.id
}

# Storage Account Information
output "storage_account_name" {
  description = "Name of the storage account"
  value       = azurerm_storage_account.main.name
}

output "storage_account_primary_key" {
  description = "Primary access key for the storage account"
  value       = azurerm_storage_account.main.primary_access_key
  sensitive   = true
}

output "storage_account_connection_string" {
  description = "Connection string for the storage account"
  value       = azurerm_storage_account.main.primary_connection_string
  sensitive   = true
}

output "storage_account_id" {
  description = "ID of the storage account"
  value       = azurerm_storage_account.main.id
}

output "storage_containers" {
  description = "List of storage containers created"
  value = {
    financial_videos     = azurerm_storage_container.financial_videos.name
    research_documents   = azurerm_storage_container.research_documents.name
    processed_insights   = azurerm_storage_container.processed_insights.name
  }
}

# Event Hubs Information
output "event_hub_namespace_name" {
  description = "Name of the Event Hubs namespace"
  value       = azurerm_eventhub_namespace.main.name
}

output "event_hub_name" {
  description = "Name of the Event Hub"
  value       = azurerm_eventhub.market_data.name
}

output "event_hub_connection_string" {
  description = "Connection string for Event Hubs namespace"
  value       = azurerm_eventhub_namespace.main.default_primary_connection_string
  sensitive   = true
}

output "event_hub_consumer_groups" {
  description = "Consumer groups created for Event Hub"
  value = {
    stream_analytics = azurerm_eventhub_consumer_group.stream_analytics.name
    functions       = azurerm_eventhub_consumer_group.functions.name
  }
}

output "event_hub_id" {
  description = "ID of the Event Hub"
  value       = azurerm_eventhub.market_data.id
}

# Stream Analytics Information
output "stream_analytics_job_name" {
  description = "Name of the Stream Analytics job"
  value       = azurerm_stream_analytics_job.main.name
}

output "stream_analytics_job_id" {
  description = "ID of the Stream Analytics job"
  value       = azurerm_stream_analytics_job.main.id
}

output "stream_analytics_streaming_units" {
  description = "Number of streaming units allocated"
  value       = azurerm_stream_analytics_job.main.streaming_units
}

# Cosmos DB Information
output "cosmos_db_account_name" {
  description = "Name of the Cosmos DB account"
  value       = azurerm_cosmosdb_account.main.name
}

output "cosmos_db_endpoint" {
  description = "Endpoint URL for Cosmos DB"
  value       = azurerm_cosmosdb_account.main.endpoint
}

output "cosmos_db_primary_key" {
  description = "Primary key for Cosmos DB"
  value       = azurerm_cosmosdb_account.main.primary_key
  sensitive   = true
}

output "cosmos_db_connection_strings" {
  description = "Connection strings for Cosmos DB"
  value       = azurerm_cosmosdb_account.main.connection_strings
  sensitive   = true
}

output "cosmos_db_database_name" {
  description = "Name of the Cosmos DB database"
  value       = azurerm_cosmosdb_sql_database.main.name
}

output "cosmos_db_container_name" {
  description = "Name of the Cosmos DB container"
  value       = azurerm_cosmosdb_sql_container.signals.name
}

output "cosmos_db_id" {
  description = "ID of the Cosmos DB account"
  value       = azurerm_cosmosdb_account.main.id
}

# Function App Information
output "function_app_name" {
  description = "Name of the Function App"
  value       = var.function_app_os_type == "Windows" ? azurerm_windows_function_app.main[0].name : azurerm_linux_function_app.main[0].name
}

output "function_app_default_hostname" {
  description = "Default hostname of the Function App"
  value       = var.function_app_os_type == "Windows" ? azurerm_windows_function_app.main[0].default_hostname : azurerm_linux_function_app.main[0].default_hostname
}

output "function_app_id" {
  description = "ID of the Function App"
  value       = var.function_app_os_type == "Windows" ? azurerm_windows_function_app.main[0].id : azurerm_linux_function_app.main[0].id
}

output "function_app_identity" {
  description = "Managed identity of the Function App"
  value = {
    principal_id = var.function_app_os_type == "Windows" ? azurerm_windows_function_app.main[0].identity[0].principal_id : azurerm_linux_function_app.main[0].identity[0].principal_id
    tenant_id    = var.function_app_os_type == "Windows" ? azurerm_windows_function_app.main[0].identity[0].tenant_id : azurerm_linux_function_app.main[0].identity[0].tenant_id
  }
}

output "app_service_plan_name" {
  description = "Name of the App Service Plan"
  value       = azurerm_service_plan.main.name
}

output "app_service_plan_id" {
  description = "ID of the App Service Plan"
  value       = azurerm_service_plan.main.id
}

# Service Bus Information
output "service_bus_namespace_name" {
  description = "Name of the Service Bus namespace"
  value       = azurerm_servicebus_namespace.main.name
}

output "service_bus_connection_string" {
  description = "Connection string for Service Bus namespace"
  value       = azurerm_servicebus_namespace.main.default_primary_connection_string
  sensitive   = true
}

output "service_bus_topic_name" {
  description = "Name of the Service Bus topic"
  value       = azurerm_servicebus_topic.trading_signals.name
}

output "service_bus_subscription_name" {
  description = "Name of the Service Bus subscription"
  value       = azurerm_servicebus_subscription.high_priority.name
}

output "service_bus_id" {
  description = "ID of the Service Bus namespace"
  value       = azurerm_servicebus_namespace.main.id
}

# Monitoring Information
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.name
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.id
}

output "application_insights_name" {
  description = "Name of the Application Insights instance"
  value       = azurerm_application_insights.main.name
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key for Application Insights"
  value       = azurerm_application_insights.main.instrumentation_key
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Connection string for Application Insights"
  value       = azurerm_application_insights.main.connection_string
  sensitive   = true
}

output "application_insights_id" {
  description = "ID of the Application Insights instance"
  value       = azurerm_application_insights.main.id
}

# Network and Security Information
output "resource_unique_suffix" {
  description = "Unique suffix used for resource naming"
  value       = local.unique_suffix
}

output "common_tags" {
  description = "Common tags applied to all resources"
  value       = local.common_tags
}

# Connection Information for Applications
output "connection_info" {
  description = "Connection information for applications"
  value = {
    event_hub = {
      namespace_name      = azurerm_eventhub_namespace.main.name
      hub_name           = azurerm_eventhub.market_data.name
      consumer_group     = azurerm_eventhub_consumer_group.stream_analytics.name
    }
    cosmos_db = {
      account_name    = azurerm_cosmosdb_account.main.name
      database_name   = azurerm_cosmosdb_sql_database.main.name
      container_name  = azurerm_cosmosdb_sql_container.signals.name
    }
    service_bus = {
      namespace_name     = azurerm_servicebus_namespace.main.name
      topic_name        = azurerm_servicebus_topic.trading_signals.name
      subscription_name = azurerm_servicebus_subscription.high_priority.name
    }
    storage = {
      account_name = azurerm_storage_account.main.name
      containers = {
        financial_videos   = azurerm_storage_container.financial_videos.name
        research_documents = azurerm_storage_container.research_documents.name
        processed_insights = azurerm_storage_container.processed_insights.name
      }
    }
  }
}

# Deployment Information
output "deployment_summary" {
  description = "Summary of deployed resources"
  value = {
    resource_group     = azurerm_resource_group.main.name
    location          = azurerm_resource_group.main.location
    ai_services       = azurerm_cognitive_account.main.name
    storage_account   = azurerm_storage_account.main.name
    event_hub         = azurerm_eventhub.market_data.name
    stream_analytics  = azurerm_stream_analytics_job.main.name
    cosmos_db         = azurerm_cosmosdb_account.main.name
    function_app      = var.function_app_os_type == "Windows" ? azurerm_windows_function_app.main[0].name : azurerm_linux_function_app.main[0].name
    service_bus       = azurerm_servicebus_namespace.main.name
    environment       = var.environment
    project_name      = var.project_name
  }
}

# Stream Analytics Query for Reference
output "stream_analytics_query_reference" {
  description = "Reference Stream Analytics query for trading signals"
  value = <<-EOT
    WITH PriceMovements AS (
        SELECT 
            symbol,
            price,
            volume,
            LAG(price, 1) OVER (PARTITION BY symbol ORDER BY EventEnqueuedUtcTime) as prev_price,
            AVG(price) OVER (PARTITION BY symbol ORDER BY EventEnqueuedUtcTime 
                RANGE BETWEEN INTERVAL '5' MINUTE PRECEDING AND CURRENT ROW) as sma_5min,
            STDEV(price) OVER (PARTITION BY symbol ORDER BY EventEnqueuedUtcTime 
                RANGE BETWEEN INTERVAL '5' MINUTE PRECEDING AND CURRENT ROW) as volatility_5min,
            EventEnqueuedUtcTime,
            System.Timestamp() as WindowEnd
        FROM MarketDataInput
    ),
    TradingSignals AS (
        SELECT 
            symbol,
            price,
            volume,
            prev_price,
            sma_5min,
            volatility_5min,
            CASE 
                WHEN price > prev_price * 1.02 AND volume > LAG(volume, 1) OVER (PARTITION BY symbol ORDER BY EventEnqueuedUtcTime) * 1.5 
                THEN 'STRONG_BUY'
                WHEN price > sma_5min * 1.01 AND volatility_5min < 0.02 
                THEN 'BUY'
                WHEN price < prev_price * 0.98 AND volume > LAG(volume, 1) OVER (PARTITION BY symbol ORDER BY EventEnqueuedUtcTime) * 1.5 
                THEN 'STRONG_SELL'
                WHEN price < sma_5min * 0.99 
                THEN 'SELL'
                ELSE 'HOLD'
            END as signal,
            (price - prev_price) / prev_price * 100 as price_change_pct,
            volatility_5min as risk_score,
            WindowEnd as signal_timestamp
        FROM PriceMovements
        WHERE prev_price IS NOT NULL
    )
    SELECT * INTO SignalOutput FROM TradingSignals
    WHERE signal IN ('STRONG_BUY', 'BUY', 'STRONG_SELL', 'SELL')
  EOT
}

# Next Steps Information
output "next_steps" {
  description = "Next steps for completing the deployment"
  value = {
    stream_analytics_query = "Deploy the Stream Analytics query using the Azure portal or CLI"
    function_code = "Deploy the Function App code for content processing"
    test_data = "Send test market data to Event Hub for validation"
    monitoring = "Configure alerts and dashboards in Application Insights"
    security = "Review and configure additional security settings if needed"
  }
}