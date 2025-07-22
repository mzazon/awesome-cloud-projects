# =============================================================================
# Outputs for Azure Quantum Supply Chain Network Optimization
# =============================================================================

# =============================================================================
# Resource Group Outputs
# =============================================================================

output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_id" {
  description = "ID of the created resource group"
  value       = azurerm_resource_group.main.id
}

output "location" {
  description = "Azure region where resources are deployed"
  value       = azurerm_resource_group.main.location
}

# =============================================================================
# Azure Quantum Workspace Outputs
# =============================================================================

output "quantum_workspace_name" {
  description = "Name of the Azure Quantum workspace"
  value       = azurerm_quantum_workspace.main.name
}

output "quantum_workspace_id" {
  description = "ID of the Azure Quantum workspace"
  value       = azurerm_quantum_workspace.main.id
}

output "quantum_workspace_endpoint" {
  description = "Endpoint URL for the Azure Quantum workspace"
  value       = "https://quantum.azure.com/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${azurerm_resource_group.main.name}/providers/Microsoft.Quantum/Workspaces/${azurerm_quantum_workspace.main.name}"
}

# =============================================================================
# Azure Digital Twins Outputs
# =============================================================================

output "digital_twins_instance_name" {
  description = "Name of the Azure Digital Twins instance"
  value       = azurerm_digital_twins_instance.main.name
}

output "digital_twins_instance_id" {
  description = "ID of the Azure Digital Twins instance"
  value       = azurerm_digital_twins_instance.main.id
}

output "digital_twins_endpoint" {
  description = "Endpoint URL for the Azure Digital Twins instance"
  value       = "https://${azurerm_digital_twins_instance.main.host_name}"
}

output "digital_twins_hostname" {
  description = "Hostname of the Azure Digital Twins instance"
  value       = azurerm_digital_twins_instance.main.host_name
}

# =============================================================================
# Azure Function App Outputs
# =============================================================================

output "function_app_name" {
  description = "Name of the Azure Function App"
  value       = azurerm_linux_function_app.main.name
}

output "function_app_id" {
  description = "ID of the Azure Function App"
  value       = azurerm_linux_function_app.main.id
}

output "function_app_default_hostname" {
  description = "Default hostname of the Azure Function App"
  value       = azurerm_linux_function_app.main.default_hostname
}

output "function_app_url" {
  description = "URL of the Azure Function App"
  value       = "https://${azurerm_linux_function_app.main.default_hostname}"
}

output "function_app_principal_id" {
  description = "Principal ID of the Function App's managed identity"
  value       = azurerm_linux_function_app.main.identity[0].principal_id
}

output "function_app_optimization_endpoint" {
  description = "Optimization endpoint URL for the Function App"
  value       = "https://${azurerm_linux_function_app.main.default_hostname}/api/optimization"
}

# =============================================================================
# Storage Account Outputs
# =============================================================================

output "storage_account_name" {
  description = "Name of the storage account"
  value       = azurerm_storage_account.main.name
}

output "storage_account_id" {
  description = "ID of the storage account"
  value       = azurerm_storage_account.main.id
}

output "storage_account_primary_endpoint" {
  description = "Primary endpoint of the storage account"
  value       = azurerm_storage_account.main.primary_blob_endpoint
}

output "storage_account_primary_access_key" {
  description = "Primary access key of the storage account"
  value       = azurerm_storage_account.main.primary_access_key
  sensitive   = true
}

# =============================================================================
# Cosmos DB Outputs
# =============================================================================

output "cosmos_account_name" {
  description = "Name of the Cosmos DB account"
  value       = azurerm_cosmosdb_account.main.name
}

output "cosmos_account_id" {
  description = "ID of the Cosmos DB account"
  value       = azurerm_cosmosdb_account.main.id
}

output "cosmos_account_endpoint" {
  description = "Endpoint URL of the Cosmos DB account"
  value       = azurerm_cosmosdb_account.main.endpoint
}

output "cosmos_database_name" {
  description = "Name of the Cosmos DB database"
  value       = azurerm_cosmosdb_sql_database.main.name
}

output "cosmos_container_name" {
  description = "Name of the Cosmos DB container for optimization results"
  value       = azurerm_cosmosdb_sql_container.optimization_results.name
}

