# Resource Group Information
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_id" {
  description = "ID of the created resource group"
  value       = azurerm_resource_group.main.id
}

output "location" {
  description = "Azure region where resources are deployed"
  value       = azurerm_resource_group.main.location
}

# AI Foundry Machine Learning Workspace Information
output "ai_foundry_workspace_name" {
  description = "Name of the AI Foundry Machine Learning workspace"
  value       = azurerm_machine_learning_workspace.main.name
}

output "ai_foundry_workspace_id" {
  description = "ID of the AI Foundry Machine Learning workspace"
  value       = azurerm_machine_learning_workspace.main.id
}

output "ai_foundry_workspace_discovery_url" {
  description = "Discovery URL for the AI Foundry workspace"
  value       = azurerm_machine_learning_workspace.main.discovery_url
}

# Cognitive Services Information
output "cognitive_services_name" {
  description = "Name of the Cognitive Services account"
  value       = azurerm_cognitive_account.main.name
}

output "cognitive_services_endpoint" {
  description = "Endpoint URL for the Cognitive Services account"
  value       = azurerm_cognitive_account.main.endpoint
  sensitive   = false
}

output "cognitive_services_id" {
  description = "ID of the Cognitive Services account"
  value       = azurerm_cognitive_account.main.id
}

# Service Bus Information
output "service_bus_namespace_name" {
  description = "Name of the Service Bus namespace"
  value       = azurerm_servicebus_namespace.main.name
}

output "service_bus_namespace_id" {
  description = "ID of the Service Bus namespace"
  value       = azurerm_servicebus_namespace.main.id
}

output "service_bus_connection_string" {
  description = "Primary connection string for the Service Bus namespace"
  value       = azurerm_servicebus_namespace_authorization_rule.function_app.primary_connection_string
  sensitive   = true
}

output "carbon_data_queue_name" {
  description = "Name of the carbon data queue"
  value       = azurerm_servicebus_queue.carbon_data.name
}

output "analysis_results_queue_name" {
  description = "Name of the analysis results queue"
  value       = azurerm_servicebus_queue.analysis_results.name
}

# Function App Information
output "function_app_name" {
  description = "Name of the Function App"
  value       = azurerm_linux_function_app.main.name
}

output "function_app_id" {
  description = "ID of the Function App"
  value       = azurerm_linux_function_app.main.id
}

