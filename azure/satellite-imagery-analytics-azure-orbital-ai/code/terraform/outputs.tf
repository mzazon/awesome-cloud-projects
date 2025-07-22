# Output values for Azure Orbital and AI Services infrastructure
# These outputs provide essential connection information and resource identifiers
# needed for satellite data analytics operations and integrations

# Resource Group Information
output "resource_group_name" {
  description = "Name of the resource group containing all orbital analytics resources"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Azure region where resources are deployed"
  value       = azurerm_resource_group.main.location
}

# Storage Account and Data Lake Outputs
output "storage_account_name" {
  description = "Name of the Data Lake Storage Gen2 account for satellite data"
  value       = azurerm_storage_account.datalake.name
}

output "storage_account_primary_endpoint" {
  description = "Primary endpoint URL for the Data Lake Storage account"
  value       = azurerm_storage_account.datalake.primary_dfs_endpoint
}

output "storage_account_id" {
  description = "Resource ID of the Data Lake Storage account"
  value       = azurerm_storage_account.datalake.id
}

output "storage_containers" {
  description = "List of storage containers for different data stages"
  value = {
    raw_satellite_data    = azurerm_storage_container.raw_satellite_data.name
    processed_imagery     = azurerm_storage_container.processed_imagery.name
    ai_analysis_results   = azurerm_storage_container.ai_analysis_results.name
  }
}

# Synapse Analytics Workspace Outputs
output "synapse_workspace_name" {
  description = "Name of the Synapse Analytics workspace"
  value       = azurerm_synapse_workspace.main.name
}

output "synapse_workspace_web_url" {
  description = "Web URL for accessing Synapse Studio"
  value       = "https://${azurerm_synapse_workspace.main.name}.dev.azuresynapse.net"
}

output "synapse_sql_endpoint" {
  description = "SQL endpoint for Synapse dedicated SQL pool connections"
  value       = "${azurerm_synapse_workspace.main.name}-ondemand.sql.azuresynapse.net"
}

output "synapse_spark_pool_name" {
  description = "Name of the Synapse Spark pool for image processing"
  value       = azurerm_synapse_spark_pool.main.name
}

output "synapse_sql_pool_name" {
  description = "Name of the Synapse SQL pool for structured analytics"
  value       = azurerm_synapse_sql_pool.main.name
}

output "synapse_managed_identity_id" {
  description = "Managed identity ID of the Synapse workspace for role assignments"
  value       = azurerm_synapse_workspace.main.identity[0].principal_id
}

# Event Hubs Namespace and Hubs Outputs
output "eventhub_namespace_name" {
  description = "Name of the Event Hubs namespace for data streaming"
  value       = azurerm_eventhub_namespace.main.name
}

output "eventhub_namespace_fqdn" {
  description = "Fully qualified domain name of the Event Hubs namespace"
  value       = "${azurerm_eventhub_namespace.main.name}.servicebus.windows.net"
}

output "satellite_imagery_eventhub_name" {
  description = "Name of the Event Hub for satellite imagery streams"
  value       = azurerm_eventhub.satellite_imagery.name
}

output "satellite_telemetry_eventhub_name" {
  description = "Name of the Event Hub for satellite telemetry streams"
  value       = azurerm_eventhub.satellite_telemetry.name
}

# Azure AI Services Outputs
output "ai_services_name" {
  description = "Name of the Azure AI Services cognitive account"
  value       = azurerm_cognitive_account.main.name
}

output "ai_services_endpoint" {
  description = "Endpoint URL for Azure AI Services API calls"
  value       = azurerm_cognitive_account.main.endpoint
}

output "custom_vision_training_name" {
  description = "Name of the Custom Vision training resource for satellite object detection"
  value       = azurerm_cognitive_account.custom_vision_training.name
}

output "custom_vision_training_endpoint" {
  description = "Endpoint URL for Custom Vision training API"
  value       = azurerm_cognitive_account.custom_vision_training.endpoint
}

# Azure Maps Outputs
output "maps_account_name" {
  description = "Name of the Azure Maps account for geospatial visualization"
  value       = azurerm_maps_account.main.name
}

output "maps_account_id" {
  description = "Resource ID of the Azure Maps account"
  value       = azurerm_maps_account.main.id
}

# Cosmos DB Outputs
output "cosmos_account_name" {
  description = "Name of the Cosmos DB account for metadata and results storage"
  value       = azurerm_cosmosdb_account.main.name
}

output "cosmos_account_endpoint" {
  description = "Endpoint URL for Cosmos DB API connections"
  value       = azurerm_cosmosdb_account.main.endpoint
}

output "cosmos_database_name" {
  description = "Name of the Cosmos DB database for satellite analytics"
  value       = azurerm_cosmosdb_sql_database.satellite_analytics.name
}

output "cosmos_containers" {
  description = "Names of Cosmos DB containers for different data types"
  value = {
    imagery_metadata    = azurerm_cosmosdb_sql_container.imagery_metadata.name
    ai_analysis_results = azurerm_cosmosdb_sql_container.ai_analysis_results.name
    geospatial_index   = azurerm_cosmosdb_sql_container.geospatial_index.name
  }
}

