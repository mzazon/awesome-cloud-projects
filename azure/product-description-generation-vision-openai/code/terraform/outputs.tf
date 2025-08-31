# Outputs for Azure Product Description Generation solution
# These outputs provide essential information for connecting to and using the deployed infrastructure

# Resource Group Information
output "resource_group_name" {
  description = "Name of the Azure Resource Group containing all resources"
  value       = azurerm_resource_group.main.name
}

output "resource_group_id" {
  description = "ID of the Azure Resource Group"
  value       = azurerm_resource_group.main.id
}

output "location" {
  description = "Azure region where resources are deployed"
  value       = azurerm_resource_group.main.location
}

# Storage Account Information
output "storage_account_name" {
  description = "Name of the Azure Storage Account for images and descriptions"
  value       = azurerm_storage_account.main.name
}

output "storage_account_id" {
  description = "ID of the Azure Storage Account"
  value       = azurerm_storage_account.main.id
}

output "storage_account_primary_endpoint" {
  description = "Primary blob endpoint for the storage account"
  value       = azurerm_storage_account.main.primary_blob_endpoint
}

output "storage_account_connection_string" {
  description = "Connection string for the storage account (sensitive)"
  value       = azurerm_storage_account.main.primary_connection_string
  sensitive   = true
}

# Storage Container Information
output "input_container_name" {
  description = "Name of the container for product images"
  value       = azurerm_storage_container.input.name
}

output "input_container_url" {
  description = "URL of the input container for product images"
  value       = "${azurerm_storage_account.main.primary_blob_endpoint}${azurerm_storage_container.input.name}"
}

output "output_container_name" {
  description = "Name of the container for generated descriptions"
  value       = azurerm_storage_container.output.name
}

output "output_container_url" {
  description = "URL of the output container for generated descriptions"
  value       = "${azurerm_storage_account.main.primary_blob_endpoint}${azurerm_storage_container.output.name}"
}

# Computer Vision Service Information
output "computer_vision_name" {
  description = "Name of the Computer Vision service"
  value       = azurerm_cognitive_account.computer_vision.name
}

output "computer_vision_endpoint" {
  description = "Endpoint URL for the Computer Vision service"
  value       = azurerm_cognitive_account.computer_vision.endpoint
}

output "computer_vision_id" {
  description = "ID of the Computer Vision service"
  value       = azurerm_cognitive_account.computer_vision.id
}

output "computer_vision_key" {
  description = "Primary access key for Computer Vision service (sensitive)"
  value       = azurerm_cognitive_account.computer_vision.primary_access_key
  sensitive   = true
}

# OpenAI Service Information
output "openai_service_name" {
  description = "Name of the Azure OpenAI service"
  value       = azurerm_cognitive_account.openai.name
}

output "openai_endpoint" {
  description = "Endpoint URL for the Azure OpenAI service"
  value       = azurerm_cognitive_account.openai.endpoint
}

output "openai_service_id" {
  description = "ID of the Azure OpenAI service"
  value       = azurerm_cognitive_account.openai.id
}

output "openai_key" {
  description = "Primary access key for Azure OpenAI service (sensitive)"
  value       = azurerm_cognitive_account.openai.primary_access_key
  sensitive   = true
}

output "openai_model_deployment_name" {
  description = "Name of the deployed OpenAI model"
  value       = azurerm_cognitive_deployment.gpt_model.name
}

output "openai_model_name" {
  description = "Name of the OpenAI model (e.g., gpt-4o)"
  value       = var.openai_model_name
}

output "openai_model_version" {
  description = "Version of the deployed OpenAI model"
  value       = var.openai_model_version
}

# Function App Information
output "function_app_name" {
  description = "Name of the Azure Function App"
  value       = azurerm_linux_function_app.main.name
}

output "function_app_id" {
  description = "ID of the Azure Function App"
  value       = azurerm_linux_function_app.main.id
}

output "function_app_url" {
  description = "Default hostname for the Function App"
  value       = "https://${azurerm_linux_function_app.main.default_hostname}"
}

output "function_app_principal_id" {
  description = "Principal ID of the Function App's managed identity (if enabled)"
  value       = var.enable_managed_identity ? azurerm_linux_function_app.main.identity[0].principal_id : null
}

# Service Plan Information
output "app_service_plan_name" {
  description = "Name of the App Service Plan hosting the Function App"
  value       = azurerm_service_plan.main.name
}

output "app_service_plan_id" {
  description = "ID of the App Service Plan"
  value       = azurerm_service_plan.main.id
}

output "app_service_plan_sku" {
  description = "SKU of the App Service Plan"
  value       = azurerm_service_plan.main.sku_name
}

# Monitoring Information
output "application_insights_name" {
  description = "Name of the Application Insights instance (if enabled)"
  value       = var.enable_application_insights ? azurerm_application_insights.main[0].name : null
}

output "application_insights_instrumentation_key" {
  description = "Application Insights instrumentation key (sensitive)"
  value       = var.enable_application_insights ? azurerm_application_insights.main[0].instrumentation_key : null
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Application Insights connection string (sensitive)"
  value       = var.enable_application_insights ? azurerm_application_insights.main[0].connection_string : null
  sensitive   = true
}

