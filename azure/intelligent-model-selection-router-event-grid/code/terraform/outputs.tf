# Output values for Azure intelligent model selection architecture
# These outputs provide important information for connecting to and managing the deployed resources

# Resource Group Information
output "resource_group_name" {
  description = "The name of the resource group containing all resources"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "The location where all resources are deployed"
  value       = azurerm_resource_group.main.location
}

output "resource_group_id" {
  description = "The resource ID of the resource group"
  value       = azurerm_resource_group.main.id
}

# Storage Account Information
output "storage_account_name" {
  description = "The name of the storage account used by the Function App"
  value       = azurerm_storage_account.function_storage.name
}

output "storage_account_primary_connection_string" {
  description = "The primary connection string for the storage account"
  value       = azurerm_storage_account.function_storage.primary_connection_string
  sensitive   = true
}

# Function App Information
output "function_app_name" {
  description = "The name of the Azure Function App"
  value       = azurerm_linux_function_app.main.name
}

output "function_app_url" {
  description = "The default hostname of the Function App"
  value       = "https://${azurerm_linux_function_app.main.default_hostname}"
}

output "function_app_id" {
  description = "The resource ID of the Function App"
  value       = azurerm_linux_function_app.main.id
}

output "function_app_principal_id" {
  description = "The principal ID of the Function App's managed identity"
  value       = azurerm_linux_function_app.main.identity[0].principal_id
}

output "function_health_check_url" {
  description = "The health check endpoint URL for the Function App"
  value       = "https://${azurerm_linux_function_app.main.default_hostname}/api/health"
}

# Event Grid Information
output "event_grid_topic_name" {
  description = "The name of the Event Grid topic"
  value       = azurerm_eventgrid_topic.main.name
}

output "event_grid_topic_endpoint" {
  description = "The endpoint URL for publishing events to the Event Grid topic"
  value       = azurerm_eventgrid_topic.main.endpoint
}

output "event_grid_topic_id" {
  description = "The resource ID of the Event Grid topic"
  value       = azurerm_eventgrid_topic.main.id
}

output "event_grid_primary_access_key" {
  description = "The primary access key for the Event Grid topic"
  value       = azurerm_eventgrid_topic.main.primary_access_key
  sensitive   = true
}

output "event_grid_secondary_access_key" {
  description = "The secondary access key for the Event Grid topic"
  value       = azurerm_eventgrid_topic.main.secondary_access_key
  sensitive   = true
}

# Event Grid Subscription Information
output "event_subscription_name" {
  description = "The name of the Event Grid subscription"
  value       = azurerm_eventgrid_event_subscription.function_subscription.name
}

output "event_subscription_id" {
  description = "The resource ID of the Event Grid subscription"
  value       = azurerm_eventgrid_event_subscription.function_subscription.id
}

# Azure AI Foundry Information
output "ai_foundry_name" {
  description = "The name of the Azure AI Foundry resource"
  value       = azurerm_cognitive_account.ai_foundry.name
}

output "ai_foundry_endpoint" {
  description = "The endpoint URL for the Azure AI Foundry resource"
  value       = azurerm_cognitive_account.ai_foundry.endpoint
}

output "ai_foundry_id" {
  description = "The resource ID of the Azure AI Foundry resource"
  value       = azurerm_cognitive_account.ai_foundry.id
}

output "ai_foundry_primary_access_key" {
  description = "The primary access key for the Azure AI Foundry resource"
  value       = azurerm_cognitive_account.ai_foundry.primary_access_key
  sensitive   = true
}

output "ai_foundry_secondary_access_key" {
  description = "The secondary access key for the Azure AI Foundry resource"
  value       = azurerm_cognitive_account.ai_foundry.secondary_access_key
  sensitive   = true
}

# Model Router Deployment Information
output "model_deployment_name" {
  description = "The name of the Model Router deployment"
  value       = azurerm_cognitive_deployment.model_router.name
}

