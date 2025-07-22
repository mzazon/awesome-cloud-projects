# Resource Group Information
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.quantum_manufacturing.name
}

output "resource_group_location" {
  description = "Location of the resource group"
  value       = azurerm_resource_group.quantum_manufacturing.location
}

output "resource_group_id" {
  description = "ID of the resource group"
  value       = azurerm_resource_group.quantum_manufacturing.id
}

# Storage Account Information
output "storage_account_name" {
  description = "Name of the storage account"
  value       = azurerm_storage_account.quantum_storage.name
}

output "storage_account_primary_endpoint" {
  description = "Primary endpoint of the storage account"
  value       = azurerm_storage_account.quantum_storage.primary_blob_endpoint
}

output "storage_account_id" {
  description = "ID of the storage account"
  value       = azurerm_storage_account.quantum_storage.id
}

output "storage_containers" {
  description = "List of created storage containers"
  value = {
    ml_inference   = azurerm_storage_container.ml_inference.name
    quality_data   = azurerm_storage_container.quality_data.name
    quantum_results = azurerm_storage_container.quantum_results.name
  }
}

# Key Vault Information
output "key_vault_name" {
  description = "Name of the Key Vault"
  value       = azurerm_key_vault.quantum_kv.name
}

output "key_vault_uri" {
  description = "URI of the Key Vault"
  value       = azurerm_key_vault.quantum_kv.vault_uri
}

output "key_vault_id" {
  description = "ID of the Key Vault"
  value       = azurerm_key_vault.quantum_kv.id
}

# Azure Machine Learning Workspace Information
output "ml_workspace_name" {
  description = "Name of the Machine Learning workspace"
  value       = azurerm_machine_learning_workspace.quantum_ml.name
}

output "ml_workspace_id" {
  description = "ID of the Machine Learning workspace"
  value       = azurerm_machine_learning_workspace.quantum_ml.id
}

output "ml_workspace_discovery_url" {
  description = "Discovery URL of the Machine Learning workspace"
  value       = azurerm_machine_learning_workspace.quantum_ml.discovery_url
}

output "ml_compute_cluster_name" {
  description = "Name of the ML compute cluster"
  value       = azurerm_machine_learning_compute_cluster.quantum_cluster.name
}

output "ml_compute_instance_name" {
  description = "Name of the ML compute instance"
  value       = azurerm_machine_learning_compute_instance.quantum_dev.name
}

# Azure Quantum Workspace Information
output "quantum_workspace_name" {
  description = "Name of the Quantum workspace"
  value       = var.enable_quantum_workspace ? azurerm_quantum_workspace.manufacturing_quantum[0].name : "Not deployed"
}

output "quantum_workspace_id" {
  description = "ID of the Quantum workspace"
  value       = var.enable_quantum_workspace ? azurerm_quantum_workspace.manufacturing_quantum[0].id : "Not deployed"
}

output "quantum_workspace_endpoint" {
  description = "Endpoint of the Quantum workspace"
  value       = var.enable_quantum_workspace ? "https://quantum.azure.com/workspaces/${azurerm_quantum_workspace.manufacturing_quantum[0].name}" : "Not deployed"
}

# IoT Hub Information
output "iot_hub_name" {
  description = "Name of the IoT Hub"
  value       = azurerm_iothub.manufacturing_iot.name
}

output "iot_hub_hostname" {
  description = "Hostname of the IoT Hub"
  value       = azurerm_iothub.manufacturing_iot.hostname
}

output "iot_hub_id" {
  description = "ID of the IoT Hub"
  value       = azurerm_iothub.manufacturing_iot.id
}

output "iot_hub_connection_string" {
  description = "Connection string for IoT Hub (sensitive)"
  value       = azurerm_iothub.manufacturing_iot.shared_access_policy[0].primary_connection_string
  sensitive   = true
}

# Event Hub Information
output "event_hub_namespace_name" {
  description = "Name of the Event Hub namespace"
  value       = azurerm_eventhub_namespace.iot_events.name
}

