# Output Values for Financial Market Data Processing Infrastructure
# This file defines all outputs that provide important information about deployed resources

# Resource Group Information
output "resource_group_name" {
  description = "Name of the created resource group"
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

# Azure Data Explorer Outputs
output "adx_cluster_name" {
  description = "Name of the Azure Data Explorer cluster"
  value       = azurerm_kusto_cluster.main.name
}

output "adx_cluster_uri" {
  description = "URI of the Azure Data Explorer cluster for client connections"
  value       = azurerm_kusto_cluster.main.uri
}

output "adx_cluster_id" {
  description = "ID of the Azure Data Explorer cluster"
  value       = azurerm_kusto_cluster.main.id
}

output "adx_database_name" {
  description = "Name of the Azure Data Explorer database"
  value       = azurerm_kusto_database.main.name
}

output "adx_database_id" {
  description = "ID of the Azure Data Explorer database"
  value       = azurerm_kusto_database.main.id
}

output "adx_cluster_principal_id" {
  description = "Principal ID of the Azure Data Explorer cluster managed identity"
  value       = azurerm_kusto_cluster.main.identity[0].principal_id
}

# Event Hubs Outputs
output "eventhub_namespace_name" {
  description = "Name of the Event Hubs namespace"
  value       = azurerm_eventhub_namespace.main.name
}

output "eventhub_namespace_id" {
  description = "ID of the Event Hubs namespace"
  value       = azurerm_eventhub_namespace.main.id
}

output "eventhub_namespace_connection_string" {
  description = "Primary connection string for Event Hubs namespace"
  value       = azurerm_eventhub_namespace.main.default_primary_connection_string
  sensitive   = true
}

output "market_data_hub_name" {
  description = "Name of the market data Event Hub"
  value       = azurerm_eventhub.market_data.name
}

output "market_data_hub_id" {
  description = "ID of the market data Event Hub"
  value       = azurerm_eventhub.market_data.id
}

output "trading_events_hub_name" {
  description = "Name of the trading events Event Hub"
  value       = azurerm_eventhub.trading_events.name
}

output "trading_events_hub_id" {
  description = "ID of the trading events Event Hub"
  value       = azurerm_eventhub.trading_events.id
}

output "trading_events_consumer_group_name" {
  description = "Name of the trading events consumer group"
  value       = azurerm_eventhub_consumer_group.trading_events.name
}

# Azure Functions Outputs
output "function_app_name" {
  description = "Name of the Function App"
  value       = azurerm_linux_function_app.main.name
}

output "function_app_id" {
  description = "ID of the Function App"
  value       = azurerm_linux_function_app.main.id
}

output "function_app_default_hostname" {
  description = "Default hostname of the Function App"
  value       = azurerm_linux_function_app.main.default_hostname
}

output "function_app_principal_id" {
  description = "Principal ID of the Function App managed identity"
  value       = azurerm_linux_function_app.main.identity[0].principal_id
}

output "function_app_url" {
  description = "URL of the Function App"
  value       = "https://${azurerm_linux_function_app.main.default_hostname}"
}

# Storage Account Outputs
output "storage_account_name" {
  description = "Name of the storage account"
  value       = azurerm_storage_account.main.name
}

output "storage_account_id" {
  description = "ID of the storage account"
  value       = azurerm_storage_account.main.id
}

output "storage_account_primary_access_key" {
  description = "Primary access key for the storage account"
  value       = azurerm_storage_account.main.primary_access_key
  sensitive   = true
}

output "storage_account_primary_blob_endpoint" {
  description = "Primary blob service endpoint for the storage account"
  value       = azurerm_storage_account.main.primary_blob_endpoint
}

output "market_data_archive_container_name" {
  description = "Name of the market data archive container"
  value       = azurerm_storage_container.market_data_archive.name
}

# Event Grid Outputs
output "event_grid_topic_name" {
  description = "Name of the Event Grid topic"
  value       = azurerm_eventgrid_topic.main.name
}

output "event_grid_topic_id" {
  description = "ID of the Event Grid topic"
  value       = azurerm_eventgrid_topic.main.id
}

output "event_grid_topic_endpoint" {
  description = "Endpoint URL for the Event Grid topic"
  value       = azurerm_eventgrid_topic.main.endpoint
}

output "event_grid_topic_primary_access_key" {
  description = "Primary access key for the Event Grid topic"
  value       = azurerm_eventgrid_topic.main.primary_access_key
  sensitive   = true
}

# Application Insights Outputs
output "application_insights_name" {
  description = "Name of the Application Insights instance"
  value       = azurerm_application_insights.main.name
}

output "application_insights_id" {
  description = "ID of the Application Insights instance"
  value       = azurerm_application_insights.main.id
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

output "application_insights_app_id" {
  description = "Application ID for Application Insights"
  value       = azurerm_application_insights.main.app_id
}

# Log Analytics Outputs
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.name
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.id
}

output "log_analytics_workspace_workspace_id" {
  description = "Workspace ID (GUID) of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.workspace_id
}

output "log_analytics_workspace_primary_shared_key" {
  description = "Primary shared key for the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.primary_shared_key
  sensitive   = true
}

# Service Plan Outputs
output "service_plan_name" {
  description = "Name of the App Service Plan"
  value       = azurerm_service_plan.main.name
}

output "service_plan_id" {
  description = "ID of the App Service Plan"
  value       = azurerm_service_plan.main.id
}

# Data Connection Outputs
output "adx_data_connection_name" {
  description = "Name of the ADX data connection"
  value       = azurerm_kusto_eventhub_data_connection.market_data.name
}

output "adx_data_connection_id" {
  description = "ID of the ADX data connection"
  value       = azurerm_kusto_eventhub_data_connection.market_data.id
}

# Generated Random Suffix
output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = local.random_suffix
}

