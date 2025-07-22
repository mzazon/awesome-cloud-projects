# Output Values for Microservices Choreography Infrastructure
# This file defines all output values that provide important information
# about the deployed infrastructure resources

# Resource Group Information
output "resource_group_name" {
  description = "The name of the created resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "The location of the created resource group"
  value       = azurerm_resource_group.main.location
}

output "resource_group_id" {
  description = "The ID of the created resource group"
  value       = azurerm_resource_group.main.id
}

# Service Bus Information
output "service_bus_namespace_name" {
  description = "The name of the Service Bus namespace"
  value       = azurerm_servicebus_namespace.main.name
}

output "service_bus_namespace_id" {
  description = "The ID of the Service Bus namespace"
  value       = azurerm_servicebus_namespace.main.id
}

output "service_bus_connection_string" {
  description = "The primary connection string for the Service Bus namespace"
  value       = azurerm_servicebus_namespace.main.default_primary_connection_string
  sensitive   = true
}

output "service_bus_primary_key" {
  description = "The primary key for the Service Bus namespace"
  value       = azurerm_servicebus_namespace.main.default_primary_key
  sensitive   = true
}

output "service_bus_endpoint" {
  description = "The endpoint URL for the Service Bus namespace"
  value       = "https://${azurerm_servicebus_namespace.main.name}.servicebus.windows.net/"
}

# Service Bus Topics Information
output "service_bus_topics" {
  description = "Map of created Service Bus topics with their IDs"
  value = {
    for topic_name, topic in azurerm_servicebus_topic.topics : topic_name => {
      id   = topic.id
      name = topic.name
    }
  }
}

# Service Bus Subscriptions Information
output "service_bus_subscriptions" {
  description = "Map of created Service Bus subscriptions with their details"
  value = {
    for sub_name, sub in azurerm_servicebus_subscription.subscriptions : sub_name => {
      id         = sub.id
      name       = sub.name
      topic_name = split("/", sub.topic_id)[length(split("/", sub.topic_id)) - 1]
    }
  }
}

# Dead Letter Queue Information
output "dead_letter_queue" {
  description = "Information about the dead letter queue"
  value = {
    id   = azurerm_servicebus_queue.dead_letter_queue.id
    name = azurerm_servicebus_queue.dead_letter_queue.name
  }
}

# Log Analytics Workspace Information
output "log_analytics_workspace_name" {
  description = "The name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.name
}

output "log_analytics_workspace_id" {
  description = "The ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.id
}

output "log_analytics_workspace_key" {
  description = "The primary shared key for the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.primary_shared_key
  sensitive   = true
}

output "log_analytics_workspace_customer_id" {
  description = "The customer ID (workspace ID) for the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.workspace_id
}

# Application Insights Information
output "application_insights_name" {
  description = "The name of the Application Insights instance"
  value       = azurerm_application_insights.main.name
}

output "application_insights_id" {
  description = "The ID of the Application Insights instance"
  value       = azurerm_application_insights.main.id
}

output "application_insights_instrumentation_key" {
  description = "The instrumentation key for Application Insights"
  value       = azurerm_application_insights.main.instrumentation_key
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "The connection string for Application Insights"
  value       = azurerm_application_insights.main.connection_string
  sensitive   = true
}

output "application_insights_app_id" {
  description = "The App ID for Application Insights"
  value       = azurerm_application_insights.main.app_id
}

# Container Apps Environment Information
output "container_app_environment_name" {
  description = "The name of the Container Apps Environment"
  value       = azurerm_container_app_environment.main.name
}

output "container_app_environment_id" {
  description = "The ID of the Container Apps Environment"
  value       = azurerm_container_app_environment.main.id
}

output "container_app_environment_default_domain" {
  description = "The default domain for the Container Apps Environment"
  value       = azurerm_container_app_environment.main.default_domain
}

# Container Apps Information
output "order_service_url" {
  description = "The URL for the Order Service Container App"
  value       = "https://${azurerm_container_app.order_service.latest_revision_fqdn}"
}

output "order_service_name" {
  description = "The name of the Order Service Container App"
  value       = azurerm_container_app.order_service.name
}

output "order_service_id" {
  description = "The ID of the Order Service Container App"
  value       = azurerm_container_app.order_service.id
}

output "inventory_service_name" {
  description = "The name of the Inventory Service Container App"
  value       = azurerm_container_app.inventory_service.name
}

output "inventory_service_id" {
  description = "The ID of the Inventory Service Container App"
  value       = azurerm_container_app.inventory_service.id
}

output "inventory_service_internal_url" {
  description = "The internal URL for the Inventory Service Container App"
  value       = "https://${azurerm_container_app.inventory_service.latest_revision_fqdn}"
}

# Function Apps Information
output "payment_function_name" {
  description = "The name of the Payment Service Function App"
  value       = azurerm_linux_function_app.payment_service.name
}

