# Outputs for Azure Real-Time Fraud Detection Pipeline

# Resource Group Information
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.fraud_detection.name
}

output "resource_group_id" {
  description = "ID of the created resource group"
  value       = azurerm_resource_group.fraud_detection.id
}

output "location" {
  description = "Azure region where resources are deployed"
  value       = azurerm_resource_group.fraud_detection.location
}

# Event Hubs Information
output "eventhub_namespace_name" {
  description = "Name of the Event Hubs namespace"
  value       = azurerm_eventhub_namespace.fraud_events.name
}

output "eventhub_namespace_id" {
  description = "ID of the Event Hubs namespace"
  value       = azurerm_eventhub_namespace.fraud_events.id
}

output "eventhub_name" {
  description = "Name of the transactions Event Hub"
  value       = azurerm_eventhub.transactions.name
}

output "eventhub_connection_string" {
  description = "Connection string for the Event Hub (sensitive)"
  value       = azurerm_eventhub_authorization_rule.stream_analytics_access.primary_connection_string
  sensitive   = true
}

output "eventhub_primary_key" {
  description = "Primary key for Event Hub access (sensitive)"
  value       = azurerm_eventhub_authorization_rule.stream_analytics_access.primary_key
  sensitive   = true
}

# Stream Analytics Information
output "stream_analytics_job_name" {
  description = "Name of the Stream Analytics job"
  value       = azurerm_stream_analytics_job.fraud_detection.name
}

output "stream_analytics_job_id" {
  description = "ID of the Stream Analytics job"
  value       = azurerm_stream_analytics_job.fraud_detection.id
}

output "stream_analytics_job_state" {
  description = "Current state of the Stream Analytics job"
  value       = azurerm_stream_analytics_job.fraud_detection.job_state
}

output "stream_analytics_streaming_units" {
  description = "Number of streaming units allocated to the job"
  value       = azurerm_stream_analytics_job.fraud_detection.streaming_units
}

# Machine Learning Information
output "ml_workspace_name" {
  description = "Name of the Azure Machine Learning workspace"
  value       = azurerm_machine_learning_workspace.fraud_ml.name
}

output "ml_workspace_id" {
  description = "ID of the Azure Machine Learning workspace"
  value       = azurerm_machine_learning_workspace.fraud_ml.id
}

output "ml_compute_instance_name" {
  description = "Name of the ML compute instance"
  value       = azurerm_machine_learning_compute_instance.fraud_compute.name
}

output "ml_workspace_discovery_url" {
  description = "Discovery URL for the ML workspace"
  value       = azurerm_machine_learning_workspace.fraud_ml.discovery_url
}

# Cosmos DB Information
output "cosmosdb_account_name" {
  description = "Name of the Cosmos DB account"
  value       = azurerm_cosmosdb_account.fraud_cosmos.name
}

output "cosmosdb_account_id" {
  description = "ID of the Cosmos DB account"
  value       = azurerm_cosmosdb_account.fraud_cosmos.id
}

output "cosmosdb_endpoint" {
  description = "Endpoint URL for the Cosmos DB account"
  value       = azurerm_cosmosdb_account.fraud_cosmos.endpoint
}

output "cosmosdb_connection_strings" {
  description = "Connection strings for Cosmos DB (sensitive)"
  value       = azurerm_cosmosdb_account.fraud_cosmos.connection_strings
  sensitive   = true
}

output "cosmosdb_primary_key" {
  description = "Primary key for Cosmos DB access (sensitive)"
  value       = azurerm_cosmosdb_account.fraud_cosmos.primary_key
  sensitive   = true
}

output "cosmosdb_database_name" {
  description = "Name of the fraud detection database"
  value       = azurerm_cosmosdb_sql_database.fraud_database.name
}

output "cosmosdb_transactions_container" {
  description = "Name of the transactions container"
  value       = azurerm_cosmosdb_sql_container.transactions.name
}

output "cosmosdb_alerts_container" {
  description = "Name of the fraud alerts container"
  value       = azurerm_cosmosdb_sql_container.fraud_alerts.name
}

# Function App Information
output "function_app_name" {
  description = "Name of the Function App"
  value       = azurerm_linux_function_app.fraud_alerts.name
}

output "function_app_id" {
  description = "ID of the Function App"
  value       = azurerm_linux_function_app.fraud_alerts.id
}

output "function_app_hostname" {
  description = "Default hostname of the Function App"
  value       = azurerm_linux_function_app.fraud_alerts.default_hostname
}

output "function_app_outbound_ip_addresses" {
  description = "Outbound IP addresses of the Function App"
  value       = azurerm_linux_function_app.fraud_alerts.outbound_ip_addresses
}

output "function_app_principal_id" {
  description = "Principal ID of the Function App managed identity"
  value       = azurerm_linux_function_app.fraud_alerts.identity[0].principal_id
}

# Storage Account Information
output "storage_account_name" {
  description = "Name of the storage account"
  value       = azurerm_storage_account.fraud_storage.name
}

output "storage_account_id" {
  description = "ID of the storage account"
  value       = azurerm_storage_account.fraud_storage.id
}

output "storage_account_primary_endpoint" {
  description = "Primary blob endpoint of the storage account"
  value       = azurerm_storage_account.fraud_storage.primary_blob_endpoint
}

