# Output values for the cost-optimized content generation infrastructure
# These outputs provide essential information for verification, integration, and operational use

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
  description = "Full resource ID of the resource group"
  value       = azurerm_resource_group.main.id
}

# AI Foundry (Cognitive Services) Outputs
output "ai_foundry_name" {
  description = "Name of the Azure AI Foundry resource"
  value       = azurerm_cognitive_account.ai_foundry.name
}

output "ai_foundry_endpoint" {
  description = "Endpoint URL for the AI Foundry resource"
  value       = azurerm_cognitive_account.ai_foundry.endpoint
}

output "ai_foundry_id" {
  description = "Resource ID of the AI Foundry resource"
  value       = azurerm_cognitive_account.ai_foundry.id
}

output "ai_foundry_principal_id" {
  description = "Principal ID of the AI Foundry managed identity"
  value       = azurerm_cognitive_account.ai_foundry.identity[0].principal_id
}

# Model Router Deployment Information
output "model_router_deployment_name" {
  description = "Name of the Model Router deployment"
  value       = azurerm_cognitive_deployment.model_router.name
}

output "model_router_capacity" {
  description = "Capacity of the Model Router deployment"
  value       = azurerm_cognitive_deployment.model_router.scale[0].capacity
}

# Storage Account Outputs
output "storage_account_name" {
  description = "Name of the storage account"
  value       = azurerm_storage_account.main.name
}

output "storage_account_id" {
  description = "Resource ID of the storage account"
  value       = azurerm_storage_account.main.id
}

output "storage_account_primary_endpoint" {
  description = "Primary blob endpoint of the storage account"
  value       = azurerm_storage_account.main.primary_blob_endpoint
}

output "storage_containers" {
  description = "Names of the created storage containers"
  value = {
    content_requests   = azurerm_storage_container.content_requests.name
    generated_content = azurerm_storage_container.generated_content.name
  }
}

# Function App Outputs
output "function_app_name" {
  description = "Name of the Function App"
  value       = local.function_app.name
}

output "function_app_id" {
  description = "Resource ID of the Function App"
  value       = local.function_app.id
}

output "function_app_default_hostname" {
  description = "Default hostname of the Function App"
  value       = local.function_app.default_hostname
}

output "function_app_principal_id" {
  description = "Principal ID of the Function App managed identity"
  value       = local.function_app.identity[0].principal_id
}

output "function_app_kind" {
  description = "Kind of the Function App (FunctionApp or functionapp,linux)"
  value       = local.function_app.kind
}

# Service Plan Outputs
output "service_plan_name" {
  description = "Name of the App Service Plan"
  value       = azurerm_service_plan.main.name
}

output "service_plan_id" {
  description = "Resource ID of the App Service Plan"
  value       = azurerm_service_plan.main.id
}

output "service_plan_sku" {
  description = "SKU of the App Service Plan"
  value       = azurerm_service_plan.main.sku_name
}

# Application Insights Outputs
output "application_insights_name" {
  description = "Name of the Application Insights resource"
  value       = azurerm_application_insights.main.name
}

output "application_insights_id" {
  description = "Resource ID of Application Insights"
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

# Log Analytics Workspace Outputs
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics Workspace"
  value       = azurerm_log_analytics_workspace.main.name
}

output "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics Workspace"
  value       = azurerm_log_analytics_workspace.main.id
}

output "log_analytics_workspace_workspace_id" {
  description = "Workspace ID of the Log Analytics Workspace"
  value       = azurerm_log_analytics_workspace.main.workspace_id
}

# Event Grid Outputs
output "eventgrid_system_topic_name" {
  description = "Name of the Event Grid System Topic"
  value       = azurerm_eventgrid_system_topic.storage.name
}

output "eventgrid_system_topic_id" {
  description = "Resource ID of the Event Grid System Topic"
  value       = azurerm_eventgrid_system_topic.storage.id
}

output "eventgrid_subscription_name" {
  description = "Name of the Event Grid subscription"
  value       = azurerm_eventgrid_event_subscription.content_processing.name
}

output "eventgrid_subscription_id" {
  description = "Resource ID of the Event Grid subscription"
  value       = azurerm_eventgrid_event_subscription.content_processing.id
}

# Monitoring and Alerting Outputs
output "action_group_name" {
  description = "Name of the Action Group for budget alerts"
  value       = azurerm_monitor_action_group.budget_alerts.name
}

output "action_group_id" {
  description = "Resource ID of the Action Group"
  value       = azurerm_monitor_action_group.budget_alerts.id
}

output "budget_name" {
  description = "Name of the consumption budget"
  value       = azurerm_consumption_budget_resource_group.main.name
}