output "event_hub_name" {
  description = "Name of the Event Hub"
  value       = azurerm_eventhub.quality_events.name
}

output "event_hub_connection_string" {
  description = "Connection string for Event Hub (sensitive)"
  value       = azurerm_eventhub_authorization_rule.iot_hub_listen.primary_connection_string
  sensitive   = true
}

# Stream Analytics Information
output "stream_analytics_job_name" {
  description = "Name of the Stream Analytics job"
  value       = var.enable_stream_analytics ? azurerm_stream_analytics_job.quality_control[0].name : "Not deployed"
}

output "stream_analytics_job_id" {
  description = "ID of the Stream Analytics job"
  value       = var.enable_stream_analytics ? azurerm_stream_analytics_job.quality_control[0].id : "Not deployed"
}

output "stream_analytics_job_status" {
  description = "Status of the Stream Analytics job"
  value       = var.enable_stream_analytics ? "Deployed (requires manual start)" : "Not deployed"
}

# Cosmos DB Information
output "cosmos_db_account_name" {
  description = "Name of the Cosmos DB account"
  value       = var.enable_cosmos_db ? azurerm_cosmosdb_account.quality_dashboard[0].name : "Not deployed"
}

output "cosmos_db_endpoint" {
  description = "Endpoint of the Cosmos DB account"
  value       = var.enable_cosmos_db ? azurerm_cosmosdb_account.quality_dashboard[0].endpoint : "Not deployed"
}

output "cosmos_db_id" {
  description = "ID of the Cosmos DB account"
  value       = var.enable_cosmos_db ? azurerm_cosmosdb_account.quality_dashboard[0].id : "Not deployed"
}

output "cosmos_db_database_name" {
  description = "Name of the Cosmos DB database"
  value       = var.enable_cosmos_db ? azurerm_cosmosdb_sql_database.quality_control_db[0].name : "Not deployed"
}

output "cosmos_db_container_name" {
  description = "Name of the Cosmos DB container"
  value       = var.enable_cosmos_db ? azurerm_cosmosdb_sql_container.quality_metrics[0].name : "Not deployed"
}

# Function App Information
output "function_app_name" {
  description = "Name of the Function App"
  value       = var.enable_function_app ? azurerm_linux_function_app.dashboard_api[0].name : "Not deployed"
}

output "function_app_hostname" {
  description = "Hostname of the Function App"
  value       = var.enable_function_app ? azurerm_linux_function_app.dashboard_api[0].default_hostname : "Not deployed"
}

output "function_app_id" {
  description = "ID of the Function App"
  value       = var.enable_function_app ? azurerm_linux_function_app.dashboard_api[0].id : "Not deployed"
}

output "function_app_url" {
  description = "URL of the Function App"
  value       = var.enable_function_app ? "https://${azurerm_linux_function_app.dashboard_api[0].default_hostname}" : "Not deployed"
}

# Application Insights Information
output "application_insights_name" {
  description = "Name of Application Insights"
  value       = var.enable_application_insights ? azurerm_application_insights.quantum_insights[0].name : "Not deployed"
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key for Application Insights (sensitive)"
  value       = var.enable_application_insights ? azurerm_application_insights.quantum_insights[0].instrumentation_key : "Not deployed"
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Connection string for Application Insights (sensitive)"
  value       = var.enable_application_insights ? azurerm_application_insights.quantum_insights[0].connection_string : "Not deployed"
  sensitive   = true
}

# Log Analytics Information
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = var.enable_monitoring ? azurerm_log_analytics_workspace.quantum_logs[0].name : "Not deployed"
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace"
  value       = var.enable_monitoring ? azurerm_log_analytics_workspace.quantum_logs[0].workspace_id : "Not deployed"
}

# Service Principal Information
output "ml_workspace_principal_id" {
  description = "Principal ID of the ML workspace managed identity"
  value       = azurerm_machine_learning_workspace.quantum_ml.identity[0].principal_id
}

