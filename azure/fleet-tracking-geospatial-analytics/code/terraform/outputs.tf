# Output values for Azure Geospatial Analytics Infrastructure
# This file defines all output values that can be used by other
# Terraform configurations or for verification purposes

# Resource Group Information
output "resource_group_name" {
  description = "Name of the resource group containing all resources"
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

# Storage Account Information
output "storage_account_name" {
  description = "Name of the storage account"
  value       = azurerm_storage_account.main.name
}

output "storage_account_id" {
  description = "ID of the storage account"
  value       = azurerm_storage_account.main.id
}

output "storage_account_primary_endpoint" {
  description = "Primary endpoint of the storage account"
  value       = azurerm_storage_account.main.primary_blob_endpoint
}

output "storage_account_primary_access_key" {
  description = "Primary access key for the storage account"
  value       = azurerm_storage_account.main.primary_access_key
  sensitive   = true
}

output "storage_containers" {
  description = "List of storage containers created"
  value = {
    telemetry_archive = azurerm_storage_container.telemetry_archive.name
    geofences        = azurerm_storage_container.geofences.name
  }
}

# Event Hub Information
output "eventhub_namespace_name" {
  description = "Name of the Event Hub namespace"
  value       = azurerm_eventhub_namespace.main.name
}

output "eventhub_namespace_id" {
  description = "ID of the Event Hub namespace"
  value       = azurerm_eventhub_namespace.main.id
}

output "eventhub_name" {
  description = "Name of the Event Hub for vehicle locations"
  value       = azurerm_eventhub.vehicle_locations.name
}

output "eventhub_connection_string" {
  description = "Connection string for the Event Hub"
  value       = azurerm_eventhub_namespace.main.default_primary_connection_string
  sensitive   = true
}

output "eventhub_primary_key" {
  description = "Primary key for Event Hub access"
  value       = azurerm_eventhub_namespace.main.default_primary_key
  sensitive   = true
}

output "eventhub_consumer_group" {
  description = "Consumer group for Stream Analytics"
  value       = azurerm_eventhub_consumer_group.stream_analytics.name
}

# Stream Analytics Information
output "stream_analytics_job_name" {
  description = "Name of the Stream Analytics job"
  value       = azurerm_stream_analytics_job.main.name
}

output "stream_analytics_job_id" {
  description = "ID of the Stream Analytics job"
  value       = azurerm_stream_analytics_job.main.id
}

output "stream_analytics_job_state" {
  description = "Current state of the Stream Analytics job"
  value       = azurerm_stream_analytics_job.main.job_state
}

output "stream_analytics_streaming_units" {
  description = "Number of streaming units configured"
  value       = azurerm_stream_analytics_job.main.streaming_units
}

output "stream_analytics_query" {
  description = "The Stream Analytics query for geospatial processing"
  value       = local.stream_analytics_query
}

# Cosmos DB Information
output "cosmosdb_account_name" {
  description = "Name of the Cosmos DB account"
  value       = azurerm_cosmosdb_account.main.name
}

output "cosmosdb_account_id" {
  description = "ID of the Cosmos DB account"
  value       = azurerm_cosmosdb_account.main.id
}

output "cosmosdb_endpoint" {
  description = "Endpoint URL of the Cosmos DB account"
  value       = azurerm_cosmosdb_account.main.endpoint
}

output "cosmosdb_primary_key" {
  description = "Primary key for Cosmos DB access"
  value       = azurerm_cosmosdb_account.main.primary_key
  sensitive   = true
}

output "cosmosdb_connection_strings" {
  description = "Connection strings for Cosmos DB"
  value       = azurerm_cosmosdb_account.main.connection_strings
  sensitive   = true
}

output "cosmosdb_database_name" {
  description = "Name of the Cosmos DB database"
  value       = azurerm_cosmosdb_sql_database.fleet_analytics.name
}

output "cosmosdb_container_name" {
  description = "Name of the Cosmos DB container for location events"
  value       = azurerm_cosmosdb_sql_container.location_events.name
}

# Azure Maps Information
output "azure_maps_account_name" {
  description = "Name of the Azure Maps account"
  value       = azurerm_maps_account.main.name
}

output "azure_maps_account_id" {
  description = "ID of the Azure Maps account"
  value       = azurerm_maps_account.main.id
}

output "azure_maps_primary_key" {
  description = "Primary key for Azure Maps access"
  value       = azurerm_maps_account.main.primary_access_key
  sensitive   = true
}

output "azure_maps_secondary_key" {
  description = "Secondary key for Azure Maps access"
  value       = azurerm_maps_account.main.secondary_access_key
  sensitive   = true
}

# Monitoring Information
output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace"
  value       = var.enable_monitoring ? azurerm_log_analytics_workspace.main[0].id : null
}

output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = var.enable_monitoring ? azurerm_log_analytics_workspace.main[0].name : null
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

output "action_group_id" {
  description = "ID of the action group for alerts"
  value       = var.enable_monitoring ? azurerm_monitor_action_group.fleet_alerts[0].id : null
}