output "payment_function_id" {
  description = "The ID of the Payment Service Function App"
  value       = azurerm_linux_function_app.payment_service.id
}

output "payment_function_url" {
  description = "The default hostname for the Payment Service Function App"
  value       = "https://${azurerm_linux_function_app.payment_service.default_hostname}"
}

output "shipping_function_name" {
  description = "The name of the Shipping Service Function App"
  value       = azurerm_linux_function_app.shipping_service.name
}

output "shipping_function_id" {
  description = "The ID of the Shipping Service Function App"
  value       = azurerm_linux_function_app.shipping_service.id
}

output "shipping_function_url" {
  description = "The default hostname for the Shipping Service Function App"
  value       = "https://${azurerm_linux_function_app.shipping_service.default_hostname}"
}

# Storage Account Information
output "function_storage_account_name" {
  description = "The name of the storage account used by Function Apps"
  value       = azurerm_storage_account.function_storage.name
}

output "function_storage_account_id" {
  description = "The ID of the storage account used by Function Apps"
  value       = azurerm_storage_account.function_storage.id
}

output "function_storage_primary_blob_endpoint" {
  description = "The primary blob endpoint for the storage account"
  value       = azurerm_storage_account.function_storage.primary_blob_endpoint
}

# Service Plan Information
output "function_service_plan_name" {
  description = "The name of the service plan for Function Apps"
  value       = azurerm_service_plan.function_plan.name
}

output "function_service_plan_id" {
  description = "The ID of the service plan for Function Apps"
  value       = azurerm_service_plan.function_plan.id
}

output "function_service_plan_sku" {
  description = "The SKU of the service plan for Function Apps"
  value       = azurerm_service_plan.function_plan.sku_name
}

# Azure Monitor Workbook Information
output "monitor_workbook_id" {
  description = "The ID of the Azure Monitor Workbook for distributed tracing"
  value       = azapi_resource.choreography_workbook.id
}

output "monitor_workbook_name" {
  description = "The name of the Azure Monitor Workbook"
  value       = "choreography-dashboard-${local.resource_suffix}"
}

# Portal URLs for easy access
output "azure_portal_urls" {
  description = "Direct links to Azure Portal for key resources"
  value = {
    resource_group = "https://portal.azure.com/#@/resource${azurerm_resource_group.main.id}/overview"
    service_bus    = "https://portal.azure.com/#@/resource${azurerm_servicebus_namespace.main.id}/overview"
    app_insights   = "https://portal.azure.com/#@/resource${azurerm_application_insights.main.id}/overview"
    log_analytics  = "https://portal.azure.com/#@/resource${azurerm_log_analytics_workspace.main.id}/overview"
    workbook      = "https://portal.azure.com/#@/resource${azapi_resource.choreography_workbook.id}/overview"
    order_service = "https://portal.azure.com/#@/resource${azurerm_container_app.order_service.id}/overview"
  }
}

# Deployment Summary
output "deployment_summary" {
  description = "Summary of the deployed choreography infrastructure"
  value = {
    environment               = var.environment
    location                 = var.location
    resource_group           = azurerm_resource_group.main.name
    service_bus_sku          = var.service_bus_sku
    service_bus_capacity     = var.service_bus_capacity
    container_apps_count     = 2
    function_apps_count      = 2
    topics_count            = length(var.service_bus_topics)
    subscriptions_count     = length(var.service_bus_subscriptions)
    monitoring_enabled      = var.enable_diagnostic_settings
    zone_redundancy_enabled = var.enable_zone_redundancy
  }
}

# Connection Information for Applications
output "application_configuration" {
  description = "Configuration values needed for application deployment"
  value = {
    service_bus_connection = "Use service_bus_connection_string output (sensitive)"
    app_insights_connection = "Use application_insights_connection_string output (sensitive)"
    log_analytics_workspace_id = azurerm_log_analytics_workspace.main.workspace_id
    container_environment_id = azurerm_container_app_environment.main.id
    available_topics = keys(var.service_bus_topics)
    available_subscriptions = keys(var.service_bus_subscriptions)
  }
}

# Health Check URLs
output "health_check_urls" {
  description = "URLs for health checking the deployed services"
  value = {
    order_service = "https://${azurerm_container_app.order_service.latest_revision_fqdn}/api/health"
    payment_function = "https://${azurerm_linux_function_app.payment_service.default_hostname}/api/health"
    shipping_function = "https://${azurerm_linux_function_app.shipping_service.default_hostname}/api/health"
  }
}

# Testing Information
output "testing_configuration" {
  description = "Information needed for testing the choreography workflow"
  value = {
    test_topic = "order-events"
    test_message = jsonencode({
      orderId    = "test-001"
      customerId = "customer-123"
      amount     = 99.99
      priority   = "High"
    })
    high_priority_subscription = "high-priority-orders"
    dead_letter_queue = azurerm_servicebus_queue.dead_letter_queue.name
  }
}