# Key Vault Outputs
output "key_vault_name" {
  description = "Name of the Key Vault for secure credential storage"
  value       = azurerm_key_vault.main.name
}

output "key_vault_uri" {
  description = "URI of the Key Vault for accessing stored secrets"
  value       = azurerm_key_vault.main.vault_uri
}

# Security and Access Outputs
output "key_vault_secret_names" {
  description = "Names of secrets stored in Key Vault for application configuration"
  value = {
    eventhub_connection    = azurerm_key_vault_secret.eventhub_connection.name
    ai_services_endpoint   = azurerm_key_vault_secret.ai_services_endpoint.name
    ai_services_key       = azurerm_key_vault_secret.ai_services_key.name
    maps_subscription_key = azurerm_key_vault_secret.maps_subscription_key.name
    cosmos_endpoint       = azurerm_key_vault_secret.cosmos_endpoint.name
    cosmos_key           = azurerm_key_vault_secret.cosmos_key.name
  }
}

# Monitoring and Diagnostics Outputs
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace for monitoring (if enabled)"
  value       = var.enable_diagnostic_logs ? azurerm_log_analytics_workspace.main[0].name : null
}

output "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics workspace (if enabled)"
  value       = var.enable_diagnostic_logs ? azurerm_log_analytics_workspace.main[0].id : null
}

# Configuration Information for Applications
output "satellite_data_pipeline_config" {
  description = "Configuration object for satellite data processing applications"
  value = {
    # Data ingestion endpoints
    imagery_eventhub_name    = azurerm_eventhub.satellite_imagery.name
    telemetry_eventhub_name  = azurerm_eventhub.satellite_telemetry.name
    eventhub_namespace_fqdn  = "${azurerm_eventhub_namespace.main.name}.servicebus.windows.net"
    
    # Storage configuration
    storage_account_name     = azurerm_storage_account.datalake.name
    storage_endpoint        = azurerm_storage_account.datalake.primary_dfs_endpoint
    raw_data_container      = azurerm_storage_container.raw_satellite_data.name
    processed_data_container = azurerm_storage_container.processed_imagery.name
    results_container       = azurerm_storage_container.ai_analysis_results.name
    
    # Processing configuration
    synapse_workspace_name  = azurerm_synapse_workspace.main.name
    spark_pool_name        = azurerm_synapse_spark_pool.main.name
    sql_pool_name          = azurerm_synapse_sql_pool.main.name
    
    # AI Services configuration
    ai_services_endpoint   = azurerm_cognitive_account.main.endpoint
    custom_vision_endpoint = azurerm_cognitive_account.custom_vision_training.endpoint
    
    # Database configuration
    cosmos_endpoint        = azurerm_cosmosdb_account.main.endpoint
    cosmos_database_name   = azurerm_cosmosdb_sql_database.satellite_analytics.name
    
    # Visualization configuration
    maps_account_name      = azurerm_maps_account.main.name
    
    # Security configuration
    key_vault_uri          = azurerm_key_vault.main.vault_uri
  }
}

# Azure Orbital Integration Information
output "orbital_integration_config" {
  description = "Configuration details for Azure Orbital ground station integration"
  value = {
    # Event Hub targets for satellite data streams
    imagery_stream_target = {
      namespace_name = azurerm_eventhub_namespace.main.name
      eventhub_name  = azurerm_eventhub.satellite_imagery.name
      endpoint       = "${azurerm_eventhub_namespace.main.name}.servicebus.windows.net"
    }
    
    telemetry_stream_target = {
      namespace_name = azurerm_eventhub_namespace.main.name
      eventhub_name  = azurerm_eventhub.satellite_telemetry.name
      endpoint       = "${azurerm_eventhub_namespace.main.name}.servicebus.windows.net"
    }
    
    # Storage targets for data archival
    storage_targets = {
      account_name     = azurerm_storage_account.datalake.name
      container_name   = azurerm_storage_container.raw_satellite_data.name
      endpoint         = azurerm_storage_account.datalake.primary_dfs_endpoint
    }
    
    # Network configuration
    resource_group_name = azurerm_resource_group.main.name
    location           = azurerm_resource_group.main.location
  }
}

# Cost Optimization Information
output "cost_optimization_info" {
  description = "Information about cost optimization features enabled"
  value = {
    spark_auto_pause_enabled = var.enable_auto_pause
    auto_pause_delay_minutes = var.auto_pause_delay_minutes
    storage_tier            = var.storage_account_tier
    cosmos_throughput       = var.cosmos_throughput
    sql_pool_sku           = var.sql_pool_sku
    diagnostic_logs_enabled = var.enable_diagnostic_logs
  }
}

# Deployment Information
output "deployment_info" {
  description = "Information about the deployment configuration"
  value = {
    terraform_version = "~> 1.0"
    azurerm_provider_version = "~> 3.0"
    deployment_timestamp = timestamp()
    environment = var.environment
    project_name = var.project_name
    resource_suffix = local.resource_suffix
  }
}