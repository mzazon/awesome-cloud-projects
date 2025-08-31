# ==============================================================================
# Output Values for Azure Service Bus Message Queue Infrastructure
# ==============================================================================
# This file defines all output values that are returned after successful
# deployment. These outputs provide essential information for application
# integration, monitoring, and infrastructure management.
# ==============================================================================

# ==============================================================================
# CONNECTION AND AUTHENTICATION OUTPUTS
# ==============================================================================

output "primary_connection_string" {
  description = "Primary connection string for Service Bus namespace (contains authentication credentials)"
  value       = azurerm_servicebus_namespace.main.default_primary_connection_string
  sensitive   = true
}

output "secondary_connection_string" {
  description = "Secondary connection string for Service Bus namespace (backup authentication)"
  value       = azurerm_servicebus_namespace.main.default_secondary_connection_string
  sensitive   = true
}

output "primary_key" {
  description = "Primary access key for the RootManageSharedAccessKey authorization rule"
  value       = azurerm_servicebus_namespace.main.default_primary_key
  sensitive   = true
}

output "secondary_key" {
  description = "Secondary access key for the RootManageSharedAccessKey authorization rule"
  value       = azurerm_servicebus_namespace.main.default_secondary_key
  sensitive   = true
}

# ==============================================================================
# SERVICE ENDPOINT AND CONFIGURATION OUTPUTS
# ==============================================================================

output "service_bus_endpoint" {
  description = "Service Bus namespace endpoint URL for direct API access"
  value       = azurerm_servicebus_namespace.main.endpoint
}

output "service_bus_fqdn" {
  description = "Fully Qualified Domain Name (FQDN) of the Service Bus namespace"
  value       = "${azurerm_servicebus_namespace.main.name}.servicebus.windows.net"
}

output "queue_name" {
  description = "Name of the Service Bus queue for message processing"
  value       = azurerm_servicebus_queue.main.name
}

output "queue_url" {
  description = "Complete URL for accessing the Service Bus queue"
  value       = "${azurerm_servicebus_namespace.main.endpoint}${azurerm_servicebus_queue.main.name}"
}

# ==============================================================================
# RESOURCE IDENTIFICATION OUTPUTS
# ==============================================================================

output "resource_group_name" {
  description = "Name of the resource group containing Service Bus resources"
  value       = azurerm_resource_group.servicebus_rg.name
}

output "resource_group_id" {
  description = "Azure resource ID of the resource group"
  value       = azurerm_resource_group.servicebus_rg.id
}

output "servicebus_namespace_name" {
  description = "Name of the Service Bus namespace"
  value       = azurerm_servicebus_namespace.main.name
}

output "servicebus_namespace_id" {
  description = "Azure resource ID of the Service Bus namespace"
  value       = azurerm_servicebus_namespace.main.id
}

output "servicebus_queue_id" {
  description = "Azure resource ID of the Service Bus queue"
  value       = azurerm_servicebus_queue.main.id
}

# ==============================================================================
# CONFIGURATION AND METADATA OUTPUTS  
# ==============================================================================

output "location" {
  description = "Azure region where resources are deployed"
  value       = azurerm_resource_group.servicebus_rg.location
}

output "servicebus_sku" {
  description = "Service Bus namespace pricing tier (Basic, Standard, or Premium)"
  value       = azurerm_servicebus_namespace.main.sku
}

output "queue_max_size_mb" {
  description = "Maximum queue size in megabytes"
  value       = azurerm_servicebus_queue.main.max_size_in_megabytes
}

output "queue_message_ttl" {
  description = "Default message time-to-live in ISO 8601 duration format"
  value       = azurerm_servicebus_queue.main.default_message_ttl
}

output "dead_letter_enabled" {
  description = "Whether dead letter queue is enabled for expired messages"
  value       = azurerm_servicebus_queue.main.dead_lettering_on_message_expiration
}

output "max_delivery_count" {
  description = "Maximum delivery attempts before message is dead lettered"
  value       = azurerm_servicebus_queue.main.max_delivery_count
}

# ==============================================================================
# INTEGRATION AND MONITORING OUTPUTS
# ==============================================================================

output "tags" {
  description = "Tags applied to Service Bus resources for management and cost allocation"
  value       = azurerm_servicebus_namespace.main.tags
}

output "namespace_status" {
  description = "Current status of the Service Bus namespace"
  value       = "Active" # Namespaces are active when successfully created
}

output "public_network_access_enabled" {
  description = "Whether public network access is enabled for the Service Bus namespace"
  value       = azurerm_servicebus_namespace.main.public_network_access_enabled
}

output "minimum_tls_version" {
  description = "Minimum TLS version required for connections"
  value       = azurerm_servicebus_namespace.main.minimum_tls_version
}

# ==============================================================================
# APPLICATION INTEGRATION HELPER OUTPUTS
# ==============================================================================

output "connection_info" {
  description = "Complete connection information for application configuration"
  value = {
    namespace_name     = azurerm_servicebus_namespace.main.name
    queue_name        = azurerm_servicebus_queue.main.name
    endpoint          = azurerm_servicebus_namespace.main.endpoint
    sku              = azurerm_servicebus_namespace.main.sku
    location         = azurerm_resource_group.servicebus_rg.location
    resource_group   = azurerm_resource_group.servicebus_rg.name
  }
}

output "queue_configuration" {
  description = "Service Bus queue configuration summary"
  value = {
    name                    = azurerm_servicebus_queue.main.name
    max_size_mb            = azurerm_servicebus_queue.main.max_size_in_megabytes
    default_message_ttl    = azurerm_servicebus_queue.main.default_message_ttl
    max_delivery_count     = azurerm_servicebus_queue.main.max_delivery_count
    dead_lettering_enabled = azurerm_servicebus_queue.main.dead_lettering_on_message_expiration
    lock_duration         = azurerm_servicebus_queue.main.lock_duration
    partitioning_enabled  = azurerm_servicebus_queue.main.partitioning_enabled
    sessions_enabled      = azurerm_servicebus_queue.main.requires_session
    duplicate_detection   = azurerm_servicebus_queue.main.requires_duplicate_detection
  }
}

# ==============================================================================
# DEPLOYMENT SUMMARY OUTPUT
# ==============================================================================

output "deployment_summary" {
  description = "Summary of deployed Service Bus infrastructure"
  value = {
    resource_group_name    = azurerm_resource_group.servicebus_rg.name
    location              = azurerm_resource_group.servicebus_rg.location
    namespace_name        = azurerm_servicebus_namespace.main.name
    namespace_sku         = azurerm_servicebus_namespace.main.sku
    namespace_endpoint    = azurerm_servicebus_namespace.main.endpoint
    queue_name           = azurerm_servicebus_queue.main.name
    queue_max_size_mb    = azurerm_servicebus_queue.main.max_size_in_megabytes
    public_access_enabled = azurerm_servicebus_namespace.main.public_network_access_enabled
    tls_version          = azurerm_servicebus_namespace.main.minimum_tls_version
    deployment_date      = timestamp()
  }
}