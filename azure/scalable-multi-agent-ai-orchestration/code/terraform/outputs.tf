# ==============================================================================
# RESOURCE GROUP OUTPUTS
# ==============================================================================

output "resource_group_name" {
  description = "Name of the resource group"
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

# ==============================================================================
# AZURE AI FOUNDRY OUTPUTS
# ==============================================================================

output "ai_foundry_name" {
  description = "Name of the Azure AI Foundry resource"
  value       = azurerm_cognitive_services_account.main.name
}

output "ai_foundry_endpoint" {
  description = "Endpoint URL for Azure AI Foundry"
  value       = azurerm_cognitive_services_account.main.endpoint
}

output "ai_foundry_id" {
  description = "ID of the Azure AI Foundry resource"
  value       = azurerm_cognitive_services_account.main.id
}

output "ai_foundry_location" {
  description = "Location of the Azure AI Foundry resource"
  value       = azurerm_cognitive_services_account.main.location
}

output "gpt4_deployment_name" {
  description = "Name of the GPT-4 model deployment"
  value       = azurerm_cognitive_services_account_deployment.gpt4.name
}

output "gpt4_deployment_id" {
  description = "ID of the GPT-4 model deployment"
  value       = azurerm_cognitive_services_account_deployment.gpt4.id
}

# ==============================================================================
# STORAGE ACCOUNT OUTPUTS
# ==============================================================================

output "storage_account_name" {
  description = "Name of the storage account"
  value       = azurerm_storage_account.main.name
}

output "storage_account_id" {
  description = "ID of the storage account"
  value       = azurerm_storage_account.main.id
}

output "storage_account_primary_endpoint" {
  description = "Primary endpoint for the storage account"
  value       = azurerm_storage_account.main.primary_blob_endpoint
}

output "deadletter_container_name" {
  description = "Name of the dead letter events container"
  value       = azurerm_storage_container.deadletter.name
}

output "agent_data_container_name" {
  description = "Name of the agent data container"
  value       = azurerm_storage_container.agent_data.name
}

# ==============================================================================
# COSMOS DB OUTPUTS
# ==============================================================================

output "cosmos_account_name" {
  description = "Name of the Cosmos DB account"
  value       = azurerm_cosmosdb_account.main.name
}

output "cosmos_account_id" {
  description = "ID of the Cosmos DB account"
  value       = azurerm_cosmosdb_account.main.id
}

output "cosmos_account_endpoint" {
  description = "Endpoint URL for Cosmos DB"
  value       = azurerm_cosmosdb_account.main.endpoint
}

output "cosmos_database_name" {
  description = "Name of the Cosmos DB database"
  value       = azurerm_cosmosdb_sql_database.agent_state.name
}

output "cosmos_conversations_container_name" {
  description = "Name of the conversations container"
  value       = azurerm_cosmosdb_sql_container.conversations.name
}

output "cosmos_workflows_container_name" {
  description = "Name of the workflows container"
  value       = azurerm_cosmosdb_sql_container.workflows.name
}

# ==============================================================================
# EVENT GRID OUTPUTS
# ==============================================================================

output "event_grid_topic_name" {
  description = "Name of the Event Grid topic"
  value       = azurerm_eventgrid_topic.main.name
}

output "event_grid_topic_id" {
  description = "ID of the Event Grid topic"
  value       = azurerm_eventgrid_topic.main.id
}

output "event_grid_endpoint" {
  description = "Endpoint URL for Event Grid topic"
  value       = azurerm_eventgrid_topic.main.endpoint
}

output "event_grid_subscriptions" {
  description = "List of Event Grid subscription names"
  value = [
    azurerm_eventgrid_event_subscription.document_agent.name,
    azurerm_eventgrid_event_subscription.data_analysis_agent.name,
    azurerm_eventgrid_event_subscription.customer_service_agent.name,
    azurerm_eventgrid_event_subscription.workflow_orchestration.name,
    azurerm_eventgrid_event_subscription.health_monitoring.name
  ]
}

# ==============================================================================
# CONTAINER APPS ENVIRONMENT OUTPUTS
# ==============================================================================

output "container_apps_environment_name" {
  description = "Name of the Container Apps environment"
  value       = azurerm_container_app_environment.main.name
}

output "container_apps_environment_id" {
  description = "ID of the Container Apps environment"
  value       = azurerm_container_app_environment.main.id
}

output "container_apps_environment_default_domain" {
  description = "Default domain of the Container Apps environment"
  value       = azurerm_container_app_environment.main.default_domain
}

output "container_apps_environment_static_ip_address" {
  description = "Static IP address of the Container Apps environment"
  value       = azurerm_container_app_environment.main.static_ip_address
}

# ==============================================================================
# CONTAINER APPS OUTPUTS
# ==============================================================================

output "coordinator_agent_name" {
  description = "Name of the coordinator agent container app"
  value       = azurerm_container_app.coordinator.name
}

output "coordinator_agent_id" {
  description = "ID of the coordinator agent container app"
  value       = azurerm_container_app.coordinator.id
}

output "coordinator_agent_fqdn" {
  description = "FQDN of the coordinator agent container app"
  value       = azurerm_container_app.coordinator.ingress[0].fqdn
}

output "coordinator_agent_url" {
  description = "URL of the coordinator agent container app"
  value       = "https://${azurerm_container_app.coordinator.ingress[0].fqdn}"
}

output "document_agent_name" {
  description = "Name of the document agent container app"
  value       = azurerm_container_app.document.name
}

output "document_agent_id" {
  description = "ID of the document agent container app"
  value       = azurerm_container_app.document.id
}

output "document_agent_fqdn" {
  description = "FQDN of the document agent container app"
  value       = azurerm_container_app.document.ingress[0].fqdn
}

output "document_agent_url" {
  description = "URL of the document agent container app"
  value       = "https://${azurerm_container_app.document.ingress[0].fqdn}"
}

output "data_analysis_agent_name" {
  description = "Name of the data analysis agent container app"
  value       = azurerm_container_app.data_analysis.name
}

output "data_analysis_agent_id" {
  description = "ID of the data analysis agent container app"
  value       = azurerm_container_app.data_analysis.id
}

output "data_analysis_agent_fqdn" {
  description = "FQDN of the data analysis agent container app"
  value       = azurerm_container_app.data_analysis.ingress[0].fqdn
}

output "data_analysis_agent_url" {
  description = "URL of the data analysis agent container app"
  value       = "https://${azurerm_container_app.data_analysis.ingress[0].fqdn}"
}

output "customer_service_agent_name" {
  description = "Name of the customer service agent container app"
  value       = azurerm_container_app.customer_service.name
}

output "customer_service_agent_id" {
  description = "ID of the customer service agent container app"
  value       = azurerm_container_app.customer_service.id
}

output "customer_service_agent_fqdn" {
  description = "FQDN of the customer service agent container app"
  value       = azurerm_container_app.customer_service.ingress[0].fqdn
}

output "customer_service_agent_url" {
  description = "URL of the customer service agent container app"
  value       = "https://${azurerm_container_app.customer_service.ingress[0].fqdn}"
}

output "api_gateway_name" {
  description = "Name of the API gateway container app"
  value       = azurerm_container_app.api_gateway.name
}

output "api_gateway_id" {
  description = "ID of the API gateway container app"
  value       = azurerm_container_app.api_gateway.id
}

output "api_gateway_fqdn" {
  description = "FQDN of the API gateway container app"
  value       = azurerm_container_app.api_gateway.ingress[0].fqdn
}

output "api_gateway_url" {
  description = "URL of the API gateway container app"
  value       = "https://${azurerm_container_app.api_gateway.ingress[0].fqdn}"
}

# ==============================================================================
# MONITORING OUTPUTS
# ==============================================================================

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

output "application_insights_id" {
  description = "ID of the Application Insights instance"
  value       = azurerm_application_insights.main.id
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key for Application Insights"
  value       = azurerm_application_insights.main.instrumentation_key
  sensitive   = true
}

output "application_insights_app_id" {
  description = "Application ID for Application Insights"
  value       = azurerm_application_insights.main.app_id
}

output "monitor_action_group_name" {
  description = "Name of the monitor action group"
  value       = azurerm_monitor_action_group.main.name
}

output "monitor_action_group_id" {
  description = "ID of the monitor action group"
  value       = azurerm_monitor_action_group.main.id
}

# ==============================================================================
# SECURITY OUTPUTS
# ==============================================================================

output "key_vault_name" {
  description = "Name of the Key Vault"
  value       = azurerm_key_vault.main.name
}

output "key_vault_id" {
  description = "ID of the Key Vault"
  value       = azurerm_key_vault.main.id
}

output "key_vault_uri" {
  description = "URI of the Key Vault"
  value       = azurerm_key_vault.main.vault_uri
}

output "container_registry_name" {
  description = "Name of the Container Registry"
  value       = azurerm_container_registry.main.name
}

output "container_registry_id" {
  description = "ID of the Container Registry"
  value       = azurerm_container_registry.main.id
}

output "container_registry_login_server" {
  description = "Login server for the Container Registry"
  value       = azurerm_container_registry.main.login_server
}

# ==============================================================================
# DEPLOYMENT INFORMATION OUTPUTS
# ==============================================================================

output "deployment_summary" {
  description = "Summary of deployed resources"
  value = {
    resource_group           = azurerm_resource_group.main.name
    ai_foundry_endpoint      = azurerm_cognitive_services_account.main.endpoint
    api_gateway_url          = "https://${azurerm_container_app.api_gateway.ingress[0].fqdn}"
    coordinator_agent_url    = "https://${azurerm_container_app.coordinator.ingress[0].fqdn}"
    event_grid_endpoint      = azurerm_eventgrid_topic.main.endpoint
    cosmos_endpoint          = azurerm_cosmosdb_account.main.endpoint
    storage_account_endpoint = azurerm_storage_account.main.primary_blob_endpoint
    container_environment   = azurerm_container_app_environment.main.name
    application_insights     = azurerm_application_insights.main.name
    key_vault_uri           = azurerm_key_vault.main.vault_uri
  }
}

output "agent_endpoints" {
  description = "All agent endpoints for easy access"
  value = {
    api_gateway       = "https://${azurerm_container_app.api_gateway.ingress[0].fqdn}"
    coordinator       = "https://${azurerm_container_app.coordinator.ingress[0].fqdn}"
    document_agent    = "https://${azurerm_container_app.document.ingress[0].fqdn}"
    data_analysis     = "https://${azurerm_container_app.data_analysis.ingress[0].fqdn}"
    customer_service  = "https://${azurerm_container_app.customer_service.ingress[0].fqdn}"
  }
}

output "connection_strings" {
  description = "Connection information for services (sensitive)"
  value = {
    event_grid_endpoint = azurerm_eventgrid_topic.main.endpoint
    cosmos_endpoint     = azurerm_cosmosdb_account.main.endpoint
    storage_endpoint    = azurerm_storage_account.main.primary_blob_endpoint
    ai_foundry_endpoint = azurerm_cognitive_services_account.main.endpoint
  }
  sensitive = true
}

# ==============================================================================
# VALIDATION OUTPUTS
# ==============================================================================

output "validation_endpoints" {
  description = "Endpoints for validation and testing"
  value = {
    health_check_urls = {
      coordinator      = "https://${azurerm_container_app.coordinator.ingress[0].fqdn}/health"
      document_agent   = "https://${azurerm_container_app.document.ingress[0].fqdn}/health"
      data_analysis    = "https://${azurerm_container_app.data_analysis.ingress[0].fqdn}/health"
      customer_service = "https://${azurerm_container_app.customer_service.ingress[0].fqdn}/health"
      api_gateway      = "https://${azurerm_container_app.api_gateway.ingress[0].fqdn}/health"
    }
    workflow_endpoint = "https://${azurerm_container_app.api_gateway.ingress[0].fqdn}/api/workflows"
    event_test_url    = azurerm_eventgrid_topic.main.endpoint
  }
}

# ==============================================================================
# NEXT STEPS OUTPUTS
# ==============================================================================

output "next_steps" {
  description = "Next steps for using the deployed infrastructure"
  value = {
    test_workflow = "POST to https://${azurerm_container_app.api_gateway.ingress[0].fqdn}/api/workflows"
    monitor_logs  = "Check Application Insights: ${azurerm_application_insights.main.name}"
    view_metrics  = "Check Log Analytics: ${azurerm_log_analytics_workspace.main.name}"
    manage_secrets = "Access Key Vault: ${azurerm_key_vault.main.vault_uri}"
  }
}