output "model_deployment_id" {
  description = "The resource ID of the Model Router deployment"
  value       = azurerm_cognitive_deployment.model_router.id
}

output "model_name" {
  description = "The name of the deployed model"
  value       = azurerm_cognitive_deployment.model_router.model[0].name
}

output "model_version" {
  description = "The version of the deployed model"
  value       = azurerm_cognitive_deployment.model_router.model[0].version
}

# Application Insights Information
output "application_insights_name" {
  description = "The name of the Application Insights component"
  value       = azurerm_application_insights.main.name
}

output "application_insights_instrumentation_key" {
  description = "The instrumentation key for Application Insights"
  value       = azurerm_application_insights.main.instrumentation_key
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "The connection string for Application Insights"
  value       = azurerm_application_insights.main.connection_string
  sensitive   = true
}

output "application_insights_app_id" {
  description = "The app ID of the Application Insights component"
  value       = azurerm_application_insights.main.app_id
}

# Log Analytics Workspace Information
output "log_analytics_workspace_name" {
  description = "The name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.name
}

output "log_analytics_workspace_id" {
  description = "The resource ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.id
}

output "log_analytics_workspace_customer_id" {
  description = "The customer ID (workspace ID) of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.workspace_id
}

# Testing and Validation Information
output "sample_event_payload" {
  description = "Sample Event Grid event payload for testing the intelligent routing"
  value = jsonencode({
    id          = "test-001"
    eventType   = "AIRequest.Submitted"
    subject     = "test-request"
    eventTime   = "2025-01-23T12:00:00Z"
    dataVersion = "1.0"
    data = {
      prompt     = "What is artificial intelligence and how does it work?"
      request_id = "test-001"
    }
  })
}

output "azure_cli_test_command" {
  description = "Azure CLI command to test the Event Grid topic"
  value = "az eventgrid event send --topic-name ${azurerm_eventgrid_topic.main.name} --resource-group ${azurerm_resource_group.main.name} --events '[{\"id\":\"test-001\",\"eventType\":\"AIRequest.Submitted\",\"subject\":\"test-request\",\"data\":{\"prompt\":\"What is artificial intelligence?\",\"request_id\":\"test-001\"},\"dataVersion\":\"1.0\"}]'"
}

# Cost and Resource Management Information
output "estimated_monthly_cost" {
  description = "Estimated monthly cost in USD for the deployed resources (approximate)"
  value = {
    function_app_consumption = "5-15 USD (based on execution time and requests)"
    event_grid              = "1-5 USD (based on number of events)"
    ai_foundry_s0          = "Variable (based on model usage and tokens)"
    application_insights   = "2-10 USD (based on data ingestion)"
    storage_account        = "1-3 USD (based on storage usage)"
    total_estimated        = "15-25 USD per month for testing workloads"
  }
}

output "resource_tags" {
  description = "The common tags applied to all resources"
  value       = var.resource_tags
}

# Security and Access Information
output "managed_identity_principal_id" {
  description = "The principal ID of the Function App's system-assigned managed identity"
  value       = azurerm_linux_function_app.main.identity[0].principal_id
}

output "ai_foundry_custom_domain" {
  description = "The custom subdomain for the Azure AI Foundry resource"
  value       = azurerm_cognitive_account.ai_foundry.custom_subdomain_name
}

# Deployment Status Information
output "deployment_timestamp" {
  description = "The timestamp when this deployment was completed"
  value       = timestamp()
}

output "terraform_workspace" {
  description = "The Terraform workspace used for this deployment"
  value       = terraform.workspace
}

# Connection Information for External Systems
output "function_app_webhook_url" {
  description = "The Event Grid webhook URL for the Function App"
  value       = "https://${azurerm_linux_function_app.main.default_hostname}/runtime/webhooks/eventgrid?functionName=router_function"
}

output "monitoring_query_url" {
  description = "Direct URL to Application Insights for monitoring function execution"
  value       = "https://portal.azure.com/#@/resource${azurerm_application_insights.main.id}/logs"
}