# Output values for the Serverless AI Agents infrastructure

# Resource Group Information
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Location of the created resource group"
  value       = azurerm_resource_group.main.location
}

# Azure OpenAI Service Information
output "openai_service_name" {
  description = "Name of the Azure OpenAI service"
  value       = azurerm_cognitive_account.openai.name
}

output "openai_service_endpoint" {
  description = "Endpoint URL for the Azure OpenAI service"
  value       = azurerm_cognitive_account.openai.endpoint
}

output "openai_service_key" {
  description = "Primary access key for the Azure OpenAI service"
  value       = azurerm_cognitive_account.openai.primary_access_key
  sensitive   = true
}

output "openai_model_deployment_name" {
  description = "Name of the deployed OpenAI model"
  value       = azurerm_cognitive_deployment.gpt4.name
}

# Azure Container Registry Information
output "container_registry_name" {
  description = "Name of the Azure Container Registry"
  value       = azurerm_container_registry.main.name
}

output "container_registry_login_server" {
  description = "Login server URL for the Azure Container Registry"
  value       = azurerm_container_registry.main.login_server
}

output "container_registry_admin_username" {
  description = "Admin username for the Azure Container Registry"
  value       = azurerm_container_registry.main.admin_username
  sensitive   = true
}

output "container_registry_admin_password" {
  description = "Admin password for the Azure Container Registry"
  value       = azurerm_container_registry.main.admin_password
  sensitive   = true
}

# Storage Account Information
output "storage_account_name" {
  description = "Name of the Azure Storage Account"
  value       = azurerm_storage_account.main.name
}

output "storage_account_primary_connection_string" {
  description = "Primary connection string for the Azure Storage Account"
  value       = azurerm_storage_account.main.primary_connection_string
  sensitive   = true
}

output "storage_account_primary_blob_endpoint" {
  description = "Primary blob endpoint for the Azure Storage Account"
  value       = azurerm_storage_account.main.primary_blob_endpoint
}

output "results_container_name" {
  description = "Name of the storage container for AI agent results"
  value       = azurerm_storage_container.results.name
}

# Event Grid Information
output "event_grid_topic_name" {
  description = "Name of the Event Grid topic"
  value       = azurerm_eventgrid_topic.main.name
}

output "event_grid_topic_endpoint" {
  description = "Endpoint URL for the Event Grid topic"
  value       = azurerm_eventgrid_topic.main.endpoint
}

output "event_grid_topic_key" {
  description = "Primary access key for the Event Grid topic"
  value       = azurerm_eventgrid_topic.main.primary_access_key
  sensitive   = true
}

# Function App Information
output "function_app_name" {
  description = "Name of the Azure Function App"
  value       = azurerm_linux_function_app.main.name
}

output "function_app_default_hostname" {
  description = "Default hostname for the Azure Function App"
  value       = azurerm_linux_function_app.main.default_hostname
}

output "function_app_url" {
  description = "URL for the Azure Function App"
  value       = "https://${azurerm_linux_function_app.main.default_hostname}"
}

output "function_app_api_endpoint" {
  description = "API endpoint for submitting AI agent tasks"
  value       = "https://${azurerm_linux_function_app.main.default_hostname}/api/agent"
}

output "function_app_identity_principal_id" {
  description = "Principal ID of the Function App's managed identity"
  value       = azurerm_linux_function_app.main.identity[0].principal_id
}

# Logic App Information
output "logic_app_name" {
  description = "Name of the Logic App for container orchestration"
  value       = azurerm_logic_app_workflow.aci_orchestrator.name
}

output "logic_app_identity_principal_id" {
  description = "Principal ID of the Logic App's managed identity"
  value       = azurerm_logic_app_workflow.aci_orchestrator.identity[0].principal_id
}

# Application Insights Information (if enabled)
output "application_insights_name" {
  description = "Name of the Application Insights instance"
  value       = var.enable_monitoring ? azurerm_application_insights.main[0].name : null
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key for Application Insights"
  value       = var.enable_monitoring ? azurerm_application_insights.main[0].instrumentation_key : null
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Connection string for Application Insights"
  value       = var.enable_monitoring ? azurerm_application_insights.main[0].connection_string : null
  sensitive   = true
}

# Container Configuration
output "container_image_name" {
  description = "Name of the container image for AI agents"
  value       = local.container_image_name
}

output "container_image_tag" {
  description = "Tag of the container image for AI agents"
  value       = local.container_image_tag
}

output "container_cpu" {
  description = "CPU configuration for container instances"
  value       = var.container_cpu
}

output "container_memory" {
  description = "Memory configuration for container instances"
  value       = var.container_memory
}

# Deployment Information
output "deployment_commands" {
  description = "Commands to deploy the AI agent system"
  value = {
    build_container = "docker build -t ${azurerm_container_registry.main.login_server}/${local.container_image_name}:${local.container_image_tag} ./docker/"
    push_container  = "docker push ${azurerm_container_registry.main.login_server}/${local.container_image_name}:${local.container_image_tag}"
    deploy_function = "func azure functionapp publish ${azurerm_linux_function_app.main.name} --python"
    test_api        = "curl -X POST https://${azurerm_linux_function_app.main.default_hostname}/api/agent -H 'Content-Type: application/json' -d '{\"prompt\": \"Hello, AI agent!\"}'"
  }
}

# Testing Information
output "testing_commands" {
  description = "Commands for testing the AI agent system"
  value = {
    submit_task = "curl -X POST https://${azurerm_linux_function_app.main.default_hostname}/api/agent -H 'Content-Type: application/json' -d '{\"prompt\": \"Analyze the benefits of serverless architectures for AI workloads\"}'"
    check_status = "curl https://${azurerm_linux_function_app.main.default_hostname}/api/agent/{task_id}"
    list_containers = "az container list --resource-group ${azurerm_resource_group.main.name} --output table"
    view_logs = "az container logs --name {container_name} --resource-group ${azurerm_resource_group.main.name}"
  }
}

# Resource Summary
output "resource_summary" {
  description = "Summary of all created resources"
  value = {
    resource_group = azurerm_resource_group.main.name
    openai_service = azurerm_cognitive_account.openai.name
    container_registry = azurerm_container_registry.main.name
    storage_account = azurerm_storage_account.main.name
    event_grid_topic = azurerm_eventgrid_topic.main.name
    function_app = azurerm_linux_function_app.main.name
    logic_app = azurerm_logic_app_workflow.aci_orchestrator.name
    application_insights = var.enable_monitoring ? azurerm_application_insights.main[0].name : "disabled"
  }
}

# Security Information
output "security_notes" {
  description = "Important security considerations for the deployment"
  value = {
    managed_identities = "Function App and Logic App use system-assigned managed identities"
    access_keys = "Access keys are stored in Terraform state - consider using Azure Key Vault for production"
    network_security = "All services use public endpoints - consider private endpoints for production"
    container_security = "Container Registry admin access is enabled - consider using managed identity for production"
    monitoring = var.enable_monitoring ? "Application Insights monitoring is enabled" : "Monitoring is disabled"
  }
}

# Cost Information
output "cost_considerations" {
  description = "Cost considerations for the deployed resources"
  value = {
    openai_service = "Azure OpenAI Service charges based on tokens processed"
    container_instances = "Container Instances charge per second of execution"
    function_app = "Function App uses consumption plan - pay per execution"
    storage_account = "Storage Account charges for storage and transactions"
    event_grid = "Event Grid charges per million events published"
    container_registry = "Container Registry charges for storage and data transfer"
    monitoring = var.enable_monitoring ? "Application Insights charges for data ingestion and retention" : "No monitoring costs"
  }
}