output "cosmos_connection_strings" {
  description = "Connection strings for the Cosmos DB account"
  value       = azurerm_cosmosdb_account.main.connection_strings
  sensitive   = true
}

output "cosmos_primary_key" {
  description = "Primary key for the Cosmos DB account"
  value       = azurerm_cosmosdb_account.main.primary_key
  sensitive   = true
}

# =============================================================================
# Event Hub Outputs
# =============================================================================

output "eventhub_namespace_name" {
  description = "Name of the Event Hub namespace"
  value       = azurerm_eventhub_namespace.main.name
}

output "eventhub_namespace_id" {
  description = "ID of the Event Hub namespace"
  value       = azurerm_eventhub_namespace.main.id
}

output "eventhub_name" {
  description = "Name of the Event Hub"
  value       = azurerm_eventhub.supply_chain_events.name
}

output "eventhub_id" {
  description = "ID of the Event Hub"
  value       = azurerm_eventhub.supply_chain_events.id
}

output "eventhub_connection_string" {
  description = "Connection string for the Event Hub"
  value       = azurerm_eventhub_namespace.main.default_primary_connection_string
  sensitive   = true
}

# =============================================================================
# Stream Analytics Outputs
# =============================================================================

output "stream_analytics_job_name" {
  description = "Name of the Stream Analytics job"
  value       = azurerm_stream_analytics_job.main.name
}

output "stream_analytics_job_id" {
  description = "ID of the Stream Analytics job"
  value       = azurerm_stream_analytics_job.main.id
}

output "stream_analytics_job_state" {
  description = "Current state of the Stream Analytics job"
  value       = azurerm_stream_analytics_job.main.job_state
}

# =============================================================================
# Monitoring Outputs
# =============================================================================

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

output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.name
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.id
}

output "log_analytics_workspace_primary_shared_key" {
  description = "Primary shared key for the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.primary_shared_key
  sensitive   = true
}

# =============================================================================
# Security and Access Outputs
# =============================================================================

output "action_group_id" {
  description = "ID of the monitoring action group"
  value       = azurerm_monitor_action_group.supply_chain_alerts.id
}

output "metric_alert_id" {
  description = "ID of the low inventory metric alert"
  value       = azurerm_monitor_metric_alert.low_inventory.id
}

# =============================================================================
# Supply Chain Configuration Outputs
# =============================================================================

output "supply_chain_suppliers" {
  description = "Configuration of supply chain suppliers"
  value = [
    for supplier in var.supply_chain_suppliers : {
      id            = supplier.id
      name          = supplier.name
      location      = supplier.location
      capacity      = supplier.capacity
      cost_per_unit = supplier.cost_per_unit
    }
  ]
}

output "supply_chain_warehouses" {
  description = "Configuration of supply chain warehouses"
  value = [
    for warehouse in var.supply_chain_warehouses : {
      id               = warehouse.id
      name             = warehouse.name
      location         = warehouse.location
      storage_capacity = warehouse.storage_capacity
    }
  ]
}

# =============================================================================
# Deployment Information
# =============================================================================

output "deployment_summary" {
  description = "Summary of deployed resources"
  value = {
    resource_group_name         = azurerm_resource_group.main.name
    quantum_workspace_name      = azurerm_quantum_workspace.main.name
    digital_twins_instance_name = azurerm_digital_twins_instance.main.name
    function_app_name           = azurerm_linux_function_app.main.name
    cosmos_account_name         = azurerm_cosmosdb_account.main.name
    eventhub_namespace_name     = azurerm_eventhub_namespace.main.name
    stream_analytics_job_name   = azurerm_stream_analytics_job.main.name
    application_insights_name   = azurerm_application_insights.main.name
    log_analytics_workspace_name = azurerm_log_analytics_workspace.main.name
    deployment_region           = azurerm_resource_group.main.location
    environment                 = var.environment
  }
}

# =============================================================================
# Connection and Configuration Information
# =============================================================================

