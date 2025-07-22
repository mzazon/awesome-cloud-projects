# Resource Group outputs
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Location of the resource group"
  value       = azurerm_resource_group.main.location
}

output "resource_group_id" {
  description = "ID of the created resource group"
  value       = azurerm_resource_group.main.id
}

# Container Apps Environment outputs
output "container_apps_environment_name" {
  description = "Name of the Container Apps Environment"
  value       = azurerm_container_app_environment.main.name
}

output "container_apps_environment_id" {
  description = "ID of the Container Apps Environment"
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

# Container Apps Job outputs
output "container_app_job_name" {
  description = "Name of the Container Apps Job"
  value       = azurerm_container_app_job.main.name
}

output "container_app_job_id" {
  description = "ID of the Container Apps Job"
  value       = azurerm_container_app_job.main.id
}

output "container_app_job_latest_revision_name" {
  description = "Latest revision name of the Container Apps Job"
  value       = azurerm_container_app_job.main.latest_revision_name
}

output "container_app_job_latest_revision_fqdn" {
  description = "Latest revision FQDN of the Container Apps Job"
  value       = azurerm_container_app_job.main.latest_revision_fqdn
}

output "container_app_job_outbound_ip_addresses" {
  description = "Outbound IP addresses of the Container Apps Job"
  value       = azurerm_container_app_job.main.outbound_ip_addresses
}

# Service Bus outputs
output "service_bus_namespace_name" {
  description = "Name of the Service Bus namespace"
  value       = azurerm_servicebus_namespace.main.name
}

output "service_bus_namespace_id" {
  description = "ID of the Service Bus namespace"
  value       = azurerm_servicebus_namespace.main.id
}

output "service_bus_namespace_endpoint" {
  description = "Service Bus namespace endpoint"
  value       = azurerm_servicebus_namespace.main.endpoint
}

output "service_bus_namespace_sku" {
  description = "SKU of the Service Bus namespace"
  value       = azurerm_servicebus_namespace.main.sku
}

output "service_bus_queue_name" {
  description = "Name of the Service Bus queue"
  value       = azurerm_servicebus_queue.main.name
}

output "service_bus_queue_id" {
  description = "ID of the Service Bus queue"
  value       = azurerm_servicebus_queue.main.id
}

output "service_bus_connection_string" {
  description = "Primary connection string for the Service Bus namespace"
  value       = data.azurerm_servicebus_namespace_authorization_rule.main.primary_connection_string
  sensitive   = true
}

output "service_bus_connection_string_secondary" {
  description = "Secondary connection string for the Service Bus namespace"
  value       = data.azurerm_servicebus_namespace_authorization_rule.main.secondary_connection_string
  sensitive   = true
}

# Container Registry outputs
output "container_registry_name" {
  description = "Name of the Container Registry"
  value       = azurerm_container_registry.main.name
}

output "container_registry_id" {
  description = "ID of the Container Registry"
  value       = azurerm_container_registry.main.id
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

# Log Analytics outputs
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.name
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.id
}

output "log_analytics_workspace_workspace_id" {
  description = "Workspace ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.workspace_id
}

output "log_analytics_workspace_primary_shared_key" {
  description = "Primary shared key of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.primary_shared_key
  sensitive   = true
}

# Managed Identity outputs
output "user_assigned_identity_name" {
  description = "Name of the user-assigned managed identity"
  value       = azurerm_user_assigned_identity.job_identity.name
}

output "user_assigned_identity_id" {
  description = "ID of the user-assigned managed identity"
  value       = azurerm_user_assigned_identity.job_identity.id
}

output "user_assigned_identity_principal_id" {
  description = "Principal ID of the user-assigned managed identity"
  value       = azurerm_user_assigned_identity.job_identity.principal_id
}

output "user_assigned_identity_client_id" {
  description = "Client ID of the user-assigned managed identity"
  value       = azurerm_user_assigned_identity.job_identity.client_id
}

# Monitoring outputs (conditional)
output "monitor_action_group_id" {
  description = "ID of the monitor action group (if enabled)"
  value       = var.enable_monitoring_alerts ? azurerm_monitor_action_group.main[0].id : null
}

output "job_failure_alert_id" {
  description = "ID of the job failure metric alert (if enabled)"
  value       = var.enable_monitoring_alerts ? azurerm_monitor_metric_alert.job_failure[0].id : null
}

output "queue_depth_alert_id" {
  description = "ID of the queue depth metric alert (if enabled)"
  value       = var.enable_monitoring_alerts ? azurerm_monitor_metric_alert.queue_depth[0].id : null
}

# Deployment information
output "deployment_instructions" {
  description = "Instructions for completing the deployment"
  value = <<-EOT
    Deployment completed successfully! Here are the next steps:
    
    1. Build and push your container image:
       docker build -t ${azurerm_container_registry.main.login_server}/${var.container_image_name} .
       az acr login --name ${azurerm_container_registry.main.name}
       docker push ${azurerm_container_registry.main.login_server}/${var.container_image_name}
    
    2. Test the Service Bus queue:
       az servicebus queue message send \
         --namespace-name ${azurerm_servicebus_namespace.main.name} \
         --queue-name ${var.queue_name} \
         --resource-group ${azurerm_resource_group.main.name} \
         --body "Test message"
    
    3. Monitor job executions:
       az containerapp job execution list \
         --name ${azurerm_container_app_job.main.name} \
         --resource-group ${azurerm_resource_group.main.name}
    
    4. View job logs:
       az containerapp job logs show \
         --name ${azurerm_container_app_job.main.name} \
         --resource-group ${azurerm_resource_group.main.name}
    
    Resources created:
    - Resource Group: ${azurerm_resource_group.main.name}
    - Container Apps Environment: ${azurerm_container_app_environment.main.name}
    - Container Apps Job: ${azurerm_container_app_job.main.name}
    - Service Bus Namespace: ${azurerm_servicebus_namespace.main.name}
    - Service Bus Queue: ${var.queue_name}
    - Container Registry: ${azurerm_container_registry.main.name}
    - Log Analytics Workspace: ${azurerm_log_analytics_workspace.main.name}
    - Managed Identity: ${azurerm_user_assigned_identity.job_identity.name}
  EOT
}

# Cost estimation information
output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown (USD, subject to change)"
  value = {
    container_apps_environment = "~$0.00 (consumption-based)"
    container_apps_job        = "~$0.00 (pay-per-execution)"
    service_bus_standard      = "~$10.00 (base cost + operations)"
    container_registry_basic  = "~$5.00 (storage + operations)"
    log_analytics_workspace   = "~$2.50 (5GB free tier)"
    total_estimated          = "~$17.50 (excluding data transfer and execution costs)"
    note                     = "Actual costs depend on usage patterns, data transfer, and execution frequency"
  }
}

# Quick reference commands
output "useful_commands" {
  description = "Useful Azure CLI commands for managing the deployed resources"
  value = {
    send_test_message = "az servicebus queue message send --namespace-name ${azurerm_servicebus_namespace.main.name} --queue-name ${var.queue_name} --resource-group ${azurerm_resource_group.main.name} --body 'Test message'"
    list_job_executions = "az containerapp job execution list --name ${azurerm_container_app_job.main.name} --resource-group ${azurerm_resource_group.main.name}"
    view_job_logs = "az containerapp job logs show --name ${azurerm_container_app_job.main.name} --resource-group ${azurerm_resource_group.main.name}"
    check_queue_status = "az servicebus queue show --name ${var.queue_name} --namespace-name ${azurerm_servicebus_namespace.main.name} --resource-group ${azurerm_resource_group.main.name}"
    manual_job_trigger = "az containerapp job start --name ${azurerm_container_app_job.main.name} --resource-group ${azurerm_resource_group.main.name}"
  }
}