# ==============================================================================
# Azure Service Bus Message Queue Infrastructure
# ==============================================================================
# This Terraform configuration creates an Azure Service Bus namespace and queue
# for reliable, asynchronous communication between applications following the
# recipe "Simple Message Queue with Service Bus"
# ==============================================================================

# Configure the Azure Provider
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

# Configure the Microsoft Azure Provider features
provider "azurerm" {
  features {}
}

# Data source to get current Azure client configuration
data "azurerm_client_config" "current" {}

# ==============================================================================
# RESOURCE GROUP
# ==============================================================================

# Create a Resource Group to contain all Service Bus resources
# Resource groups provide logical grouping and management boundaries for resources
resource "azurerm_resource_group" "servicebus_rg" {
  name     = var.resource_group_name
  location = var.location

  tags = merge(var.common_tags, {
    component = "infrastructure"
    purpose   = "messaging"
  })
}

# ==============================================================================
# SERVICE BUS NAMESPACE
# ==============================================================================

# Create a Service Bus Namespace
# The namespace provides a scoping container for messaging entities like queues and topics
# and serves as the unique DNS name for messaging resources
resource "azurerm_servicebus_namespace" "main" {
  name                = var.servicebus_namespace_name
  location            = azurerm_resource_group.servicebus_rg.location
  resource_group_name = azurerm_resource_group.servicebus_rg.name
  
  # Use Standard tier for full messaging capabilities including message sessions,
  # dead-letter queues, and duplicate detection
  sku = var.servicebus_sku
  
  # Security configuration
  local_auth_enabled            = var.local_auth_enabled
  public_network_access_enabled = var.public_network_access_enabled
  minimum_tls_version          = var.minimum_tls_version

  tags = merge(var.common_tags, {
    component = "messaging"
    tier      = var.servicebus_sku
  })
}

# ==============================================================================
# SERVICE BUS QUEUE
# ==============================================================================

# Create a Service Bus Queue for reliable message delivery
# Queues implement First-In-First-Out (FIFO) delivery semantics and support
# competing consumer patterns for load distribution
resource "azurerm_servicebus_queue" "main" {
  name         = var.queue_name
  namespace_id = azurerm_servicebus_namespace.main.id

  # Message time-to-live: 14 days (P14D in ISO 8601 duration format)
  # After this period, messages will expire and can be moved to dead letter queue
  default_message_ttl = var.default_message_ttl

  # Enable dead letter queue for expired messages
  # This provides essential error handling and message recovery capabilities
  dead_lettering_on_message_expiration = var.dead_lettering_on_message_expiration

  # Maximum queue size in megabytes
  # Controls memory allocation for the queue (1024 MB = 1 GB)
  max_size_in_megabytes = var.max_size_in_megabytes

  # Message delivery attempt limit before dead lettering
  # After 10 failed delivery attempts, messages are moved to dead letter queue
  max_delivery_count = var.max_delivery_count

  # Lock duration for message processing
  # Amount of time a message is locked for other receivers during processing
  lock_duration = var.lock_duration

  # Enable server-side batched operations for improved throughput
  batched_operations_enabled = var.batched_operations_enabled

  # Duplicate detection settings
  requires_duplicate_detection           = var.requires_duplicate_detection
  duplicate_detection_history_time_window = var.duplicate_detection_history_time_window

  # Session support for ordered message processing
  # When enabled, provides guaranteed FIFO delivery within message sessions
  requires_session = var.requires_session

  # Partitioning support for increased throughput (Standard/Premium tiers)
  partitioning_enabled = var.partitioning_enabled

  # Express entities hold messages in memory before persistent storage
  # Not supported in Premium tier
  express_enabled = var.servicebus_sku == "Premium" ? false : var.express_enabled

  # Queue status - Active by default
  status = "Active"

  depends_on = [azurerm_servicebus_namespace.main]
}

# ==============================================================================
# OUTPUTS FOR APPLICATION INTEGRATION
# ==============================================================================

# Output the Service Bus connection string for application configuration
# Applications will use this connection string to authenticate and connect
output "primary_connection_string" {
  description = "Primary connection string for Service Bus namespace"
  value       = azurerm_servicebus_namespace.main.default_primary_connection_string
  sensitive   = true
}

# Output the Service Bus namespace endpoint
output "service_bus_endpoint" {
  description = "Service Bus namespace endpoint URL"
  value       = azurerm_servicebus_namespace.main.endpoint
}

# Output the queue name for application configuration
output "queue_name" {
  description = "Name of the Service Bus queue"
  value       = azurerm_servicebus_queue.main.name
}

# Output resource identifiers for integration with other resources
output "servicebus_namespace_id" {
  description = "ID of the Service Bus namespace"
  value       = azurerm_servicebus_namespace.main.id
}

output "servicebus_queue_id" {
  description = "ID of the Service Bus queue"  
  value       = azurerm_servicebus_queue.main.id
}

output "resource_group_name" {
  description = "Name of the resource group"
  value       = azurerm_resource_group.servicebus_rg.name
}