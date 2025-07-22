# Outputs for Azure Serverless Data Pipeline Infrastructure

# Resource Group Information
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Location of the resource group"
  value       = azurerm_resource_group.main.location
}

# Storage Account Information
output "storage_account_name" {
  description = "Name of the Data Lake Storage account"
  value       = azurerm_storage_account.data_lake.name
}

output "storage_account_id" {
  description = "ID of the Data Lake Storage account"
  value       = azurerm_storage_account.data_lake.id
}

output "storage_account_primary_dfs_endpoint" {
  description = "Primary DFS endpoint of the Data Lake Storage account"
  value       = azurerm_storage_account.data_lake.primary_dfs_endpoint
}

output "storage_account_primary_web_endpoint" {
  description = "Primary web endpoint of the Data Lake Storage account"
  value       = azurerm_storage_account.data_lake.primary_web_endpoint
}

output "data_lake_containers" {
  description = "List of created data lake containers"
  value       = [for container in azurerm_storage_data_lake_gen2_filesystem.containers : container.name]
}

# Azure Key Vault Information
output "key_vault_name" {
  description = "Name of the Azure Key Vault"
  value       = azurerm_key_vault.main.name
}

output "key_vault_id" {
  description = "ID of the Azure Key Vault"
  value       = azurerm_key_vault.main.id
}

output "key_vault_uri" {
  description = "URI of the Azure Key Vault"
  value       = azurerm_key_vault.main.vault_uri
}

# Azure Synapse Analytics Information
output "synapse_workspace_name" {
  description = "Name of the Synapse Analytics workspace"
  value       = azurerm_synapse_workspace.main.name
}

output "synapse_workspace_id" {
  description = "ID of the Synapse Analytics workspace"
  value       = azurerm_synapse_workspace.main.id
}

output "synapse_workspace_web_url" {
  description = "Web URL of the Synapse Analytics workspace"
  value       = "https://${azurerm_synapse_workspace.main.name}.dev.azuresynapse.net"
}

output "synapse_sql_endpoint" {
  description = "SQL endpoint of the Synapse Analytics workspace"
  value       = "${azurerm_synapse_workspace.main.name}.sql.azuresynapse.net"
}

output "synapse_sql_admin_login" {
  description = "SQL administrator login for Synapse workspace"
  value       = var.synapse_sql_admin_login
}

output "synapse_managed_identity_principal_id" {
  description = "Principal ID of the Synapse workspace managed identity"
  value       = azurerm_synapse_workspace.main.identity[0].principal_id
}

# Azure Data Factory Information
output "data_factory_name" {
  description = "Name of the Azure Data Factory"
  value       = azurerm_data_factory.main.name
}

output "data_factory_id" {
  description = "ID of the Azure Data Factory"
  value       = azurerm_data_factory.main.id
}

output "data_factory_managed_identity_principal_id" {
  description = "Principal ID of the Data Factory managed identity"
  value       = azurerm_data_factory.main.identity[0].principal_id
}

# Linked Services Information
output "data_factory_key_vault_linked_service_name" {
  description = "Name of the Key Vault linked service in Data Factory"
  value       = azurerm_data_factory_linked_service_key_vault.key_vault.name
}

output "data_factory_storage_linked_service_name" {
  description = "Name of the storage linked service in Data Factory"
  value       = azurerm_data_factory_linked_service_data_lake_storage_gen2.storage.name
}

# Dataset Information
output "data_factory_source_dataset_name" {
  description = "Name of the source dataset in Data Factory"
  value       = azurerm_data_factory_dataset_json.streaming_source.name
}

output "data_factory_sink_dataset_name" {
  description = "Name of the sink dataset in Data Factory"
  value       = azurerm_data_factory_dataset_parquet.curated_sink.name
}

# Monitoring Information (conditional outputs)
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace (if monitoring enabled)"
  value       = var.enable_monitoring ? azurerm_log_analytics_workspace.main[0].name : null
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace (if monitoring enabled)"
  value       = var.enable_monitoring ? azurerm_log_analytics_workspace.main[0].id : null
}

output "action_group_name" {
  description = "Name of the action group for alerts (if monitoring enabled)"
  value       = var.enable_monitoring ? azurerm_monitor_action_group.pipeline_alerts[0].name : null
}

# Connection Information for External Access
output "connection_instructions" {
  description = "Instructions for connecting to the deployed resources"
  value = {
    synapse_studio_url = "https://${azurerm_synapse_workspace.main.name}.dev.azuresynapse.net"
    data_factory_url   = "https://adf.azure.com/home?factory=%2Fsubscriptions%2F${data.azurerm_client_config.current.subscription_id}%2FresourceGroups%2F${azurerm_resource_group.main.name}%2Fproviders%2FMicrosoft.DataFactory%2Ffactories%2F${azurerm_data_factory.main.name}"
    storage_explorer_url = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_storage_account.data_lake.id}/storageexplorer"
  }
}

# Security Information
output "firewall_rules" {
  description = "List of configured firewall rules for Synapse workspace"
  value = var.enable_firewall_rules ? [
    for rule in azurerm_synapse_firewall_rule.firewall_rules : {
      name     = rule.name
      start_ip = rule.start_ip_address
      end_ip   = rule.end_ip_address
    }
  ] : []
}

# Cost Management Information
output "cost_management_tips" {
  description = "Tips for managing costs of the deployed resources"
  value = {
    synapse_serverless = "Synapse serverless SQL pools charge per TB of data processed. Monitor query costs through Azure Cost Management."
    data_factory      = "Data Factory charges based on pipeline activities and data movement. Use scheduling and triggers efficiently."
    storage           = "Data Lake Storage charges based on data stored and transactions. Use lifecycle management policies for cost optimization."
    monitoring        = "Log Analytics workspace charges based on data ingested. Configure retention policies appropriately."
  }
}

# Next Steps Information
output "next_steps" {
  description = "Next steps after deployment"
  value = {
    synapse_setup = [
      "Access Synapse Studio at https://${azurerm_synapse_workspace.main.name}.dev.azuresynapse.net",
      "Create external tables in serverless SQL pool for data lake access",
      "Configure data sources and external file formats",
      "Test connectivity to Data Lake Storage containers"
    ]
    data_factory_setup = [
      "Access Data Factory at the provided URL",
      "Create mapping data flows for data transformation",
      "Configure triggers for pipeline scheduling",
      "Test data movement between source and sink datasets"
    ]
    security_setup = [
      "Review and customize firewall rules as needed",
      "Configure additional access policies in Key Vault",
      "Set up Azure Active Directory integration",
      "Enable private endpoints for enhanced security"
    ]
  }
}