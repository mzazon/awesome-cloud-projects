# Outputs for the simple file compression Azure solution
# This file defines outputs that provide important information about deployed resources

# Resource Group Outputs
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

# Storage Account Outputs
output "storage_account_name" {
  description = "Name of the storage account"
  value       = azurerm_storage_account.main.name
}

output "storage_account_id" {
  description = "ID of the storage account"
  value       = azurerm_storage_account.main.id
}

output "storage_account_primary_endpoint" {
  description = "Primary blob endpoint of the storage account"
  value       = azurerm_storage_account.main.primary_blob_endpoint
}

output "storage_account_primary_connection_string" {
  description = "Primary connection string for the storage account"
  value       = azurerm_storage_account.main.primary_connection_string
  sensitive   = true
}

output "storage_account_primary_access_key" {
  description = "Primary access key for the storage account"
  value       = azurerm_storage_account.main.primary_access_key
  sensitive   = true
}

# Blob Container Outputs
output "input_container_name" {
  description = "Name of the input blob container"
  value       = azurerm_storage_container.input.name
}

output "input_container_url" {
  description = "URL of the input blob container"
  value       = "${azurerm_storage_account.main.primary_blob_endpoint}${azurerm_storage_container.input.name}"
}

output "output_container_name" {
  description = "Name of the output blob container"
  value       = azurerm_storage_container.output.name
}

output "output_container_url" {
  description = "URL of the output blob container"
  value       = "${azurerm_storage_account.main.primary_blob_endpoint}${azurerm_storage_container.output.name}"
}

# Function App Outputs
output "function_app_name" {
  description = "Name of the Function App"
  value       = azurerm_linux_function_app.main.name
}

output "function_app_id" {
  description = "ID of the Function App"
  value       = azurerm_linux_function_app.main.id
}

output "function_app_default_hostname" {
  description = "Default hostname of the Function App"
  value       = azurerm_linux_function_app.main.default_hostname
}

output "function_app_url" {
  description = "URL of the Function App"
  value       = "https://${azurerm_linux_function_app.main.default_hostname}"
}

output "function_app_identity_principal_id" {
  description = "Principal ID of the Function App's managed identity"
  value       = azurerm_linux_function_app.main.identity[0].principal_id
}

output "function_app_identity_tenant_id" {
  description = "Tenant ID of the Function App's managed identity"
  value       = azurerm_linux_function_app.main.identity[0].tenant_id
}