output "function_app_url" {
  description = "Default hostname of the Function App"
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

# Storage Account Information
output "storage_account_name" {
  description = "Name of the storage account"
  value       = azurerm_storage_account.main.name
}

output "storage_account_id" {
  description = "ID of the storage account"
  value       = azurerm_storage_account.main.id
}

output "storage_account_primary_blob_endpoint" {
  description = "Primary blob endpoint of the storage account"
  value       = azurerm_storage_account.main.primary_blob_endpoint
}

output "storage_containers" {
  description = "List of created storage containers"
  value = {
    for container in azurerm_storage_container.containers : container.name => {
      name         = container.name
      access_type  = container.container_access_type
      url          = "${azurerm_storage_account.main.primary_blob_endpoint}${container.name}"
    }
  }
}

# Key Vault Information
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
  description = "Name of the Application Insights resource"
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

# Network Information (when private endpoints are enabled)
output "virtual_network_id" {
  description = "ID of the virtual network (when private endpoints are enabled)"
  value       = var.enable_private_endpoints ? azurerm_virtual_network.main[0].id : null
}

output "virtual_network_name" {
  description = "Name of the virtual network (when private endpoints are enabled)"
  value       = var.enable_private_endpoints ? azurerm_virtual_network.main[0].name : null
}

output "subnet_ids" {
  description = "IDs of the created subnets (when private endpoints are enabled)"
  value = var.enable_private_endpoints ? {
    functions = azurerm_subnet.functions[0].id
    ai        = azurerm_subnet.ai[0].id
    data      = azurerm_subnet.data[0].id
  } : {}
}

# Security Information
output "network_security_group_id" {
  description = "ID of the network security group for functions (when private endpoints are enabled)"
  value       = var.enable_private_endpoints ? azurerm_network_security_group.functions[0].id : null
}

# Budget Information
output "budget_name" {
  description = "Name of the budget alert (when monitoring is enabled)"
  value       = var.enable_monitoring ? azurerm_consumption_budget_resource_group.main[0].name : null
}

output "budget_amount" {
  description = "Monthly budget amount configured"
  value       = var.monthly_budget_amount
}

# Alert Information
output "action_group_id" {
  description = "ID of the action group for alerts (when monitoring is enabled)"
  value       = var.enable_monitoring && length(var.alert_email_addresses) > 0 ? azurerm_monitor_action_group.main[0].id : null
}

output "metric_alerts" {
  description = "Information about configured metric alerts"
  value = var.enable_monitoring ? {
    function_app_errors = azurerm_monitor_metric_alert.function_app_errors[0].id
    service_bus_dead_letters = azurerm_monitor_metric_alert.service_bus_dead_letters[0].id
  } : {}
}

# Deployment Information
output "deployment_timestamp" {
  description = "Timestamp of the deployment"
  value       = timestamp()
}

output "terraform_workspace" {
  description = "Terraform workspace used for deployment"
  value       = terraform.workspace
}

# Resource Names for Reference
output "resource_names" {
  description = "All resource names for easy reference"
  value = {
    resource_group         = azurerm_resource_group.main.name
    ai_foundry_workspace   = azurerm_machine_learning_workspace.main.name
    cognitive_services     = azurerm_cognitive_account.main.name
    service_bus_namespace  = azurerm_servicebus_namespace.main.name
    carbon_data_queue      = azurerm_servicebus_queue.carbon_data.name
    analysis_results_queue = azurerm_servicebus_queue.analysis_results.name
    function_app          = azurerm_linux_function_app.main.name
    storage_account       = azurerm_storage_account.main.name
    key_vault             = azurerm_key_vault.main.name
    log_analytics         = azurerm_log_analytics_workspace.main.name
    application_insights  = azurerm_application_insights.main.name
  }
}

# Configuration Summary
output "configuration_summary" {
  description = "Summary of key configuration settings"
  value = {
    location                    = var.location
    environment                 = var.environment
    project_name               = var.project_name
    service_bus_sku            = var.service_bus_sku
    function_app_runtime       = var.function_app_runtime
    function_app_runtime_version = var.function_app_runtime_version
    cognitive_services_sku     = var.cognitive_services_sku
    private_endpoints_enabled  = var.enable_private_endpoints
    monitoring_enabled         = var.enable_monitoring
    budget_amount              = var.monthly_budget_amount
    backup_retention_days      = var.backup_retention_days
  }
}

# Quick Start Information
output "quick_start_info" {
  description = "Quick start information for using the deployed resources"
  value = {
    function_app_url = "https://${azurerm_linux_function_app.main.default_hostname}"
    ai_foundry_portal_url = "https://ml.azure.com/?wsid=${azurerm_machine_learning_workspace.main.id}"
    service_bus_connection_string_secret = "Stored in Key Vault as 'service-bus-connection-string'"
    cognitive_services_key_secret = "Stored in Key Vault as 'cognitive-services-key'"
    storage_account_containers = [for container in azurerm_storage_container.containers : container.name]
    log_analytics_workspace_url = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_log_analytics_workspace.main.id}/logs"
  }
}

# Post-Deployment Instructions
output "post_deployment_instructions" {
  description = "Instructions for post-deployment configuration"
  value = [
    "1. Configure AI agents in the AI Foundry workspace using the provided discovery URL",
    "2. Deploy Function App code for carbon data processing and analysis",
    "3. Set up Power Platform environment for Sustainability Manager integration",
    "4. Configure carbon data sources to send messages to the Service Bus queues",
    "5. Test the end-to-end carbon tracking pipeline",
    "6. Set up monitoring dashboards using Application Insights and Log Analytics",
    "7. Configure additional alert rules based on specific business requirements"
  ]
}

# Security Recommendations
output "security_recommendations" {
  description = "Security recommendations for the deployed infrastructure"
  value = [
    "1. Enable private endpoints for enhanced network security",
    "2. Configure network security groups with specific IP ranges",
    "3. Implement Azure Active Directory authentication for Function Apps",
    "4. Enable diagnostic logging for all services",
    "5. Regularly rotate access keys stored in Key Vault",
    "6. Configure backup and disaster recovery procedures",
    "7. Implement proper RBAC for all resources"
  ]
}

# Cost Optimization Tips
output "cost_optimization_tips" {
  description = "Tips for optimizing costs of the deployed infrastructure"
  value = [
    "1. Use consumption plan for Function Apps if workload is intermittent",
    "2. Configure auto-scaling for Service Bus based on queue depth",
    "3. Implement lifecycle management for storage account blobs",
    "4. Monitor and optimize Application Insights data retention",
    "5. Use Azure reservations for predictable workloads",
    "6. Set up cost alerts and budgets for proactive monitoring",
    "7. Regularly review and optimize resource SKUs based on usage patterns"
  ]
}