# Output Values for Azure Notification Hubs Infrastructure
# These outputs provide essential information for connecting applications and services

# Resource Group Information
output "resource_group_name" {
  description = "Name of the created resource group containing all notification hub resources"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Azure region where the resource group and all resources are deployed"
  value       = azurerm_resource_group.main.location
}

output "resource_group_id" {
  description = "Unique identifier for the resource group"
  value       = azurerm_resource_group.main.id
}

# Notification Hub Namespace Information
output "notification_hub_namespace_name" {
  description = "Name of the notification hub namespace providing messaging endpoint"
  value       = azurerm_notification_hub_namespace.main.name
}

output "notification_hub_namespace_id" {
  description = "Unique identifier for the notification hub namespace"
  value       = azurerm_notification_hub_namespace.main.id
}

output "notification_hub_namespace_sku" {
  description = "SKU tier of the notification hub namespace"
  value       = azurerm_notification_hub_namespace.main.namespace_type
}

output "notification_hub_namespace_servicebus_endpoint" {
  description = "Service Bus endpoint URL for the notification hub namespace"
  value       = azurerm_notification_hub_namespace.main.servicebus_endpoint
}

# Notification Hub Information
output "notification_hub_name" {
  description = "Name of the notification hub for device registration and message delivery"
  value       = azurerm_notification_hub.main.name
}

output "notification_hub_id" {
  description = "Unique identifier for the notification hub"
  value       = azurerm_notification_hub.main.id
}

# Authorization and Connection Information
# These connection strings are essential for application integration

output "listen_connection_string" {
  description = "Connection string for client applications to register with the notification hub (listen permissions only)"
  value       = data.azurerm_notification_hub_authorization_rule.listen.primary_connection_string
  sensitive   = true
}

output "listen_connection_string_secondary" {
  description = "Secondary connection string for client applications (listen permissions only)"
  value       = data.azurerm_notification_hub_authorization_rule.listen.secondary_connection_string
  sensitive   = true
}

output "full_access_connection_string" {
  description = "Connection string for back-end applications to send notifications (full permissions)"
  value       = data.azurerm_notification_hub_authorization_rule.full.primary_connection_string
  sensitive   = true
}

output "full_access_connection_string_secondary" {
  description = "Secondary connection string for back-end applications (full permissions)"
  value       = data.azurerm_notification_hub_authorization_rule.full.secondary_connection_string
  sensitive   = true
}

# Access Keys for Authorization Rules
output "listen_primary_access_key" {
  description = "Primary access key for listen authorization rule"
  value       = data.azurerm_notification_hub_authorization_rule.listen.primary_access_key
  sensitive   = true
}

output "full_access_primary_access_key" {
  description = "Primary access key for full access authorization rule"
  value       = data.azurerm_notification_hub_authorization_rule.full.primary_access_key
  sensitive   = true
}

# Deployment Information
output "deployment_summary" {
  description = "Summary of deployed notification hub infrastructure"
  value = {
    resource_group_name           = azurerm_resource_group.main.name
    notification_hub_namespace    = azurerm_notification_hub_namespace.main.name
    notification_hub_name        = azurerm_notification_hub.main.name
    location                     = azurerm_resource_group.main.location
    sku                          = azurerm_notification_hub_namespace.main.namespace_type
    servicebus_endpoint          = azurerm_notification_hub_namespace.main.servicebus_endpoint
    deployment_timestamp         = timestamp()
  }
}

# Instructions for developers
output "next_steps" {
  description = "Instructions for using the deployed notification hub"
  value = <<-EOT
    Your Azure Notification Hub has been successfully deployed!
    
    Next steps:
    1. Configure platform credentials (APNS, FCM, WNS) in the Azure portal
    2. Use the listen connection string in your mobile applications for device registration
    3. Use the full access connection string in your back-end services for sending notifications
    4. Test notification delivery using Azure CLI or portal
    
    Important security notes:
    - Keep connection strings secure and never expose them in client-side code
    - Use the listen connection string for client applications (minimum required permissions)
    - Use the full access connection string only in trusted server environments
    
    Useful Azure CLI commands:
    - List notification hubs: az notification-hub list --resource-group ${azurerm_resource_group.main.name} --namespace-name ${azurerm_notification_hub_namespace.main.name}
    - Send test notification: az notification-hub test-send --resource-group ${azurerm_resource_group.main.name} --namespace-name ${azurerm_notification_hub_namespace.main.name} --notification-hub-name ${azurerm_notification_hub.main.name} --notification-format template --message "Test notification"
  EOT
}