# App Service Plan Outputs
output "app_service_plan_name" {
  description = "Name of the App Service Plan"
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

# Application Insights Outputs
output "application_insights_name" {
  description = "Name of Application Insights"
  value       = var.enable_monitoring ? azurerm_application_insights.main[0].name : null
}

output "application_insights_id" {
  description = "ID of Application Insights"
  value       = var.enable_monitoring ? azurerm_application_insights.main[0].id : null
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

output "application_insights_app_id" {
  description = "App ID for Application Insights"
  value       = var.enable_monitoring ? azurerm_application_insights.main[0].app_id : null
}

# Log Analytics Workspace Outputs
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = var.enable_monitoring ? azurerm_log_analytics_workspace.main[0].name : null
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace"
  value       = var.enable_monitoring ? azurerm_log_analytics_workspace.main[0].id : null
}

output "log_analytics_workspace_workspace_id" {
  description = "Workspace ID of the Log Analytics workspace"
  value       = var.enable_monitoring ? azurerm_log_analytics_workspace.main[0].workspace_id : null
}

output "log_analytics_workspace_primary_shared_key" {
  description = "Primary shared key for the Log Analytics workspace"
  value       = var.enable_monitoring ? azurerm_log_analytics_workspace.main[0].primary_shared_key : null
  sensitive   = true
}

# Event Grid Outputs
output "event_grid_system_topic_name" {
  description = "Name of the Event Grid system topic"
  value       = azurerm_eventgrid_system_topic.storage.name
}

output "event_grid_system_topic_id" {
  description = "ID of the Event Grid system topic"
  value       = azurerm_eventgrid_system_topic.storage.id
}

output "event_grid_system_topic_endpoint" {
  description = "Endpoint of the Event Grid system topic"
  value       = azurerm_eventgrid_system_topic.storage.metric_arm_resource_id
}

output "event_grid_subscription_name" {
  description = "Name of the Event Grid subscription"
  value       = azurerm_eventgrid_system_topic_event_subscription.blob_events.name
}

output "event_grid_subscription_id" {
  description = "ID of the Event Grid subscription"
  value       = azurerm_eventgrid_system_topic_event_subscription.blob_events.id
}

# Deployment Information Outputs
output "deployment_instructions" {
  description = "Instructions for using the deployed infrastructure"
  value = <<-EOT
    File Compression Service Deployed Successfully!
    
    === Upload Test Files ===
    1. Use Azure CLI to upload files:
       az storage blob upload \
         --account-name ${azurerm_storage_account.main.name} \
         --container-name ${azurerm_storage_container.input.name} \
         --name test-file.txt \
         --file ./local-file.txt \
         --auth-mode login
    
    2. Or use Azure Storage Explorer with connection string:
       ${azurerm_storage_account.main.primary_connection_string}
    
    === Check Compressed Files ===
    az storage blob list \
      --account-name ${azurerm_storage_account.main.name} \
      --container-name ${azurerm_storage_container.output.name} \
      --auth-mode login \
      --output table
    
    === Monitor Function Execution ===
    Function App URL: https://${azurerm_linux_function_app.main.default_hostname}
    ${var.enable_monitoring ? "Application Insights: ${azurerm_application_insights.main[0].name}" : ""}
    
    === Container URLs ===
    Input Container:  ${azurerm_storage_account.main.primary_blob_endpoint}${azurerm_storage_container.input.name}
    Output Container: ${azurerm_storage_account.main.primary_blob_endpoint}${azurerm_storage_container.output.name}
  EOT
}

# Cost Optimization Information
output "cost_optimization_tips" {
  description = "Tips for optimizing costs of the deployed resources"
  value = <<-EOT
    === Cost Optimization Tips ===
    
    1. Storage Account:
       - Current tier: ${var.storage_account_tier} ${var.storage_replication_type}
       - Consider Cool tier for long-term compressed files
       - Enable lifecycle management for automatic tiering
    
    2. Function App:
       - Current plan: ${var.function_app_service_plan_sku}
       - Consumption plan charges only for execution time
       - Monitor execution time and memory usage
    
    3. Monitoring:
       - Application Insights retention: ${var.enable_monitoring ? var.application_insights_retention_days : 0} days
       - Reduce retention period for cost savings
       - Use sampling for high-volume applications
    
    4. Network:
       - Enable CDN for frequently accessed compressed files
       - Use private endpoints for enhanced security (additional cost)
  EOT
}

# Security Configuration Summary
output "security_configuration" {
  description = "Summary of security configurations applied"
  value = <<-EOT
    === Security Configuration ===
    
    Storage Account:
    - HTTPS Only: ${var.enable_https_traffic_only}
    - Minimum TLS: ${var.min_tls_version}
    - Public Access: ${var.allow_nested_items_to_be_public ? "Allowed" : "Disabled"}
    - Network Default Action: ${var.storage_network_default_action}
    
    Function App:
    - Managed Identity: Enabled (System-assigned)
    - Runtime: ${var.function_runtime} ${var.function_runtime_version}
    - OS Type: ${var.function_app_os_type}
    
    Event Grid:
    - System Topic: Storage account events
    - Subscription: Blob creation events only
    - Subject Filter: ${var.event_grid_subject_filter_begins_with}*
  EOT
}

# Testing Commands
output "testing_commands" {
  description = "Commands for testing the file compression functionality"
  value = <<-EOT
    === Testing Commands ===
    
    # Create test file
    echo "This is a test file for compression." > test-file.txt
    
    # Upload test file
    az storage blob upload \
      --account-name ${azurerm_storage_account.main.name} \
      --container-name ${azurerm_storage_container.input.name} \
      --name test-file.txt \
      --file test-file.txt \
      --auth-mode login
    
    # Wait a few seconds, then check compressed files
    az storage blob list \
      --account-name ${azurerm_storage_account.main.name} \
      --container-name ${azurerm_storage_container.output.name} \
      --auth-mode login \
      --output table
    
    # Download and verify compressed file
    az storage blob download \
      --account-name ${azurerm_storage_account.main.name} \
      --container-name ${azurerm_storage_container.output.name} \
      --name test-file.txt.gz \
      --file downloaded-compressed.gz \
      --auth-mode login
    
    # Decompress and verify content
    gunzip downloaded-compressed.gz
    cat downloaded-compressed
    
    # Clean up test files
    rm test-file.txt downloaded-compressed
  EOT
}

# Resource Tags Applied
output "resource_tags" {
  description = "Tags applied to all resources"
  value       = var.tags
}