# Output Values for Real-time Document Processing Infrastructure
# These outputs provide important information about the deployed resources

# Resource Group Information
output "resource_group_name" {
  description = "Name of the resource group containing all resources"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Location of the resource group"
  value       = azurerm_resource_group.main.location
}

# Event Hub Outputs
output "eventhub_namespace_name" {
  description = "Name of the Event Hub namespace"
  value       = azurerm_eventhub_namespace.main.name
}

output "eventhub_name" {
  description = "Name of the Event Hub for document events"
  value       = azurerm_eventhub.document_events.name
}

output "eventhub_connection_string" {
  description = "Connection string for Event Hub (sensitive)"
  value       = azurerm_eventhub_authorization_rule.functions.primary_connection_string
  sensitive   = true
}

output "eventhub_namespace_endpoint" {
  description = "HTTPS endpoint of the Event Hub namespace"
  value       = "https://${azurerm_eventhub_namespace.main.name}.servicebus.windows.net/"
}

output "eventhub_consumer_group_name" {
  description = "Name of the consumer group for Functions"
  value       = azurerm_eventhub_consumer_group.functions.name
}

# Cosmos DB Outputs
output "cosmosdb_account_name" {
  description = "Name of the Cosmos DB account"
  value       = azurerm_cosmosdb_account.main.name
}

output "cosmosdb_endpoint" {
  description = "Endpoint URL of the Cosmos DB account"
  value       = azurerm_cosmosdb_account.main.endpoint
}

output "cosmosdb_connection_string" {
  description = "MongoDB connection string for Cosmos DB (sensitive)"
  value       = azurerm_cosmosdb_account.main.connection_strings[0]
  sensitive   = true
}

output "cosmosdb_database_name" {
  description = "Name of the MongoDB database"
  value       = azurerm_cosmosdb_mongo_database.main.name
}

output "cosmosdb_collection_name" {
  description = "Name of the MongoDB collection"
  value       = azurerm_cosmosdb_mongo_collection.documents.name
}

output "cosmosdb_primary_key" {
  description = "Primary key for Cosmos DB account (sensitive)"
  value       = azurerm_cosmosdb_account.main.primary_key
  sensitive   = true
}

# AI Document Intelligence Outputs
output "ai_document_service_name" {
  description = "Name of the AI Document Intelligence service"
  value       = azurerm_cognitive_account.document_intelligence.name
}

output "ai_document_endpoint" {
  description = "Endpoint URL of the AI Document Intelligence service"
  value       = azurerm_cognitive_account.document_intelligence.endpoint
}

output "ai_document_key" {
  description = "Primary key for AI Document Intelligence service (sensitive)"
  value       = azurerm_cognitive_account.document_intelligence.primary_access_key
  sensitive   = true
}

# Function App Outputs
output "function_app_name" {
  description = "Name of the Function App"
  value       = azurerm_linux_function_app.main.name
}

output "function_app_hostname" {
  description = "Hostname of the Function App"
  value       = azurerm_linux_function_app.main.default_hostname
}

output "function_app_url" {
  description = "URL of the Function App"
  value       = "https://${azurerm_linux_function_app.main.default_hostname}"
}

output "function_app_principal_id" {
  description = "Principal ID of the Function App managed identity"
  value       = azurerm_linux_function_app.main.identity[0].principal_id
}

output "function_app_identity_tenant_id" {
  description = "Tenant ID of the Function App managed identity"
  value       = azurerm_linux_function_app.main.identity[0].tenant_id
}

# Storage Account Outputs
output "storage_account_name" {
  description = "Name of the storage account for Function App"
  value       = azurerm_storage_account.functions.name
}

output "storage_account_primary_endpoint" {
  description = "Primary blob endpoint of the storage account"
  value       = azurerm_storage_account.functions.primary_blob_endpoint
}

output "storage_account_primary_connection_string" {
  description = "Primary connection string of the storage account (sensitive)"
  value       = azurerm_storage_account.functions.primary_connection_string
  sensitive   = true
}