# Configuration Information
output "geofence_configuration" {
  description = "Geofence configuration used in the deployment"
  value = {
    coordinates      = var.default_geofence_coordinates
    depot_location   = var.depot_location
    speed_threshold  = var.speed_limit_threshold
  }
}

output "deployment_configuration" {
  description = "Key configuration parameters used in the deployment"
  value = {
    project_name                = var.project_name
    environment                = var.environment
    location                   = var.location
    resource_suffix            = local.resource_suffix
    eventhub_partition_count   = var.eventhub_partition_count
    stream_analytics_units     = var.stream_analytics_streaming_units
    cosmosdb_throughput       = var.cosmos_db_throughput
    monitoring_enabled        = var.enable_monitoring
    backup_retention_days     = var.backup_retention_days
  }
}

# API Endpoints and URLs
output "api_endpoints" {
  description = "API endpoints for various services"
  value = {
    cosmosdb_endpoint    = azurerm_cosmosdb_account.main.endpoint
    storage_blob_endpoint = azurerm_storage_account.main.primary_blob_endpoint
    eventhub_endpoint    = "https://${azurerm_eventhub_namespace.main.name}.servicebus.windows.net/"
    azure_maps_endpoint  = "https://atlas.microsoft.com/"
  }
}

# Connection Information for Applications
output "connection_information" {
  description = "Connection information for client applications"
  value = {
    eventhub_namespace    = azurerm_eventhub_namespace.main.name
    eventhub_name        = azurerm_eventhub.vehicle_locations.name
    cosmosdb_account     = azurerm_cosmosdb_account.main.name
    cosmosdb_database    = azurerm_cosmosdb_sql_database.fleet_analytics.name
    cosmosdb_container   = azurerm_cosmosdb_sql_container.location_events.name
    storage_account      = azurerm_storage_account.main.name
    maps_account         = azurerm_maps_account.main.name
  }
  sensitive = false
}

# Security Information
output "security_configuration" {
  description = "Security configuration applied to resources"
  value = {
    https_only_storage     = azurerm_storage_account.main.enable_https_traffic_only
    min_tls_version       = azurerm_storage_account.main.min_tls_version
    private_endpoints     = var.enable_private_endpoints
    public_network_access = !var.enable_private_endpoints
  }
}

# Backup and Disaster Recovery Information
output "backup_configuration" {
  description = "Backup and disaster recovery configuration"
  value = {
    backup_enabled           = var.enable_backup
    backup_retention_days   = var.backup_retention_days
    cosmos_backup_type      = azurerm_cosmosdb_account.main.backup[0].type
    cosmos_backup_interval  = azurerm_cosmosdb_account.main.backup[0].interval_in_minutes
    cosmos_backup_retention = azurerm_cosmosdb_account.main.backup[0].retention_in_hours
    eventhub_capture_enabled = azurerm_eventhub.vehicle_locations.capture_description[0].enabled
  }
}

# Cost Optimization Information
output "cost_optimization_info" {
  description = "Information to help with cost optimization"
  value = {
    eventhub_sku           = azurerm_eventhub_namespace.main.sku
    eventhub_capacity      = azurerm_eventhub_namespace.main.capacity
    storage_tier           = azurerm_storage_account.main.account_tier
    storage_replication    = azurerm_storage_account.main.account_replication_type
    cosmosdb_consistency   = azurerm_cosmosdb_account.main.consistency_policy[0].consistency_level
    cosmosdb_throughput    = azurerm_cosmosdb_sql_database.fleet_analytics.throughput
    azure_maps_sku         = azurerm_maps_account.main.sku_name
    stream_analytics_units = azurerm_stream_analytics_job.main.streaming_units
  }
}

# Validation URLs and Test Endpoints
output "validation_endpoints" {
  description = "Endpoints for validating the deployment"
  value = {
    azure_maps_search_api = "https://atlas.microsoft.com/search/address/json?api-version=1.0&subscription-key=${azurerm_maps_account.main.primary_access_key}&query=Seattle"
    cosmosdb_portal_url   = "https://cosmos.azure.com/accountdashboard/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${azurerm_resource_group.main.name}/accounts/${azurerm_cosmosdb_account.main.name}/overview"
    eventhub_portal_url   = "https://portal.azure.com/#resource/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${azurerm_resource_group.main.name}/providers/Microsoft.EventHub/namespaces/${azurerm_eventhub_namespace.main.name}/overview"
    stream_analytics_portal_url = "https://portal.azure.com/#resource/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${azurerm_resource_group.main.name}/providers/Microsoft.StreamAnalytics/streamingjobs/${azurerm_stream_analytics_job.main.name}/overview"
  }
  sensitive = true
}

# Sample Event Structure
output "sample_event_structure" {
  description = "Sample event structure for testing"
  value = {
    vehicleId = "VEHICLE-001"
    location = {
      latitude  = 47.645
      longitude = -122.120
    }
    speed     = 65
    timestamp = "2025-01-01T12:00:00Z"
  }
}

# Terraform State Information
output "terraform_state_info" {
  description = "Information about the Terraform deployment"
  value = {
    resource_count    = length(data.azurerm_client_config.current.*.id)
    deployment_time   = timestamp()
    random_suffix     = local.resource_suffix
    tags_applied      = local.common_tags
  }
}