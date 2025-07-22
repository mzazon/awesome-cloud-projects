# Core Infrastructure Outputs
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Location of the created resource group"
  value       = azurerm_resource_group.main.location
}

output "random_suffix" {
  description = "Random suffix used for unique resource names"
  value       = random_string.suffix.result
}

# Container Registry Outputs
output "container_registry_name" {
  description = "Name of the Azure Container Registry"
  value       = azurerm_container_registry.acr.name
}

output "container_registry_login_server" {
  description = "Login server URL for the Azure Container Registry"
  value       = azurerm_container_registry.acr.login_server
}

output "container_registry_admin_username" {
  description = "Admin username for the Azure Container Registry"
  value       = azurerm_container_registry.acr.admin_username
  sensitive   = true
}

output "container_registry_admin_password" {
  description = "Admin password for the Azure Container Registry"
  value       = azurerm_container_registry.acr.admin_password
  sensitive   = true
}

# Communication Services Outputs
output "communication_service_name" {
  description = "Name of the Azure Communication Services resource"
  value       = azurerm_communication_service.main.name
}

output "communication_service_primary_connection_string" {
  description = "Primary connection string for Azure Communication Services"
  value       = azurerm_communication_service.main.primary_connection_string
  sensitive   = true
}

output "communication_service_secondary_connection_string" {
  description = "Secondary connection string for Azure Communication Services"
  value       = azurerm_communication_service.main.secondary_connection_string
  sensitive   = true
}

output "communication_service_data_location" {
  description = "Data location for Azure Communication Services"
  value       = azurerm_communication_service.main.data_location
}

# Storage Account Outputs
output "storage_account_name" {
  description = "Name of the storage account for call recordings"
  value       = azurerm_storage_account.recordings.name
}

output "storage_account_primary_connection_string" {
  description = "Primary connection string for the storage account"
  value       = azurerm_storage_account.recordings.primary_connection_string
  sensitive   = true
}

output "storage_account_secondary_connection_string" {
  description = "Secondary connection string for the storage account"
  value       = azurerm_storage_account.recordings.secondary_connection_string
  sensitive   = true
}

output "storage_account_primary_blob_endpoint" {
  description = "Primary blob endpoint for the storage account"
  value       = azurerm_storage_account.recordings.primary_blob_endpoint
}

output "storage_container_name" {
  description = "Name of the storage container for recordings"
  value       = azurerm_storage_container.recordings.name
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

output "app_service_plan_worker_count" {
  description = "Number of worker instances in the App Service Plan"
  value       = azurerm_service_plan.main.worker_count
}

# Web App Outputs
output "web_app_name" {
  description = "Name of the Web App"
  value       = azurerm_linux_web_app.main.name
}

output "web_app_id" {
  description = "ID of the Web App"
  value       = azurerm_linux_web_app.main.id
}

output "web_app_default_hostname" {
  description = "Default hostname of the Web App"
  value       = azurerm_linux_web_app.main.default_hostname
}

output "web_app_url" {
  description = "URL of the Web App"
  value       = "https://${azurerm_linux_web_app.main.default_hostname}"
}

output "web_app_identity_principal_id" {
  description = "Principal ID of the Web App's managed identity"
  value       = azurerm_linux_web_app.main.identity[0].principal_id
}

output "web_app_identity_tenant_id" {
  description = "Tenant ID of the Web App's managed identity"
  value       = azurerm_linux_web_app.main.identity[0].tenant_id
}

# Application Insights Outputs
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

output "application_insights_app_id" {
  description = "Application ID for Application Insights"
  value       = azurerm_application_insights.main.app_id
}

# Log Analytics Workspace Outputs
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics Workspace"
  value       = azurerm_log_analytics_workspace.main.name
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics Workspace"
  value       = azurerm_log_analytics_workspace.main.id
}

output "log_analytics_workspace_customer_id" {
  description = "Customer ID of the Log Analytics Workspace"
  value       = azurerm_log_analytics_workspace.main.workspace_id
}

# Auto-scaling Outputs
output "autoscale_setting_name" {
  description = "Name of the auto-scaling setting"
  value       = var.autoscale_enabled ? azurerm_monitor_autoscale_setting.main[0].name : null
}

output "autoscale_setting_id" {
  description = "ID of the auto-scaling setting"
  value       = var.autoscale_enabled ? azurerm_monitor_autoscale_setting.main[0].id : null
}

output "autoscale_min_instances" {
  description = "Minimum number of instances for auto-scaling"
  value       = var.autoscale_min_instances
}

output "autoscale_max_instances" {
  description = "Maximum number of instances for auto-scaling"
  value       = var.autoscale_max_instances
}

output "autoscale_default_instances" {
  description = "Default number of instances for auto-scaling"
  value       = var.autoscale_default_instances
}