output "budget_amount" {
  description = "Budget amount in USD"
  value       = azurerm_consumption_budget_resource_group.main.amount
}

# Security and Access Information
output "role_assignments" {
  description = "Information about created role assignments"
  value = {
    function_ai_foundry = {
      scope = azurerm_role_assignment.function_ai_foundry.scope
      role  = azurerm_role_assignment.function_ai_foundry.role_definition_name
    }
    function_storage = {
      scope = azurerm_role_assignment.function_storage.scope
      role  = azurerm_role_assignment.function_storage.role_definition_name
    }
  }
}

# Configuration Values for Integration
output "function_app_settings" {
  description = "Key application settings for the Function App (non-sensitive values only)"
  value = {
    functions_extension_version = "~4"
    functions_worker_runtime    = var.function_app_runtime
    ai_foundry_endpoint        = azurerm_cognitive_account.ai_foundry.endpoint
    model_deployment_name      = azurerm_cognitive_deployment.model_router.name
    storage_account_name       = azurerm_storage_account.main.name
    application_insights_name  = azurerm_application_insights.main.name
  }
}

# Deployment Configuration
output "deployment_configuration" {
  description = "Configuration details for the deployment"
  value = {
    project_name                = var.project_name
    environment                = var.environment
    location                   = var.location
    random_suffix              = random_string.suffix.result
    function_app_os_type       = var.function_app_os_type
    function_app_runtime       = var.function_app_runtime
    function_app_runtime_version = var.function_app_runtime_version
    storage_account_tier       = var.storage_account_tier
    storage_replication_type   = var.storage_replication_type
    ai_foundry_sku            = var.ai_foundry_sku
    model_router_capacity     = var.model_router_capacity
  }
}

# URLs and Endpoints for Testing
output "testing_endpoints" {
  description = "Endpoints and URLs for testing the deployment"
  value = {
    function_app_url           = "https://${local.function_app.default_hostname}"
    azure_portal_function_app  = "https://portal.azure.com/#@/resource${local.function_app.id}"
    azure_portal_storage      = "https://portal.azure.com/#@/resource${azurerm_storage_account.main.id}"
    azure_portal_ai_foundry   = "https://portal.azure.com/#@/resource${azurerm_cognitive_account.ai_foundry.id}"
    application_insights_portal = "https://portal.azure.com/#@/resource${azurerm_application_insights.main.id}"
  }
}

# Cost Information
output "cost_information" {
  description = "Cost-related information for the deployment"
  value = {
    budget_amount              = var.budget_amount
    budget_alert_threshold     = var.budget_alert_threshold
    service_plan_sku          = azurerm_service_plan.main.sku_name
    storage_tier              = var.storage_account_tier
    storage_replication       = var.storage_replication_type
    ai_foundry_sku           = var.ai_foundry_sku
    model_router_capacity    = var.model_router_capacity
    estimated_monthly_cost   = "Varies based on usage. Function Apps on Consumption plan: ~$0-10/month, Storage: ~$1-5/month, AI Foundry: Depends on API calls and model selection."
  }
}

# Command-line helpers
output "cli_commands" {
  description = "Useful CLI commands for managing the deployment"
  value = {
    upload_test_content = "az storage blob upload --file sample-request.json --container-name content-requests --name test-request.json --account-name ${azurerm_storage_account.main.name}"
    view_function_logs  = "az functionapp log tail --name ${local.function_app.name} --resource-group ${azurerm_resource_group.main.name}"
    restart_function_app = "az functionapp restart --name ${local.function_app.name} --resource-group ${azurerm_resource_group.main.name}"
    check_budget_status = "az consumption budget show --budget-name ${azurerm_consumption_budget_resource_group.main.name} --resource-group ${azurerm_resource_group.main.name}"
  }
}

# Summary of Created Resources
output "resource_summary" {
  description = "Summary of all created resources"
  value = {
    resource_group        = azurerm_resource_group.main.name
    ai_foundry           = azurerm_cognitive_account.ai_foundry.name
    model_router         = azurerm_cognitive_deployment.model_router.name
    storage_account      = azurerm_storage_account.main.name
    function_app         = local.function_app.name
    service_plan         = azurerm_service_plan.main.name
    application_insights = azurerm_application_insights.main.name
    log_analytics       = azurerm_log_analytics_workspace.main.name
    eventgrid_topic     = azurerm_eventgrid_system_topic.storage.name
    eventgrid_subscription = azurerm_eventgrid_event_subscription.content_processing.name
    action_group        = azurerm_monitor_action_group.budget_alerts.name
    budget              = azurerm_consumption_budget_resource_group.main.name
    total_resources     = "12+ resources created"
  }
}