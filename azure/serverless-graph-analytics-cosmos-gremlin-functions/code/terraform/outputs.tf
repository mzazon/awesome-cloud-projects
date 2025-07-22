# Outputs for Azure Serverless Graph Analytics Infrastructure
# These outputs provide essential information for connecting to and using the deployed resources

# Resource Group Information
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.graph_analytics.name
}

output "resource_group_location" {
  description = "Location of the resource group"
  value       = azurerm_resource_group.graph_analytics.location
}

# Cosmos DB Outputs
output "cosmos_account_name" {
  description = "Name of the Cosmos DB account"
  value       = azurerm_cosmosdb_account.graph_analytics.name
}

output "cosmos_endpoint" {
  description = "Cosmos DB account endpoint URL"
  value       = azurerm_cosmosdb_account.graph_analytics.endpoint
}

output "cosmos_primary_key" {
  description = "Cosmos DB primary access key"
  value       = azurerm_cosmosdb_account.graph_analytics.primary_key
  sensitive   = true
}

output "cosmos_secondary_key" {
  description = "Cosmos DB secondary access key"
  value       = azurerm_cosmosdb_account.graph_analytics.secondary_key
  sensitive   = true
}

output "cosmos_connection_strings" {
  description = "Cosmos DB connection strings"
  value       = azurerm_cosmosdb_account.graph_analytics.connection_strings
  sensitive   = true
}

output "cosmos_database_name" {
  description = "Name of the Cosmos DB Gremlin database"
  value       = azurerm_cosmosdb_gremlin_database.graph_analytics.name
}

output "cosmos_graph_name" {
  description = "Name of the Cosmos DB Gremlin graph container"
  value       = azurerm_cosmosdb_gremlin_graph.relationship_graph.name
}

output "cosmos_throughput" {
  description = "Provisioned throughput for the graph container"
  value       = azurerm_cosmosdb_gremlin_graph.relationship_graph.throughput
}

# Function App Outputs
output "function_app_name" {
  description = "Name of the Azure Function App"
  value       = azurerm_linux_function_app.graph_processor.name
}

output "function_app_hostname" {
  description = "Hostname of the Function App"
  value       = azurerm_linux_function_app.graph_processor.default_hostname
}

output "function_app_url" {
  description = "URL of the Function App"
  value       = "https://${azurerm_linux_function_app.graph_processor.default_hostname}"
}

output "function_app_id" {
  description = "Resource ID of the Function App"
  value       = azurerm_linux_function_app.graph_processor.id
}

output "function_app_principal_id" {
  description = "Principal ID of the Function App's managed identity"
  value       = azurerm_linux_function_app.graph_processor.identity[0].principal_id
}

# Storage Account Outputs
output "storage_account_name" {
  description = "Name of the storage account"
  value       = azurerm_storage_account.function_storage.name
}

output "storage_account_primary_access_key" {
  description = "Primary access key for the storage account"
  value       = azurerm_storage_account.function_storage.primary_access_key
  sensitive   = true
}

output "storage_account_primary_connection_string" {
  description = "Primary connection string for the storage account"
  value       = azurerm_storage_account.function_storage.primary_connection_string
  sensitive   = true
}

output "storage_account_primary_blob_endpoint" {
  description = "Primary blob endpoint for the storage account"
  value       = azurerm_storage_account.function_storage.primary_blob_endpoint
}

# Event Grid Outputs
output "event_grid_topic_name" {
  description = "Name of the Event Grid topic"
  value       = azurerm_eventgrid_topic.graph_events.name
}

output "event_grid_topic_endpoint" {
  description = "Event Grid topic endpoint URL"
  value       = azurerm_eventgrid_topic.graph_events.endpoint
}

output "event_grid_topic_primary_access_key" {
  description = "Event Grid topic primary access key"
  value       = azurerm_eventgrid_topic.graph_events.primary_access_key
  sensitive   = true
}

output "event_grid_topic_secondary_access_key" {
  description = "Event Grid topic secondary access key"
  value       = azurerm_eventgrid_topic.graph_events.secondary_access_key
  sensitive   = true
}

# Application Insights Outputs
output "application_insights_name" {
  description = "Name of the Application Insights instance"
  value       = azurerm_application_insights.graph_analytics.name
}

output "application_insights_instrumentation_key" {
  description = "Application Insights instrumentation key"
  value       = azurerm_application_insights.graph_analytics.instrumentation_key
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Application Insights connection string"
  value       = azurerm_application_insights.graph_analytics.connection_string
  sensitive   = true
}

output "application_insights_app_id" {
  description = "Application Insights application ID"
  value       = azurerm_application_insights.graph_analytics.app_id
}

# Log Analytics Workspace Outputs (if monitoring is enabled)
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = var.enable_monitoring ? azurerm_log_analytics_workspace.graph_analytics[0].name : null
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace"
  value       = var.enable_monitoring ? azurerm_log_analytics_workspace.graph_analytics[0].id : null
}