output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics Workspace (if enabled)"
  value       = var.enable_application_insights ? azurerm_log_analytics_workspace.main[0].name : null
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics Workspace (if enabled)"
  value       = var.enable_application_insights ? azurerm_log_analytics_workspace.main[0].id : null
}

# Event Grid Information
output "event_grid_system_topic_name" {
  description = "Name of the Event Grid system topic (if enabled)"
  value       = var.enable_event_grid ? azurerm_eventgrid_system_topic.storage_events[0].name : null
}

output "event_grid_system_topic_id" {
  description = "ID of the Event Grid system topic (if enabled)"
  value       = var.enable_event_grid ? azurerm_eventgrid_system_topic.storage_events[0].id : null
}

output "event_grid_subscription_name" {
  description = "Name of the Event Grid event subscription (if enabled)"
  value       = var.enable_event_grid ? azurerm_eventgrid_event_subscription.function_trigger[0].name : null
}

# Resource Configuration Summary
output "configuration_summary" {
  description = "Summary of key configuration settings"
  value = {
    project_name                = var.project_name
    environment                = var.environment
    location                   = var.location
    computer_vision_sku        = var.computer_vision_sku
    openai_model              = var.openai_model_name
    openai_model_version      = var.openai_model_version
    function_app_runtime      = var.function_app_runtime
    function_app_runtime_version = var.function_app_runtime_version
    storage_tier              = var.storage_account_tier
    storage_replication       = var.storage_account_replication_type
    event_grid_enabled        = var.enable_event_grid
    application_insights_enabled = var.enable_application_insights
    managed_identity_enabled  = var.enable_managed_identity
  }
}

# Quick Start Information
output "quick_start_info" {
  description = "Quick start information for using the deployed solution"
  value = {
    upload_images_to     = "az storage blob upload --account-name ${azurerm_storage_account.main.name} --container-name ${var.input_container_name} --name 'your-image.jpg' --file 'local-image.jpg'"
    check_descriptions   = "az storage blob list --account-name ${azurerm_storage_account.main.name} --container-name ${var.output_container_name} --output table"
    download_description = "az storage blob download --account-name ${azurerm_storage_account.main.name} --container-name ${var.output_container_name} --name 'description_your-image.json' --file 'result.json'"
    function_logs       = "az functionapp logs tail --name ${azurerm_linux_function_app.main.name} --resource-group ${azurerm_resource_group.main.name}"
  }
}

# Testing Information
output "testing_commands" {
  description = "Commands for testing the deployed solution"
  value = {
    # Storage account access
    get_storage_key = "az storage account keys list --account-name ${azurerm_storage_account.main.name} --resource-group ${azurerm_resource_group.main.name} --query '[0].value' --output tsv"
    
    # Upload test image
    upload_test_image = "curl -o test-product.jpg 'https://images.unsplash.com/photo-1542291026-7eec264c27ff?w=800' && az storage blob upload --account-name ${azurerm_storage_account.main.name} --container-name ${var.input_container_name} --name 'test-product.jpg' --file 'test-product.jpg'"
    
    # Monitor processing
    check_function_status = "az functionapp show --name ${azurerm_linux_function_app.main.name} --resource-group ${azurerm_resource_group.main.name} --query 'state' --output tsv"
    
    # View results
    list_generated_files = "az storage blob list --account-name ${azurerm_storage_account.main.name} --container-name ${var.output_container_name} --output table"
    
    # Application Insights queries (if enabled)
    view_logs = var.enable_application_insights ? "az monitor app-insights query --app ${azurerm_application_insights.main[0].app_id} --analytics-query 'traces | where message contains \"ProductDescriptionGenerator\" | order by timestamp desc | limit 50'" : "Application Insights not enabled"
  }
}

# Cost Optimization Information
output "cost_optimization_info" {
  description = "Information about cost optimization features"
  value = {
    consumption_plan        = var.function_app_service_plan_sku == "Y1" ? "Enabled - Pay per execution" : "Premium plan - Fixed cost"
    storage_lifecycle_mgmt  = var.enable_storage_lifecycle_management ? "Enabled - Auto-transitions to cool tier after ${var.cool_tier_transition_days} days" : "Disabled"
    auto_delete_enabled     = var.delete_after_days > 0 ? "Files deleted after ${var.delete_after_days} days" : "Auto-delete disabled"
    storage_tier           = "Hot tier for active processing, transitions to Cool for cost savings"
    ai_service_tiers       = {
      computer_vision = var.computer_vision_sku
      openai_service  = var.openai_sku
    }
  }
}

# Security Information
output "security_features" {
  description = "Information about security features implemented"
  value = {
    https_only              = "Enabled - All traffic encrypted in transit"
    min_tls_version        = "TLS 1.2 minimum required"
    managed_identity       = var.enable_managed_identity ? "Enabled - Passwordless authentication to Azure services" : "Disabled"
    storage_public_access  = "Disabled - Private containers only"
    cognitive_services_access = "API key-based authentication with secure app settings"
    function_app_cors      = "Configured with allowed origins: ${join(", ", var.allowed_origins)}"
  }
}