# Outputs for Azure Multi-Modal Content Generation Infrastructure

# Resource Group Information
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Location of the resource group"
  value       = azurerm_resource_group.main.location
}

# Storage Account Information
output "storage_account_name" {
  description = "Name of the storage account"
  value       = azurerm_storage_account.main.name
}

output "storage_account_primary_endpoint" {
  description = "Primary blob endpoint of the storage account"
  value       = azurerm_storage_account.main.primary_blob_endpoint
}

output "storage_containers" {
  description = "Created storage containers for content"
  value = {
    generated_content = azurerm_storage_container.generated_content.name
    text_content     = azurerm_storage_container.text_content.name
    image_content    = azurerm_storage_container.image_content.name
    audio_content    = azurerm_storage_container.audio_content.name
    dead_letter      = azurerm_storage_container.dead_letter_events.name
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

# Container Registry Information
output "container_registry_name" {
  description = "Name of the Azure Container Registry"
  value       = azurerm_container_registry.main.name
}

output "container_registry_login_server" {
  description = "Login server URL of the Azure Container Registry"
  value       = azurerm_container_registry.main.login_server
}

output "container_registry_id" {
  description = "Resource ID of the Azure Container Registry"
  value       = azurerm_container_registry.main.id
}

# Azure AI Foundry Information
output "ai_foundry_hub_name" {
  description = "Name of the Azure AI Foundry Hub"
  value       = azurerm_machine_learning_workspace.hub.name
}

output "ai_foundry_hub_id" {
  description = "Resource ID of the Azure AI Foundry Hub"
  value       = azurerm_machine_learning_workspace.hub.id
}

output "ai_foundry_hub_workspace_url" {
  description = "Workspace URL of the Azure AI Foundry Hub"
  value       = azurerm_machine_learning_workspace.hub.workspace_url
}

output "ai_foundry_project_name" {
  description = "Name of the Azure AI Foundry Project"
  value       = azurerm_machine_learning_workspace.project.name
}

output "ai_foundry_project_id" {
  description = "Resource ID of the Azure AI Foundry Project"
  value       = azurerm_machine_learning_workspace.project.id
}

output "ai_foundry_project_workspace_url" {
  description = "Workspace URL of the Azure AI Foundry Project"
  value       = azurerm_machine_learning_workspace.project.workspace_url
}

# Event Grid Information
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

output "event_grid_subscription_name" {
  description = "Name of the Event Grid subscription"
  value       = azurerm_eventgrid_event_subscription.function_subscription.name
}

# Function App Information
output "function_app_name" {
  description = "Name of the Function App"
  value       = azurerm_linux_function_app.main.name
}

output "function_app_id" {
  description = "Resource ID of the Function App"
  value       = azurerm_linux_function_app.main.id
}

output "function_app_default_hostname" {
  description = "Default hostname of the Function App"
  value       = azurerm_linux_function_app.main.default_hostname
}

output "function_app_principal_id" {
  description = "Principal ID of the Function App managed identity"
  value       = azurerm_linux_function_app.main.identity[0].principal_id
}

output "service_plan_name" {
  description = "Name of the App Service Plan"
  value       = azurerm_service_plan.main.name
}

output "service_plan_id" {
  description = "Resource ID of the App Service Plan"
  value       = azurerm_service_plan.main.id
}

# Application Insights Information (if enabled)
output "application_insights_name" {
  description = "Name of Application Insights (if monitoring is enabled)"
  value       = var.enable_monitoring ? azurerm_application_insights.main[0].name : null
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key for Application Insights (if monitoring is enabled)"
  value       = var.enable_monitoring ? azurerm_application_insights.main[0].instrumentation_key : null
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Connection string for Application Insights (if monitoring is enabled)"
  value       = var.enable_monitoring ? azurerm_application_insights.main[0].connection_string : null
  sensitive   = true
}

# Managed Identity Information
output "ai_foundry_hub_principal_id" {
  description = "Principal ID of the Azure AI Foundry Hub managed identity"
  value       = azurerm_machine_learning_workspace.hub.identity[0].principal_id
}

output "ai_foundry_project_principal_id" {
  description = "Principal ID of the Azure AI Foundry Project managed identity"
  value       = azurerm_machine_learning_workspace.project.identity[0].principal_id
}

output "container_registry_principal_id" {
  description = "Principal ID of the Container Registry managed identity"
  value       = azurerm_container_registry.main.identity[0].principal_id
}

# Networking Information (if private endpoints enabled)
output "virtual_network_name" {
  description = "Name of the virtual network (if private endpoints are enabled)"
  value       = var.enable_private_endpoints ? azurerm_virtual_network.main[0].name : null
}

output "virtual_network_id" {
  description = "Resource ID of the virtual network (if private endpoints are enabled)"
  value       = var.enable_private_endpoints ? azurerm_virtual_network.main[0].id : null
}

output "private_endpoints_subnet_id" {
  description = "Resource ID of the private endpoints subnet (if private endpoints are enabled)"
  value       = var.enable_private_endpoints ? azurerm_subnet.private_endpoints[0].id : null
}

# Key Vault Secrets Information
output "key_vault_secrets" {
  description = "Names of secrets stored in Key Vault"
  value = {
    eventgrid_key                = azurerm_key_vault_secret.eventgrid_key.name
    eventgrid_endpoint          = azurerm_key_vault_secret.eventgrid_endpoint.name
    content_coordination_config = azurerm_key_vault_secret.content_coordination_config.name
    storage_connection_string   = azurerm_key_vault_secret.storage_connection_string.name
  }
}

# Configuration Information
output "ai_models_configuration" {
  description = "Configuration for AI models to be deployed"
  value       = var.ai_models_to_deploy
}

output "content_coordination_workflows" {
  description = "Configured content coordination workflows"
  value       = var.content_coordination_config.workflows
}

# Deployment Commands and Next Steps
output "deployment_commands" {
  description = "Useful commands for managing the deployed infrastructure"
  value = {
    # Azure CLI commands for connecting to services
    acr_login = "az acr login --name ${azurerm_container_registry.main.name}"
    
    # Function App deployment
    function_app_deploy = "func azure functionapp publish ${azurerm_linux_function_app.main.name} --python"
    
    # Key Vault access
    key_vault_list_secrets = "az keyvault secret list --vault-name ${azurerm_key_vault.main.name} --output table"
    
    # Event Grid test event
    event_grid_test = "az eventgrid event send --topic-name ${azurerm_eventgrid_topic.main.name} --resource-group ${azurerm_resource_group.main.name} --events '[{\"id\":\"test-001\",\"eventType\":\"content.generation.test\",\"subject\":\"test/workflow\",\"eventTime\":\"$(date -u +\"%Y-%m-%dT%H:%M:%SZ\")\",\"data\":{\"workflow_type\":\"test\",\"message\":\"Testing event delivery\"},\"dataVersion\":\"1.0\"}]'"
    
    # Storage account access
    storage_list_containers = "az storage container list --account-name ${azurerm_storage_account.main.name} --output table"
  }
}

# Environment and Resource Summary
output "deployment_summary" {
  description = "Summary of deployed resources and their purposes"
  value = {
    environment           = var.environment
    project_name         = var.project_name
    total_resources      = "Deployed complete multi-modal content generation infrastructure"
    ai_foundry_enabled   = "Azure AI Foundry Hub and Project for AI model orchestration"
    container_registry   = "Premium ACR with vulnerability scanning and geo-replication (if prod)"
    event_driven         = "Event Grid topic with Function App subscription for workflow automation"
    storage_containers   = "Separate containers for text, image, audio, and general content"
    security_features    = "Key Vault with RBAC, managed identities, and private endpoints (if enabled)"
    monitoring_enabled   = var.enable_monitoring
    private_networking   = var.enable_private_endpoints
  }
}

# URLs for accessing services
output "service_urls" {
  description = "URLs for accessing deployed services"
  value = {
    ai_foundry_hub_studio     = "https://ml.azure.com/workspaces/${azurerm_machine_learning_workspace.hub.workspace_id}/overview"
    ai_foundry_project_studio = "https://ml.azure.com/workspaces/${azurerm_machine_learning_workspace.project.workspace_id}/overview"
    function_app_portal       = "https://portal.azure.com/#@/resource${azurerm_linux_function_app.main.id}/overview"
    container_registry_portal = "https://portal.azure.com/#@/resource${azurerm_container_registry.main.id}/overview"
    key_vault_portal         = "https://portal.azure.com/#@/resource${azurerm_key_vault.main.id}/overview"
    storage_account_portal   = "https://portal.azure.com/#@/resource${azurerm_storage_account.main.id}/overview"
    event_grid_portal        = "https://portal.azure.com/#@/resource${azurerm_eventgrid_topic.main.id}/overview"
  }
}