output "function_app_principal_id" {
  description = "Principal ID of the Function App managed identity"
  value       = var.enable_function_app ? azurerm_linux_function_app.dashboard_api[0].identity[0].principal_id : "Not deployed"
}

# Deployment Information
output "deployment_summary" {
  description = "Summary of deployed components"
  value = {
    resource_group        = azurerm_resource_group.quantum_manufacturing.name
    storage_account       = azurerm_storage_account.quantum_storage.name
    key_vault            = azurerm_key_vault.quantum_kv.name
    ml_workspace         = azurerm_machine_learning_workspace.quantum_ml.name
    quantum_workspace    = var.enable_quantum_workspace ? azurerm_quantum_workspace.manufacturing_quantum[0].name : "Not deployed"
    iot_hub              = azurerm_iothub.manufacturing_iot.name
    stream_analytics     = var.enable_stream_analytics ? azurerm_stream_analytics_job.quality_control[0].name : "Not deployed"
    cosmos_db            = var.enable_cosmos_db ? azurerm_cosmosdb_account.quality_dashboard[0].name : "Not deployed"
    function_app         = var.enable_function_app ? azurerm_linux_function_app.dashboard_api[0].name : "Not deployed"
    application_insights = var.enable_application_insights ? azurerm_application_insights.quantum_insights[0].name : "Not deployed"
    log_analytics        = var.enable_monitoring ? azurerm_log_analytics_workspace.quantum_logs[0].name : "Not deployed"
  }
}

# Resource URLs and Endpoints
output "azure_portal_links" {
  description = "Direct links to Azure Portal for deployed resources"
  value = {
    resource_group = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_resource_group.quantum_manufacturing.id}"
    ml_workspace   = "https://ml.azure.com/workspaces/${azurerm_machine_learning_workspace.quantum_ml.name}"
    quantum_workspace = var.enable_quantum_workspace ? "https://quantum.azure.com/workspaces/${azurerm_quantum_workspace.manufacturing_quantum[0].name}" : "Not deployed"
    iot_hub        = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_iothub.manufacturing_iot.id}"
    storage_account = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_storage_account.quantum_storage.id}"
    cosmos_db      = var.enable_cosmos_db ? "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_cosmosdb_account.quality_dashboard[0].id}" : "Not deployed"
    function_app   = var.enable_function_app ? "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_linux_function_app.dashboard_api[0].id}" : "Not deployed"
  }
}

# Cost and Resource Information
output "resource_count" {
  description = "Count of deployed resources by type"
  value = {
    storage_account     = 1
    key_vault          = 1
    ml_workspace       = 1
    quantum_workspace  = var.enable_quantum_workspace ? 1 : 0
    iot_hub           = 1
    stream_analytics   = var.enable_stream_analytics ? 1 : 0
    cosmos_db         = var.enable_cosmos_db ? 1 : 0
    function_app      = var.enable_function_app ? 1 : 0
    application_insights = var.enable_application_insights ? 1 : 0
    log_analytics     = var.enable_monitoring ? 1 : 0
  }
}

# Configuration for Next Steps
output "next_steps" {
  description = "Next steps after deployment"
  value = {
    quantum_access = "Request access to Azure Quantum through the Azure portal if not already granted"
    ml_setup = "Configure ML environment and upload training data to ${azurerm_storage_container.quality_data.name} container"
    iot_devices = "Create IoT device identities and configure manufacturing sensors"
    stream_analytics = var.enable_stream_analytics ? "Start the Stream Analytics job: ${azurerm_stream_analytics_job.quality_control[0].name}" : "Stream Analytics not deployed"
    function_deployment = var.enable_function_app ? "Deploy function code to ${azurerm_linux_function_app.dashboard_api[0].name}" : "Function App not deployed"
    monitoring = var.enable_monitoring ? "Configure alerts and dashboards in Log Analytics workspace" : "Monitoring not enabled"
  }
}

# Generated Values
output "generated_suffix" {
  description = "Random suffix used for resource names"
  value       = random_string.suffix.result
}

output "deployment_timestamp" {
  description = "Timestamp of the deployment"
  value       = timestamp()
}