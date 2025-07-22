# Outputs for Azure secure code execution workflow infrastructure
# Provides important resource information for verification and integration

# Resource Group Information
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Location of the resource group"
  value       = azurerm_resource_group.main.location
}

# Container Apps Environment Information
output "container_apps_environment_name" {
  description = "Name of the Container Apps Environment"
  value       = azurerm_container_app_environment.main.name
}

output "container_apps_environment_id" {
  description = "Resource ID of the Container Apps Environment"
  value       = azurerm_container_app_environment.main.id
}

output "container_apps_environment_default_domain" {
  description = "Default domain of the Container Apps Environment"
  value       = azurerm_container_app_environment.main.default_domain
}

output "container_apps_environment_static_ip_address" {
  description = "Static IP address of the Container Apps Environment"
  value       = azurerm_container_app_environment.main.static_ip_address
}

# Event Grid Topic Information
output "event_grid_topic_name" {
  description = "Name of the Event Grid Topic"
  value       = azurerm_eventgrid_topic.main.name
}

output "event_grid_topic_endpoint" {
  description = "Endpoint URL of the Event Grid Topic"
  value       = azurerm_eventgrid_topic.main.endpoint
}

output "event_grid_topic_id" {
  description = "Resource ID of the Event Grid Topic"
  value       = azurerm_eventgrid_topic.main.id
}

# Event Grid Topic access keys (sensitive)
output "event_grid_topic_primary_access_key" {
  description = "Primary access key for the Event Grid Topic"
  value       = azurerm_eventgrid_topic.main.primary_access_key
  sensitive   = true
}

output "event_grid_topic_secondary_access_key" {
  description = "Secondary access key for the Event Grid Topic"
  value       = azurerm_eventgrid_topic.main.secondary_access_key
  sensitive   = true
}

# Function App Information
output "function_app_name" {
  description = "Name of the Function App"
  value       = azurerm_linux_function_app.main.name
}

output "function_app_hostname" {
  description = "Default hostname of the Function App"
  value       = azurerm_linux_function_app.main.default_hostname
}

output "function_app_id" {
  description = "Resource ID of the Function App"
  value       = azurerm_linux_function_app.main.id
}

output "function_app_principal_id" {
  description = "Principal ID of the Function App's managed identity"
  value       = azurerm_linux_function_app.main.identity[0].principal_id
}

output "function_app_outbound_ip_addresses" {
  description = "Outbound IP addresses of the Function App"
  value       = azurerm_linux_function_app.main.outbound_ip_addresses
}

# Storage Account Information
output "storage_account_name" {
  description = "Name of the Storage Account"
  value       = azurerm_storage_account.main.name
}

output "storage_account_primary_endpoint" {
  description = "Primary blob endpoint of the Storage Account"
  value       = azurerm_storage_account.main.primary_blob_endpoint
}

output "storage_account_id" {
  description = "Resource ID of the Storage Account"
  value       = azurerm_storage_account.main.id
}

# Storage Account connection string (sensitive)
output "storage_account_connection_string" {
  description = "Primary connection string for the Storage Account"
  value       = azurerm_storage_account.main.primary_connection_string
  sensitive   = true
}

# Storage containers
output "storage_containers" {
  description = "Names of created storage containers"
  value = {
    execution_results = azurerm_storage_container.execution_results.name
    execution_logs    = azurerm_storage_container.execution_logs.name
    dead_letter       = azurerm_storage_container.dead_letter.name
  }
}

# Key Vault Information
output "key_vault_name" {
  description = "Name of the Key Vault"
  value       = azurerm_key_vault.main.name
}

output "key_vault_uri" {
  description = "URI of the Key Vault"
  value       = azurerm_key_vault.main.vault_uri
}

output "key_vault_id" {
  description = "Resource ID of the Key Vault"
  value       = azurerm_key_vault.main.id
}

# Log Analytics Workspace Information
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics Workspace"
  value       = azurerm_log_analytics_workspace.main.name
}

output "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics Workspace"
  value       = azurerm_log_analytics_workspace.main.id
}

output "log_analytics_workspace_customer_id" {
  description = "Customer ID (Workspace ID) of the Log Analytics Workspace"
  value       = azurerm_log_analytics_workspace.main.workspace_id
}

