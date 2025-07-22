# Resource Group outputs
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Location of the created resource group"
  value       = azurerm_resource_group.main.location
}

# Notification Hub outputs
output "notification_hub_namespace_name" {
  description = "Name of the Notification Hub namespace"
  value       = azurerm_notification_hub_namespace.main.name
}

output "notification_hub_name" {
  description = "Name of the Notification Hub"
  value       = azurerm_notification_hub.main.name
}

output "notification_hub_endpoint" {
  description = "Service Bus endpoint for the Notification Hub namespace"
  value       = azurerm_notification_hub_namespace.main.servicebus_endpoint
}

output "notification_hub_connection_string" {
  description = "Primary connection string for the Notification Hub namespace"
  value       = azurerm_notification_hub_namespace.main.default_access_policy[0].primary_connection_string
  sensitive   = true
}

# Azure Spring Apps outputs
output "spring_cloud_service_name" {
  description = "Name of the Azure Spring Cloud service"
  value       = azurerm_spring_cloud_service.main.name
}

output "spring_cloud_app_name" {
  description = "Name of the Spring Cloud application"
  value       = azurerm_spring_cloud_app.notification_api.name
}

output "spring_cloud_app_url" {
  description = "URL of the Spring Cloud application"
  value       = azurerm_spring_cloud_app.notification_api.url
}

output "spring_cloud_app_fqdn" {
  description = "Fully qualified domain name of the Spring Cloud application"
  value       = azurerm_spring_cloud_app.notification_api.fqdn
}

output "spring_cloud_app_identity_principal_id" {
  description = "Principal ID of the Spring Cloud app managed identity"
  value       = azurerm_spring_cloud_app.notification_api.identity[0].principal_id
}

# Key Vault outputs
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

# Application Insights outputs
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

# Log Analytics outputs
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.name
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.id
}

output "log_analytics_workspace_customer_id" {
  description = "Customer ID (workspace ID) of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.workspace_id
}

# API endpoints for testing
output "device_registration_endpoint" {
  description = "Device registration API endpoint"
  value       = "${azurerm_spring_cloud_app.notification_api.url}/api/devices/register"
}

output "notification_send_endpoint" {
  description = "Notification sending API endpoint"
  value       = "${azurerm_spring_cloud_app.notification_api.url}/api/notifications"
}

output "health_check_endpoint" {
  description = "Application health check endpoint"
  value       = "${azurerm_spring_cloud_app.notification_api.url}/actuator/health"
}

# Monitoring outputs
output "monitoring_enabled" {
  description = "Whether monitoring is enabled"
  value       = var.enable_monitoring
}

output "dashboard_url" {
  description = "URL to the monitoring dashboard (if enabled)"
  value       = var.enable_monitoring ? "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/dashboard/arm${azurerm_dashboard.notification_dashboard[0].id}" : "Monitoring not enabled"
}

# Configuration guidance
output "next_steps" {
  description = "Next steps to complete the setup"
  value = <<-EOT
    1. Configure platform credentials in Azure Portal:
       - Navigate to Notification Hub > Platform Settings
       - Configure Apple (APNS), Google (FCM), and Microsoft (WNS) settings
    
    2. Deploy your Spring Boot application:
       - Build your notification service application
       - Deploy using: az spring app deploy --name ${azurerm_spring_cloud_app.notification_api.name} --service ${azurerm_spring_cloud_service.main.name} --artifact-path <your-jar-file>
    
    3. Test the endpoints:
       - Health check: ${azurerm_spring_cloud_app.notification_api.url}/actuator/health
       - Device registration: POST ${azurerm_spring_cloud_app.notification_api.url}/api/devices/register
       - Send notification: POST ${azurerm_spring_cloud_app.notification_api.url}/api/notifications
    
    4. Monitor in Azure Portal:
       - Application Insights: ${azurerm_application_insights.main.name}
       - Log Analytics: ${azurerm_log_analytics_workspace.main.name}
       - Notification Hub metrics: ${azurerm_notification_hub_namespace.main.name}
  EOT
}

# Cost estimation information
output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown (USD)"
  value = {
    notification_hub_standard = "~$10-50 (depends on push volume)"
    spring_apps_s0           = "~$90 (for 1 vCPU, 2GB RAM)"
    application_insights     = "~$5-20 (depends on telemetry volume)"
    key_vault_standard       = "~$3 (for secrets storage)"
    log_analytics           = "~$2-10 (depends on log volume)"
    total_estimated         = "~$110-173 per month"
    note                   = "Costs vary based on usage. Monitor through Azure Cost Management."
  }
}

# Security information
output "security_considerations" {
  description = "Important security considerations"
  value = {
    managed_identity     = "Spring App uses managed identity for Key Vault access"
    key_vault_rbac      = "Key Vault uses RBAC for access control"
    https_only          = "Spring App enforces HTTPS only"
    secret_management   = "Platform credentials stored securely in Key Vault"
    monitoring          = "All activities logged to Application Insights and Log Analytics"
    network_security    = var.environment == "prod" ? "Network Security Group configured for production" : "Consider NSG for production environments"
  }
}