# Monitoring Outputs
output "action_group_name" {
  description = "Name of the monitoring action group"
  value       = azurerm_monitor_action_group.main.name
}

output "action_group_id" {
  description = "ID of the monitoring action group"
  value       = azurerm_monitor_action_group.main.id
}

output "high_cpu_alert_name" {
  description = "Name of the high CPU alert"
  value       = azurerm_monitor_metric_alert.high_cpu.name
}

output "high_memory_alert_name" {
  description = "Name of the high memory alert"
  value       = azurerm_monitor_metric_alert.high_memory.name
}

output "response_time_alert_name" {
  description = "Name of the response time alert"
  value       = azurerm_monitor_metric_alert.response_time.name
}

# Private Endpoint Outputs (if enabled)
output "private_endpoint_storage_id" {
  description = "ID of the storage account private endpoint"
  value       = var.enable_private_endpoint ? azurerm_private_endpoint.storage[0].id : null
}

output "virtual_network_id" {
  description = "ID of the virtual network"
  value       = var.enable_private_endpoint ? azurerm_virtual_network.main[0].id : null
}

output "private_endpoints_subnet_id" {
  description = "ID of the private endpoints subnet"
  value       = var.enable_private_endpoint ? azurerm_subnet.private_endpoints[0].id : null
}

# Container Image Outputs
output "container_image_name" {
  description = "Name of the container image"
  value       = var.container_image_name
}

output "container_image_tag" {
  description = "Tag of the container image"
  value       = var.container_image_tag
}

output "container_image_full_name" {
  description = "Full name of the container image including registry"
  value       = "${azurerm_container_registry.acr.login_server}/${var.container_image_name}:${var.container_image_tag}"
}

# Quick Start Information
output "quick_start_info" {
  description = "Quick start information for the deployment"
  value = {
    web_app_url                    = "https://${azurerm_linux_web_app.main.default_hostname}"
    health_check_url               = "https://${azurerm_linux_web_app.main.default_hostname}/health"
    token_endpoint                 = "https://${azurerm_linux_web_app.main.default_hostname}/token"
    container_registry_login_server = azurerm_container_registry.acr.login_server
    storage_account_name           = azurerm_storage_account.recordings.name
    communication_service_name     = azurerm_communication_service.main.name
    application_insights_name      = azurerm_application_insights.main.name
  }
}

# Deployment Commands
output "deployment_commands" {
  description = "Useful commands for deployment and management"
  value = {
    build_container = "docker build -t ${azurerm_container_registry.acr.login_server}/${var.container_image_name}:${var.container_image_tag} ."
    login_acr      = "az acr login --name ${azurerm_container_registry.acr.name}"
    push_container = "docker push ${azurerm_container_registry.acr.login_server}/${var.container_image_name}:${var.container_image_tag}"
    restart_webapp = "az webapp restart --name ${azurerm_linux_web_app.main.name} --resource-group ${azurerm_resource_group.main.name}"
    view_logs      = "az webapp log tail --name ${azurerm_linux_web_app.main.name} --resource-group ${azurerm_resource_group.main.name}"
  }
}

# Cost Estimation Information
output "cost_estimation" {
  description = "Estimated monthly costs for the deployed resources"
  value = {
    app_service_plan = "App Service Plan (${var.app_service_plan_sku}): ~$73-146/month"
    container_registry = "Container Registry (${var.container_registry_sku}): ~$5-20/month"
    storage_account = "Storage Account: ~$1-5/month (depends on usage)"
    communication_services = "Communication Services: Pay-per-use (depends on usage)"
    application_insights = "Application Insights: ~$2-10/month (depends on usage)"
    total_estimated = "Total estimated: ~$80-200/month (excluding usage-based charges)"
    note = "Costs may vary based on actual usage, region, and current pricing"
  }
}

# Security Information
output "security_info" {
  description = "Security-related information for the deployment"
  value = {
    web_app_identity_enabled = "System-assigned managed identity enabled for Web App"
    https_only_enabled      = var.web_app_https_only
    storage_private_access  = "Storage container has private access"
    container_registry_admin = var.container_registry_admin_enabled ? "Admin user enabled" : "Admin user disabled"
    private_endpoints_enabled = var.enable_private_endpoint
    ftps_state             = var.web_app_ftps_state
  }
}

# Monitoring Information
output "monitoring_info" {
  description = "Monitoring and alerting information"
  value = {
    application_insights_enabled = "Application Insights monitoring enabled"
    log_analytics_retention     = "${var.log_retention_days} days"
    autoscaling_enabled         = var.autoscale_enabled
    cpu_threshold_out          = "${var.autoscale_cpu_threshold_out}%"
    cpu_threshold_in           = "${var.autoscale_cpu_threshold_in}%"
    alerts_configured          = "High CPU, High Memory, and Response Time alerts configured"
  }
}