output "quantum_cli_commands" {
  description = "CLI commands to interact with the Quantum workspace"
  value = {
    list_workspaces = "az quantum workspace list --resource-group ${azurerm_resource_group.main.name}"
    show_workspace  = "az quantum workspace show --resource-group ${azurerm_resource_group.main.name} --workspace-name ${azurerm_quantum_workspace.main.name}"
    list_providers  = "az quantum offerings list --resource-group ${azurerm_resource_group.main.name} --workspace-name ${azurerm_quantum_workspace.main.name}"
  }
}

output "digital_twins_cli_commands" {
  description = "CLI commands to interact with Digital Twins"
  value = {
    query_twins = "az dt twin query --dt-name ${azurerm_digital_twins_instance.main.name} --query-command 'SELECT * FROM DIGITALTWINS'"
    show_instance = "az dt show --dt-name ${azurerm_digital_twins_instance.main.name} --resource-group ${azurerm_resource_group.main.name}"
    list_models = "az dt model list --dt-name ${azurerm_digital_twins_instance.main.name}"
  }
}

output "function_app_cli_commands" {
  description = "CLI commands to interact with the Function App"
  value = {
    show_app = "az functionapp show --resource-group ${azurerm_resource_group.main.name} --name ${azurerm_linux_function_app.main.name}"
    list_functions = "az functionapp function list --resource-group ${azurerm_resource_group.main.name} --name ${azurerm_linux_function_app.main.name}"
    show_logs = "az functionapp log tail --resource-group ${azurerm_resource_group.main.name} --name ${azurerm_linux_function_app.main.name}"
  }
}

# =============================================================================
# Environment Variables for Development
# =============================================================================

output "environment_variables" {
  description = "Environment variables for local development and testing"
  value = {
    RESOURCE_GROUP                = azurerm_resource_group.main.name
    LOCATION                     = azurerm_resource_group.main.location
    QUANTUM_WORKSPACE_NAME       = azurerm_quantum_workspace.main.name
    DIGITAL_TWINS_ENDPOINT       = "https://${azurerm_digital_twins_instance.main.host_name}"
    FUNCTION_APP_NAME            = azurerm_linux_function_app.main.name
    COSMOS_ACCOUNT_NAME          = azurerm_cosmosdb_account.main.name
    EVENTHUB_NAMESPACE_NAME      = azurerm_eventhub_namespace.main.name
    STREAM_ANALYTICS_JOB_NAME    = azurerm_stream_analytics_job.main.name
    APPLICATION_INSIGHTS_NAME    = azurerm_application_insights.main.name
    LOG_ANALYTICS_WORKSPACE_NAME = azurerm_log_analytics_workspace.main.name
    SUBSCRIPTION_ID              = data.azurerm_client_config.current.subscription_id
  }
}

# =============================================================================
# Cost Management Information
# =============================================================================

output "cost_management_info" {
  description = "Information for cost management and monitoring"
  value = {
    resource_group_name = azurerm_resource_group.main.name
    cost_center        = var.cost_center
    business_unit      = var.business_unit
    project_name       = var.project_name
    environment        = var.environment
    quantum_workspace  = azurerm_quantum_workspace.main.name
    estimated_monthly_cost = "Review Azure Cost Management for actual costs"
  }
}

# =============================================================================
# Validation Commands
# =============================================================================

output "validation_commands" {
  description = "Commands to validate the deployment"
  value = {
    check_quantum_workspace = "az quantum workspace show --resource-group ${azurerm_resource_group.main.name} --workspace-name ${azurerm_quantum_workspace.main.name} --output table"
    check_digital_twins = "az dt show --dt-name ${azurerm_digital_twins_instance.main.name} --resource-group ${azurerm_resource_group.main.name} --output table"
    check_function_app = "az functionapp show --resource-group ${azurerm_resource_group.main.name} --name ${azurerm_linux_function_app.main.name} --output table"
    check_cosmos_db = "az cosmosdb show --resource-group ${azurerm_resource_group.main.name} --name ${azurerm_cosmosdb_account.main.name} --output table"
    check_stream_analytics = "az stream-analytics job show --resource-group ${azurerm_resource_group.main.name} --name ${azurerm_stream_analytics_job.main.name} --output table"
    test_optimization_endpoint = "curl -X POST https://${azurerm_linux_function_app.main.default_hostname}/api/optimization -H 'Content-Type: application/json' -d '{\"test\": \"data\"}'"
  }
}