output "storage_account_primary_key" {
  description = "Primary access key for the storage account (sensitive)"
  value       = azurerm_storage_account.fraud_storage.primary_access_key
  sensitive   = true
}

# Monitoring Information
output "application_insights_name" {
  description = "Name of Application Insights instance"
  value       = var.enable_application_insights ? azurerm_application_insights.fraud_insights[0].name : null
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key for Application Insights (sensitive)"
  value       = var.enable_application_insights ? azurerm_application_insights.fraud_insights[0].instrumentation_key : null
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Connection string for Application Insights (sensitive)"
  value       = var.enable_application_insights ? azurerm_application_insights.fraud_insights[0].connection_string : null
  sensitive   = true
}

output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = var.enable_log_analytics ? azurerm_log_analytics_workspace.fraud_logs[0].name : null
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace"
  value       = var.enable_log_analytics ? azurerm_log_analytics_workspace.fraud_logs[0].id : null
}

output "log_analytics_workspace_customer_id" {
  description = "Customer ID of the Log Analytics workspace"
  value       = var.enable_log_analytics ? azurerm_log_analytics_workspace.fraud_logs[0].workspace_id : null
}

# Security and Access Information
output "service_principal_ids" {
  description = "Service principal IDs for managed identities"
  value = {
    function_app  = azurerm_linux_function_app.fraud_alerts.identity[0].principal_id
    ml_workspace  = azurerm_machine_learning_workspace.fraud_ml.identity[0].principal_id
  }
}

# Deployment Information
output "deployment_timestamp" {
  description = "Timestamp when the infrastructure was deployed"
  value       = timestamp()
}

output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = local.resource_suffix
}

output "common_tags" {
  description = "Common tags applied to all resources"
  value       = local.common_tags
}

# Testing and Validation Information
output "test_commands" {
  description = "Useful commands for testing the fraud detection pipeline"
  value = {
    check_stream_analytics_status = "az stream-analytics job show --name ${azurerm_stream_analytics_job.fraud_detection.name} --resource-group ${azurerm_resource_group.fraud_detection.name} --query jobState"
    send_test_transaction = "az eventhubs eventhub send --name ${azurerm_eventhub.transactions.name} --namespace-name ${azurerm_eventhub_namespace.fraud_events.name} --resource-group ${azurerm_resource_group.fraud_detection.name} --data '{\"transactionId\":\"test-001\",\"userId\":\"user-123\",\"amount\":100.00,\"merchantId\":\"merchant-456\",\"location\":\"TestLocation\",\"timestamp\":\"${timestamp()}\"}'"
    query_cosmos_transactions = "az cosmosdb sql query --database-name ${azurerm_cosmosdb_sql_database.fraud_database.name} --container-name ${azurerm_cosmosdb_sql_container.transactions.name} --account-name ${azurerm_cosmosdb_account.fraud_cosmos.name} --resource-group ${azurerm_resource_group.fraud_detection.name} --query-text 'SELECT * FROM c ORDER BY c.timestamp DESC OFFSET 0 LIMIT 10'"
    query_fraud_alerts = "az cosmosdb sql query --database-name ${azurerm_cosmosdb_sql_database.fraud_database.name} --container-name ${azurerm_cosmosdb_sql_container.fraud_alerts.name} --account-name ${azurerm_cosmosdb_account.fraud_cosmos.name} --resource-group ${azurerm_resource_group.fraud_detection.name} --query-text 'SELECT * FROM c ORDER BY c.timestamp DESC OFFSET 0 LIMIT 10'"
    view_function_logs = "az monitor log-analytics query --workspace ${var.enable_log_analytics ? azurerm_log_analytics_workspace.fraud_logs[0].workspace_id : "none"} --analytics-query 'traces | where message contains \"Fraud alert\" | order by timestamp desc'"
  }
}

# Connection Information for Applications
output "connection_info" {
  description = "Connection information for external applications"
  value = {
    eventhub_namespace = azurerm_eventhub_namespace.fraud_events.name
    eventhub_name     = azurerm_eventhub.transactions.name
    cosmosdb_endpoint = azurerm_cosmosdb_account.fraud_cosmos.endpoint
    function_app_url  = "https://${azurerm_linux_function_app.fraud_alerts.default_hostname}"
    ml_workspace_url  = azurerm_machine_learning_workspace.fraud_ml.workspace_url
  }
}

# Resource URLs for Azure Portal
output "azure_portal_urls" {
  description = "Direct links to resources in Azure Portal"
  value = {
    resource_group    = "https://portal.azure.com/#@/resource/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${azurerm_resource_group.fraud_detection.name}/overview"
    stream_analytics  = "https://portal.azure.com/#@/resource${azurerm_stream_analytics_job.fraud_detection.id}/overview"
    eventhub          = "https://portal.azure.com/#@/resource${azurerm_eventhub_namespace.fraud_events.id}/overview"
    cosmosdb          = "https://portal.azure.com/#@/resource${azurerm_cosmosdb_account.fraud_cosmos.id}/overview"
    function_app      = "https://portal.azure.com/#@/resource${azurerm_linux_function_app.fraud_alerts.id}/overview"
    ml_workspace      = "https://portal.azure.com/#@/resource${azurerm_machine_learning_workspace.fraud_ml.id}/overview"
  }
}

# Data source for current Azure client configuration
data "azurerm_client_config" "current" {}