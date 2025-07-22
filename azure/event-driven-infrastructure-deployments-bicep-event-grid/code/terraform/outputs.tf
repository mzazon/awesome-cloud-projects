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
  description = "ID of the resource group"
  value       = azurerm_resource_group.main.id
}

# Storage Account Information
output "storage_account_name" {
  description = "Name of the storage account for Bicep templates"
  value       = azurerm_storage_account.bicep_templates.name
}

output "storage_account_primary_connection_string" {
  description = "Primary connection string for the storage account"
  value       = azurerm_storage_account.bicep_templates.primary_connection_string
  sensitive   = true
}

output "storage_account_primary_access_key" {
  description = "Primary access key for the storage account"
  value       = azurerm_storage_account.bicep_templates.primary_access_key
  sensitive   = true
}

output "storage_account_primary_blob_endpoint" {
  description = "Primary blob endpoint for the storage account"
  value       = azurerm_storage_account.bicep_templates.primary_blob_endpoint
}

output "bicep_templates_container_name" {
  description = "Name of the container for Bicep templates"
  value       = azurerm_storage_container.bicep_templates.name
}

# Container Registry Information
output "container_registry_name" {
  description = "Name of the Azure Container Registry"
  value       = azurerm_container_registry.main.name
}

output "container_registry_login_server" {
  description = "Login server URL for the Container Registry"
  value       = azurerm_container_registry.main.login_server
}

output "container_registry_admin_username" {
  description = "Admin username for the Container Registry"
  value       = azurerm_container_registry.main.admin_username
  sensitive   = true
}

output "container_registry_admin_password" {
  description = "Admin password for the Container Registry"
  value       = azurerm_container_registry.main.admin_password
  sensitive   = true
}

# Event Grid Information
output "event_grid_topic_name" {
  description = "Name of the Event Grid topic"
  value       = azurerm_eventgrid_topic.deployments.name
}

output "event_grid_topic_endpoint" {
  description = "Endpoint URL for the Event Grid topic"
  value       = azurerm_eventgrid_topic.deployments.endpoint
}

output "event_grid_topic_primary_access_key" {
  description = "Primary access key for the Event Grid topic"
  value       = azurerm_eventgrid_topic.deployments.primary_access_key
  sensitive   = true
}

output "event_grid_topic_secondary_access_key" {
  description = "Secondary access key for the Event Grid topic"
  value       = azurerm_eventgrid_topic.deployments.secondary_access_key
  sensitive   = true
}

output "event_grid_subscription_name" {
  description = "Name of the Event Grid subscription"
  value       = azurerm_eventgrid_event_subscription.deployment_subscription.name
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
  description = "ID of the Key Vault"
  value       = azurerm_key_vault.main.id
}

# Function App Information
output "function_app_name" {
  description = "Name of the Function App"
  value       = azurerm_linux_function_app.event_processor.name
}

output "function_app_default_hostname" {
  description = "Default hostname of the Function App"
  value       = azurerm_linux_function_app.event_processor.default_hostname
}

output "function_app_identity_principal_id" {
  description = "Principal ID of the Function App's managed identity"
  value       = azurerm_linux_function_app.event_processor.identity[0].principal_id
}

output "function_app_identity_tenant_id" {
  description = "Tenant ID of the Function App's managed identity"
  value       = azurerm_linux_function_app.event_processor.identity[0].tenant_id
}

# Monitoring Information
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

# Deployment Information
output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_string.suffix.result
}

output "deployment_ready" {
  description = "Indicates if the deployment automation system is ready"
  value       = "Event-driven infrastructure deployment system successfully configured"
}

# Sample Event for Testing
output "sample_event_json" {
  description = "Sample JSON event for testing the deployment system"
  value = jsonencode([
    {
      id        = "test-001"
      eventType = "Microsoft.EventGrid.CustomEvent"
      subject   = "/deployments/test"
      eventTime = "2025-01-01T12:00:00.000Z"
      data = {
        templateName        = "storage-account"
        targetResourceGroup = azurerm_resource_group.main.name
        parameters = {
          storageAccountName = "sttest${random_string.suffix.result}"
        }
      }
    }
  ])
}

# Curl Command for Event Testing
output "test_event_curl_command" {
  description = "Curl command to test event publishing"
  value = "curl -X POST '${azurerm_eventgrid_topic.deployments.endpoint}' -H 'aeg-sas-key: ${azurerm_eventgrid_topic.deployments.primary_access_key}' -H 'Content-Type: application/json' -d '${jsonencode([
    {
      id        = "test-001"
      eventType = "Microsoft.EventGrid.CustomEvent"
      subject   = "/deployments/test"
      eventTime = "2025-01-01T12:00:00.000Z"
      data = {
        templateName        = "storage-account"
        targetResourceGroup = azurerm_resource_group.main.name
        parameters = {
          storageAccountName = "sttest${random_string.suffix.result}"
        }
      }
    }
  ])}'"
  sensitive = true
}

# Important URLs and Endpoints
output "important_urls" {
  description = "Important URLs for accessing and managing the deployment system"
  value = {
    azure_portal_resource_group = "https://portal.azure.com/#@/resource/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${azurerm_resource_group.main.name}/overview"
    event_grid_topic           = "https://portal.azure.com/#@/resource${azurerm_eventgrid_topic.deployments.id}/overview"
    function_app               = "https://portal.azure.com/#@/resource${azurerm_linux_function_app.event_processor.id}/overview"
    container_registry         = "https://portal.azure.com/#@/resource${azurerm_container_registry.main.id}/overview"
    key_vault                  = "https://portal.azure.com/#@/resource${azurerm_key_vault.main.id}/overview"
    storage_account            = "https://portal.azure.com/#@/resource${azurerm_storage_account.bicep_templates.id}/overview"
    log_analytics              = "https://portal.azure.com/#@/resource${azurerm_log_analytics_workspace.main.id}/overview"
    application_insights       = "https://portal.azure.com/#@/resource${azurerm_application_insights.main.id}/overview"
  }
}

# Next Steps Instructions
output "next_steps" {
  description = "Instructions for completing the deployment automation setup"
  value = <<-EOT
## Next Steps to Complete Setup:

1. **Deploy Function Code:**
   - Create an Azure Function with Event Grid trigger
   - Implement deployment logic using Azure CLI/PowerShell
   - Deploy function code to: ${azurerm_linux_function_app.event_processor.name}

2. **Upload Bicep Templates:**
   - Upload your Bicep templates to: ${azurerm_storage_account.bicep_templates.name}/bicep-templates
   - Ensure templates follow naming convention expected by your function

3. **Test the System:**
   - Use the provided curl command to test event publishing
   - Monitor Function App logs for deployment execution
   - Check target resource groups for deployed resources

4. **Configure Monitoring:**
   - Set up alerts in Application Insights: ${azurerm_application_insights.main.name}
   - Configure Log Analytics queries for deployment tracking
   - Set up Azure Monitor dashboards for operational visibility

5. **Security Hardening:**
   - Review and adjust Key Vault access policies
   - Configure network restrictions if needed
   - Enable Azure Policy for governance compliance

## Testing Command:
${sensitive(one(values({
  test_command = "curl -X POST '${azurerm_eventgrid_topic.deployments.endpoint}' -H 'aeg-sas-key: [KEY]' -H 'Content-Type: application/json' -d '[EVENT_JSON]'"
})))}
EOT
}