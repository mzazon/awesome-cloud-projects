# Outputs for Event-Driven AI Agent Workflows with AI Foundry and Logic Apps
# These outputs provide important information for connecting to and managing the deployed resources

# Resource Group Information
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = local.resource_group.name
}

output "resource_group_location" {
  description = "Location of the resource group"
  value       = local.resource_group.location
}

# AI Foundry Workspace Information
output "ai_foundry_hub_name" {
  description = "Name of the AI Foundry hub workspace"
  value       = azurerm_machine_learning_workspace.hub.name
}

output "ai_foundry_hub_id" {
  description = "Resource ID of the AI Foundry hub workspace"
  value       = azurerm_machine_learning_workspace.hub.id
}

output "ai_foundry_project_name" {
  description = "Name of the AI Foundry project workspace"
  value       = azurerm_machine_learning_workspace.project.name
}

output "ai_foundry_project_id" {
  description = "Resource ID of the AI Foundry project workspace"
  value       = azurerm_machine_learning_workspace.project.id
}

output "ai_foundry_project_endpoint" {
  description = "Discovery URL for the AI Foundry project workspace"
  value       = azurerm_machine_learning_workspace.project.discovery_url
}

# Service Bus Information
output "service_bus_namespace_name" {
  description = "Name of the Service Bus namespace"
  value       = azurerm_servicebus_namespace.main.name
}

output "service_bus_namespace_id" {
  description = "Resource ID of the Service Bus namespace"
  value       = azurerm_servicebus_namespace.main.id
}

output "service_bus_namespace_hostname" {
  description = "Hostname of the Service Bus namespace"
  value       = "${azurerm_servicebus_namespace.main.name}.servicebus.windows.net"
}

output "service_bus_queue_name" {
  description = "Name of the Service Bus queue for event processing"
  value       = azurerm_servicebus_queue.event_processing.name
}

output "service_bus_topic_name" {
  description = "Name of the Service Bus topic for business events"
  value       = azurerm_servicebus_topic.business_events.name
}

output "service_bus_subscription_name" {
  description = "Name of the Service Bus topic subscription"
  value       = azurerm_servicebus_subscription.ai_agent.name
}

# Logic App Information
output "logic_app_name" {
  description = "Name of the Logic App workflow"
  value       = azurerm_logic_app_workflow.main.name
}

output "logic_app_id" {
  description = "Resource ID of the Logic App workflow"
  value       = azurerm_logic_app_workflow.main.id
}

output "logic_app_access_endpoint" {
  description = "Access endpoint for the Logic App workflow"
  value       = azurerm_logic_app_workflow.main.access_endpoint
}

# Storage and Supporting Services
output "storage_account_name" {
  description = "Name of the storage account for AI Foundry"
  value       = azurerm_storage_account.ai_foundry.name
}

output "storage_account_primary_endpoint" {
  description = "Primary blob endpoint of the storage account"
  value       = azurerm_storage_account.ai_foundry.primary_blob_endpoint
}

output "container_registry_name" {
  description = "Name of the container registry"
  value       = azurerm_container_registry.main.name
}

output "container_registry_login_server" {
  description = "Login server URL of the container registry"
  value       = azurerm_container_registry.main.login_server
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

# Key Vault Information
output "key_vault_name" {
  description = "Name of the Key Vault"
  value       = azurerm_key_vault.main.name
}

output "key_vault_id" {
  description = "Resource ID of the Key Vault"
  value       = azurerm_key_vault.main.id
}

output "key_vault_uri" {
  description = "URI of the Key Vault"
  value       = azurerm_key_vault.main.vault_uri
}

# Log Analytics Information (if enabled)
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace (if enabled)"
  value       = var.enable_diagnostic_logs ? azurerm_log_analytics_workspace.main[0].name : null
}

output "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics workspace (if enabled)"
  value       = var.enable_diagnostic_logs ? azurerm_log_analytics_workspace.main[0].id : null
}

# Connection Information
output "service_bus_connection_string" {
  description = "Primary connection string for Service Bus (stored in Key Vault)"
  value       = "Stored in Key Vault: ${azurerm_key_vault.main.name}/secrets/service-bus-connection-string"
  sensitive   = false
}

# Testing and Management URLs
output "azure_portal_resource_group_url" {
  description = "Azure Portal URL for the resource group"
  value       = "https://portal.azure.com/#@/resource${local.resource_group.id}"
}

output "ai_foundry_studio_url" {
  description = "Azure AI Foundry Studio URL for the project"
  value       = "https://ai.azure.com/projectOverview/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${local.resource_group.name}/providers/Microsoft.MachineLearningServices/workspaces/${azurerm_machine_learning_workspace.project.name}"
}

output "logic_app_designer_url" {
  description = "Logic App Designer URL"
  value       = "https://portal.azure.com/#@/resource${azurerm_logic_app_workflow.main.id}/logicApp"
}

# Resource Identifiers for CLI Commands
output "resource_identifiers" {
  description = "Resource identifiers for Azure CLI commands"
  value = {
    resource_group           = local.resource_group.name
    service_bus_namespace    = azurerm_servicebus_namespace.main.name
    service_bus_queue        = azurerm_servicebus_queue.event_processing.name
    service_bus_topic        = azurerm_servicebus_topic.business_events.name
    ai_foundry_hub          = azurerm_machine_learning_workspace.hub.name
    ai_foundry_project      = azurerm_machine_learning_workspace.project.name
    logic_app               = azurerm_logic_app_workflow.main.name
    key_vault               = azurerm_key_vault.main.name
  }
}

# Sample CLI Commands
output "sample_cli_commands" {
  description = "Sample Azure CLI commands for testing the infrastructure"
  value = {
    send_test_message = "az servicebus message send --namespace-name ${azurerm_servicebus_namespace.main.name} --queue-name ${azurerm_servicebus_queue.event_processing.name} --body '{\"eventType\":\"test\",\"content\":\"Test message\",\"metadata\":{\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}}'"
    check_queue_status = "az servicebus queue show --name ${azurerm_servicebus_queue.event_processing.name} --namespace-name ${azurerm_servicebus_namespace.main.name} --resource-group ${local.resource_group.name} --query messageCount"
    list_logic_app_runs = "az logic workflow list-runs --name ${azurerm_logic_app_workflow.main.name} --resource-group ${local.resource_group.name} --top 5"
    get_connection_string = "az keyvault secret show --name service-bus-connection-string --vault-name ${azurerm_key_vault.main.name} --query value --output tsv"
  }
}

# Deployment Summary
output "deployment_summary" {
  description = "Summary of deployed resources and next steps"
  value = {
    ai_foundry_hub_created     = azurerm_machine_learning_workspace.hub.name
    ai_foundry_project_created = azurerm_machine_learning_workspace.project.name
    service_bus_namespace      = azurerm_servicebus_namespace.main.name
    logic_app_workflow         = azurerm_logic_app_workflow.main.name
    diagnostic_logs_enabled    = var.enable_diagnostic_logs
    next_steps = [
      "1. Navigate to Azure AI Foundry Studio to create and configure AI agents",
      "2. Test the Service Bus queue by sending sample messages",
      "3. Monitor Logic App workflow execution in the Azure Portal",
      "4. Configure AI agent tools and actions in AI Foundry",
      "5. Review diagnostic logs in Log Analytics (if enabled)"
    ]
  }
}