output "log_analytics_workspace_primary_shared_key" {
  description = "Primary shared key for the Log Analytics workspace"
  value       = var.enable_monitoring ? azurerm_log_analytics_workspace.graph_analytics[0].primary_shared_key : null
  sensitive   = true
}

# Service Plan Outputs
output "service_plan_name" {
  description = "Name of the App Service Plan"
  value       = azurerm_service_plan.function_plan.name
}

output "service_plan_id" {
  description = "ID of the App Service Plan"
  value       = azurerm_service_plan.function_plan.id
}

# Event Grid Subscription Outputs
output "graph_writer_subscription_name" {
  description = "Name of the GraphWriter Event Grid subscription"
  value       = azurerm_eventgrid_event_subscription.graph_writer_subscription.name
}

output "analytics_subscription_name" {
  description = "Name of the Analytics Event Grid subscription"
  value       = azurerm_eventgrid_event_subscription.analytics_subscription.name
}

# Container Outputs
output "dead_letter_container_name" {
  description = "Name of the dead letter storage container"
  value       = azurerm_storage_container.dead_letter.name
}

output "function_code_container_name" {
  description = "Name of the function code storage container"
  value       = azurerm_storage_container.function_code.name
}

# Random Suffix (useful for referencing in scripts)
output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_string.suffix.result
}

# Quick Connection Information
output "gremlin_connection_info" {
  description = "Connection information for Gremlin API"
  value = {
    endpoint     = azurerm_cosmosdb_account.graph_analytics.endpoint
    database     = azurerm_cosmosdb_gremlin_database.graph_analytics.name
    graph        = azurerm_cosmosdb_gremlin_graph.relationship_graph.name
    port         = 443
    ssl          = true
    gremlin_endpoint = "wss://${replace(azurerm_cosmosdb_account.graph_analytics.endpoint, "https://", "")}:443/gremlin"
  }
}

output "event_publishing_info" {
  description = "Information for publishing events to Event Grid"
  value = {
    topic_endpoint = azurerm_eventgrid_topic.graph_events.endpoint
    topic_name     = azurerm_eventgrid_topic.graph_events.name
    schema         = "EventGridSchema"
    supported_event_types = ["GraphDataEvent", "GraphAnalyticsEvent"]
  }
}

output "monitoring_info" {
  description = "Monitoring and observability endpoints"
  value = {
    application_insights_portal_url = "https://portal.azure.com/#@/resource${azurerm_application_insights.graph_analytics.id}"
    function_app_portal_url         = "https://portal.azure.com/#@/resource${azurerm_linux_function_app.graph_processor.id}"
    cosmos_db_portal_url           = "https://portal.azure.com/#@/resource${azurerm_cosmosdb_account.graph_analytics.id}"
    event_grid_portal_url          = "https://portal.azure.com/#@/resource${azurerm_eventgrid_topic.graph_events.id}"
  }
}

# Sample Environment Variables for Local Development
output "local_development_env_vars" {
  description = "Environment variables for local development and testing"
  value = {
    COSMOS_ENDPOINT                         = azurerm_cosmosdb_account.graph_analytics.endpoint
    DATABASE_NAME                          = azurerm_cosmosdb_gremlin_database.graph_analytics.name
    GRAPH_NAME                             = azurerm_cosmosdb_gremlin_graph.relationship_graph.name
    APPINSIGHTS_INSTRUMENTATIONKEY         = azurerm_application_insights.graph_analytics.instrumentation_key
    APPLICATIONINSIGHTS_CONNECTION_STRING  = azurerm_application_insights.graph_analytics.connection_string
    EVENT_GRID_TOPIC_ENDPOINT              = azurerm_eventgrid_topic.graph_events.endpoint
    AZURE_STORAGE_CONNECTION_STRING        = azurerm_storage_account.function_storage.primary_connection_string
  }
  sensitive = true
}

# Sample Gremlin Queries
output "sample_gremlin_queries" {
  description = "Sample Gremlin queries for testing the graph database"
  value = {
    count_vertices      = "g.V().count()"
    count_edges        = "g.E().count()"
    get_all_person_names = "g.V().hasLabel('person').values('name')"
    find_connections   = "g.V('user1').out().values('name')"
    add_vertex         = "g.addV('person').property('id', 'user1').property('partitionKey', 'user1').property('name', 'Alice').property('age', 30)"
    add_edge           = "g.V('user1').addE('knows').to(g.V('user2'))"
  }
}

# Deployment Summary
output "deployment_summary" {
  description = "Summary of deployed resources and their purposes"
  value = {
    resource_group      = "Container for all graph analytics resources"
    cosmos_db          = "Graph database using Gremlin API for storing vertices and edges"
    function_app       = "Serverless compute for processing graph events and analytics"
    event_grid         = "Event routing and distribution for decoupled architecture"
    storage_account    = "Storage for Function App state and dead letter queue"
    application_insights = "Monitoring and observability for the entire solution"
    log_analytics      = var.enable_monitoring ? "Centralized logging and analytics" : "Not deployed"
    monitoring_alerts  = var.enable_monitoring ? "Automated alerts for system health" : "Not deployed"
  }
}