# Connection Information for Client Applications
output "kusto_connection_string" {
  description = "Connection string for KQL queries to Azure Data Explorer"
  value       = "Data Source=${azurerm_kusto_cluster.main.uri};Initial Catalog=${azurerm_kusto_database.main.name};AAD Federated Security=True"
}

output "market_data_ingestion_connection" {
  description = "Event Hub connection string for market data ingestion"
  value = {
    namespace_connection_string = azurerm_eventhub_namespace.main.default_primary_connection_string
    hub_name                   = azurerm_eventhub.market_data.name
    consumer_group             = "$Default"
  }
  sensitive = true
}

output "trading_events_ingestion_connection" {
  description = "Event Hub connection string for trading events ingestion"
  value = {
    namespace_connection_string = azurerm_eventhub_namespace.main.default_primary_connection_string
    hub_name                   = azurerm_eventhub.trading_events.name
    consumer_group             = azurerm_eventhub_consumer_group.trading_events.name
  }
  sensitive = true
}

# Management and Monitoring URLs
output "azure_portal_urls" {
  description = "Azure Portal URLs for key resources"
  value = {
    resource_group              = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_resource_group.main.id}"
    adx_cluster                = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_kusto_cluster.main.id}"
    adx_web_ui                 = "https://dataexplorer.azure.com/clusters/${azurerm_kusto_cluster.main.name}"
    event_hubs_namespace       = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_eventhub_namespace.main.id}"
    function_app               = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_linux_function_app.main.id}"
    event_grid_topic           = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_eventgrid_topic.main.id}"
    application_insights       = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_application_insights.main.id}"
    log_analytics_workspace    = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_log_analytics_workspace.main.id}"
  }
}

# Summary Information
output "deployment_summary" {
  description = "Summary of deployed infrastructure for financial market data processing"
  value = {
    environment                 = var.environment
    project_name               = var.project_name
    location                   = var.location
    resource_group_name        = azurerm_resource_group.main.name
    adx_cluster_name           = azurerm_kusto_cluster.main.name
    adx_database_name          = azurerm_kusto_database.main.name
    eventhub_namespace_name    = azurerm_eventhub_namespace.main.name
    function_app_name          = azurerm_linux_function_app.main.name
    event_grid_topic_name      = azurerm_eventgrid_topic.main.name
    storage_account_name       = azurerm_storage_account.main.name
    estimated_monthly_cost_usd = "$${var.monthly_budget_limit}"
    deployment_timestamp       = timestamp()
  }
}

# KQL Query Examples
output "sample_kql_queries" {
  description = "Sample KQL queries for financial market data analysis"
  value = {
    list_tables = ".show tables"
    recent_market_data = <<-EOT
      MarketDataRaw 
      | where timestamp > ago(1h)
      | summarize avg(price), max(volume) by symbol, bin(timestamp, 5m)
      | order by timestamp desc
    EOT
    
    price_volatility = <<-EOT
      MarketDataRaw
      | where symbol == "AAPL" and timestamp > ago(1d)
      | extend price_change = price - prev(price)
      | extend volatility = abs(price_change) / prev(price) * 100
      | summarize avg_volatility = avg(volatility) by bin(timestamp, 1h)
      | render timechart
    EOT
    
    trading_volume_analysis = <<-EOT
      MarketDataRaw
      | where timestamp > ago(1d)
      | summarize total_volume = sum(volume), 
                  avg_price = avg(price),
                  trade_count = count() by symbol
      | order by total_volume desc
      | take 10
    EOT
  }
}

# Next Steps and Configuration
output "post_deployment_steps" {
  description = "Next steps to complete the setup"
  value = [
    "1. Configure ADX database tables using the provided KQL scripts",
    "2. Deploy Function App code for market data processing",
    "3. Set up Event Grid subscriptions for trading alerts",
    "4. Configure data sources to send events to Event Hubs",
    "5. Test the end-to-end data flow with sample market data",
    "6. Set up monitoring dashboards in Application Insights",
    "7. Configure backup and disaster recovery policies",
    "8. Review and adjust cost management alerts"
  ]
}