# Log Analytics primary shared key (sensitive)
output "log_analytics_primary_shared_key" {
  description = "Primary shared key for the Log Analytics Workspace"
  value       = azurerm_log_analytics_workspace.main.primary_shared_key
  sensitive   = true
}

# Application Insights Information
output "application_insights_name" {
  description = "Name of the Application Insights component"
  value       = azurerm_application_insights.main.name
}

output "application_insights_app_id" {
  description = "App ID of the Application Insights component"
  value       = azurerm_application_insights.main.app_id
}

output "application_insights_connection_string" {
  description = "Connection string for Application Insights"
  value       = azurerm_application_insights.main.connection_string
  sensitive   = true
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key for Application Insights"
  value       = azurerm_application_insights.main.instrumentation_key
  sensitive   = true
}

# Event Grid Subscription Information
output "event_grid_subscription_name" {
  description = "Name of the Event Grid subscription"
  value       = azurerm_eventgrid_event_subscription.main.name
}

output "event_grid_subscription_id" {
  description = "Resource ID of the Event Grid subscription"
  value       = azurerm_eventgrid_event_subscription.main.id
}

# Service Plan Information
output "service_plan_name" {
  description = "Name of the App Service Plan"
  value       = azurerm_service_plan.main.name
}

output "service_plan_id" {
  description = "Resource ID of the App Service Plan"
  value       = azurerm_service_plan.main.id
}

# Random suffix for reference
output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_string.suffix.result
}

# Session Pool Information (Manual Configuration Required)
output "session_pool_instructions" {
  description = "Instructions for creating the session pool manually"
  value = <<-EOT
    Container Apps Session Pools are currently in preview. Create manually using Azure CLI:
    
    az containerapp sessionpool create \
      --name "pool-${var.project_name}-${random_string.suffix.result}" \
      --resource-group "${azurerm_resource_group.main.name}" \
      --location "${var.location}" \
      --environment "${azurerm_container_app_environment.main.name}" \
      --container-type "${var.session_pool_config.container_type}" \
      --max-sessions ${var.session_pool_config.max_sessions} \
      --ready-sessions ${var.session_pool_config.ready_sessions} \
      --cooldown-period ${var.session_pool_config.cooldown_period_seconds} \
      --network-status "${var.session_pool_config.network_status}"
  EOT
}

# Complete deployment verification checklist
output "deployment_verification_checklist" {
  description = "Checklist for verifying the deployment"
  value = <<-EOT
    Deployment Verification Checklist:
    
    1. ✅ Resource Group: ${azurerm_resource_group.main.name}
    2. ✅ Container Apps Environment: ${azurerm_container_app_environment.main.name}
    3. ✅ Event Grid Topic: ${azurerm_eventgrid_topic.main.name}
    4. ✅ Function App: ${azurerm_linux_function_app.main.name}
    5. ✅ Storage Account: ${azurerm_storage_account.main.name}
    6. ✅ Key Vault: ${azurerm_key_vault.main.name}
    7. ✅ Log Analytics: ${azurerm_log_analytics_workspace.main.name}
    8. ✅ Application Insights: ${azurerm_application_insights.main.name}
    9. ⚠️  Session Pool: Manual creation required (see session_pool_instructions)
    10. ✅ Event Grid Subscription: ${azurerm_eventgrid_event_subscription.main.name}
    
    Next Steps:
    - Create session pool manually using provided CLI command
    - Deploy Function App code for session management
    - Test event publishing to Event Grid topic
    - Verify session allocation and code execution
  EOT
}

# Cost estimation information
output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown (USD, approximate)"
  value = <<-EOT
    Estimated Monthly Costs (USD, Development/Testing):
    
    - Function App (Consumption): $0-20 (based on executions)
    - Storage Account: $5-15 (based on data stored and transactions)
    - Container Apps Environment: $0 (Consumption tier)
    - Container Apps Sessions: $30-50 (based on session usage)
    - Event Grid: $1-5 (based on event volume)
    - Key Vault: $3-5 (standard tier)
    - Log Analytics: $5-15 (based on data ingestion)
    - Application Insights: $0-10 (based on telemetry volume)
    
    Total Estimated Range: $44-120/month
    
    Note: Actual costs may vary based on usage patterns, data volume,
    and specific workload requirements. Monitor Azure Cost Management
    for actual spending.
  EOT
}