# Monitoring Outputs
output "application_insights_name" {
  description = "Name of the Application Insights resource"
  value       = azurerm_application_insights.main.name
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key for Application Insights (sensitive)"
  value       = azurerm_application_insights.main.instrumentation_key
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Connection string for Application Insights (sensitive)"
  value       = azurerm_application_insights.main.connection_string
  sensitive   = true
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.id
}

output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.name
}

# Service Plan Output
output "service_plan_id" {
  description = "ID of the App Service Plan"
  value       = azurerm_service_plan.functions.id
}

output "service_plan_name" {
  description = "Name of the App Service Plan"
  value       = azurerm_service_plan.functions.name
}

# Security and Configuration Outputs
output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_string.suffix.result
}

output "deployment_configuration" {
  description = "Deployment configuration summary"
  value = {
    environment                = var.environment
    location                  = var.location
    project_name              = var.project_name
    eventhub_partition_count  = var.eventhub_partition_count
    cosmosdb_throughput       = var.cosmosdb_throughput
    function_app_runtime      = var.function_app_runtime
    function_app_runtime_version = var.function_app_runtime_version
    ai_document_sku           = var.ai_document_sku
    enable_diagnostic_logs    = var.enable_diagnostic_logs
    enable_monitoring_alerts  = var.enable_monitoring_alerts
  }
}

# Testing and Validation Outputs
output "test_event_hub_command" {
  description = "Azure CLI command to send test message to Event Hub"
  value = "az eventhubs eventhub send --resource-group ${azurerm_resource_group.main.name} --namespace-name ${azurerm_eventhub_namespace.main.name} --name ${azurerm_eventhub.document_events.name} --body '{\"documentId\":\"test-doc-001\",\"documentUrl\":\"https://example.com/sample.pdf\",\"metadata\":{\"type\":\"invoice\"}}'"
}

output "cosmosdb_connection_command" {
  description = "MongoDB connection command for testing"
  value = "mongosh '${azurerm_cosmosdb_account.main.connection_strings[0]}'"
  sensitive = true
}

output "function_app_logs_command" {
  description = "Azure CLI command to view Function App logs"
  value = "az webapp log tail --resource-group ${azurerm_resource_group.main.name} --name ${azurerm_linux_function_app.main.name}"
}

# Monitoring and Alerting Outputs
output "monitoring_dashboard_url" {
  description = "URL to the Azure portal monitoring dashboard"
  value = "https://portal.azure.com/#@/resource${azurerm_resource_group.main.id}/overview"
}

output "application_insights_url" {
  description = "URL to Application Insights in Azure portal"
  value = "https://portal.azure.com/#@/resource${azurerm_application_insights.main.id}/overview"
}

output "log_analytics_url" {
  description = "URL to Log Analytics workspace in Azure portal"
  value = "https://portal.azure.com/#@/resource${azurerm_log_analytics_workspace.main.id}/overview"
}

# Cost Estimation Outputs
output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown (USD)"
  value = {
    event_hub_standard     = "~$10-50 (depends on throughput units)"
    cosmos_db_400_ru      = "~$25-35 (400 RU/s)"
    function_app_consumption = "~$0-10 (pay per execution)"
    ai_document_intelligence = "~$1-3 per 1000 documents"
    storage_account       = "~$1-5 (depends on usage)"
    application_insights  = "~$2-10 (depends on data volume)"
    total_estimate       = "~$40-115 per month"
  }
}

# Important Notes
output "important_notes" {
  description = "Important notes and next steps"
  value = {
    note1 = "Deploy Function App code after infrastructure is created"
    note2 = "Configure monitoring alerts email addresses in the Action Group"
    note3 = "Review and adjust throughput settings based on actual usage"
    note4 = "Enable private endpoints for production environments"
    note5 = "Set up proper backup and disaster recovery procedures"
  }
}