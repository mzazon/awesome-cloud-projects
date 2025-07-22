# Output Values for Azure Data Governance Solution
# This file defines all outputs that will be displayed after successful deployment

# Resource Group Information
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.governance.name
}

output "resource_group_id" {
  description = "Resource ID of the created resource group"
  value       = azurerm_resource_group.governance.id
}

output "location" {
  description = "Azure region where resources were deployed"
  value       = azurerm_resource_group.governance.location
}

# Azure Purview Outputs
output "purview_account_name" {
  description = "Name of the Azure Purview account"
  value       = azurerm_purview_account.governance.name
}

output "purview_account_id" {
  description = "Resource ID of the Azure Purview account"
  value       = azurerm_purview_account.governance.id
}

output "purview_atlas_endpoint" {
  description = "Atlas endpoint URL for Purview account"
  value       = azurerm_purview_account.governance.atlas_kafka_endpoint_primary_connection_string
  sensitive   = true
}

output "purview_catalog_endpoint" {
  description = "Catalog endpoint URL for Purview account"
  value       = azurerm_purview_account.governance.catalog_endpoint
}

output "purview_guardian_endpoint" {
  description = "Guardian endpoint URL for Purview account"
  value       = azurerm_purview_account.governance.guardian_endpoint
}

output "purview_scan_endpoint" {
  description = "Scan endpoint URL for Purview account"
  value       = azurerm_purview_account.governance.scan_endpoint
}

output "purview_managed_resource_group_name" {
  description = "Name of the Purview managed resource group"
  value       = azurerm_purview_account.governance.managed_resource_group_name
}

output "purview_managed_identity_principal_id" {
  description = "Principal ID of the Purview managed identity"
  value       = azurerm_purview_account.governance.identity[0].principal_id
}

# Data Lake Storage Outputs
output "storage_account_name" {
  description = "Name of the Data Lake Storage account"
  value       = azurerm_storage_account.data_lake.name
}

output "storage_account_id" {
  description = "Resource ID of the Data Lake Storage account"
  value       = azurerm_storage_account.data_lake.id
}

output "storage_primary_endpoint" {
  description = "Primary blob endpoint for the storage account"
  value       = azurerm_storage_account.data_lake.primary_blob_endpoint
}

output "storage_primary_dfs_endpoint" {
  description = "Primary DFS (Data Lake) endpoint for the storage account"
  value       = azurerm_storage_account.data_lake.primary_dfs_endpoint
}

output "storage_primary_access_key" {
  description = "Primary access key for the storage account"
  value       = azurerm_storage_account.data_lake.primary_access_key
  sensitive   = true
}

output "storage_primary_connection_string" {
  description = "Primary connection string for the storage account"
  value       = azurerm_storage_account.data_lake.primary_connection_string
  sensitive   = true
}

output "data_containers" {
  description = "List of created data containers"
  value = {
    for k, v in azurerm_storage_container.data_containers : k => {
      name        = v.name
      access_type = v.container_access_type
      metadata    = v.metadata
    }
  }
}

# Azure Synapse Analytics Outputs (conditional)
output "synapse_workspace_name" {
  description = "Name of the Azure Synapse workspace"
  value       = var.enable_synapse_workspace ? azurerm_synapse_workspace.analytics[0].name : null
}

output "synapse_workspace_id" {
  description = "Resource ID of the Azure Synapse workspace"
  value       = var.enable_synapse_workspace ? azurerm_synapse_workspace.analytics[0].id : null
}

output "synapse_sql_endpoint" {
  description = "SQL endpoint for the Synapse workspace"
  value       = var.enable_synapse_workspace ? azurerm_synapse_workspace.analytics[0].connectivity_endpoints["sql"] : null
}

output "synapse_dev_endpoint" {
  description = "Development endpoint for the Synapse workspace"
  value       = var.enable_synapse_workspace ? azurerm_synapse_workspace.analytics[0].connectivity_endpoints["dev"] : null
}

output "synapse_web_endpoint" {
  description = "Web/Studio endpoint for the Synapse workspace"
  value       = var.enable_synapse_workspace ? azurerm_synapse_workspace.analytics[0].connectivity_endpoints["web"] : null
}

output "synapse_managed_identity_principal_id" {
  description = "Principal ID of the Synapse managed identity"
  value       = var.enable_synapse_workspace ? azurerm_synapse_workspace.analytics[0].identity[0].principal_id : null
}

output "synapse_filesystem_name" {
  description = "Name of the Synapse dedicated filesystem"
  value       = var.enable_synapse_workspace ? azurerm_storage_data_lake_gen2_filesystem.synapse[0].name : null
}

# Monitoring and Logging Outputs
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = var.enable_diagnostic_logs ? azurerm_log_analytics_workspace.governance[0].name : null
}

output "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics workspace"
  value       = var.enable_diagnostic_logs ? azurerm_log_analytics_workspace.governance[0].id : null
}

output "log_analytics_workspace_customer_id" {
  description = "Customer ID (workspace ID) of the Log Analytics workspace"
  value       = var.enable_diagnostic_logs ? azurerm_log_analytics_workspace.governance[0].workspace_id : null
}

# Security and Access Outputs
output "role_assignments" {
  description = "Summary of created role assignments"
  value = {
    purview_storage_reader = {
      principal_id = azurerm_purview_account.governance.identity[0].principal_id
      role         = "Storage Blob Data Reader"
      scope        = azurerm_storage_account.data_lake.name
    }
    purview_data_curator = {
      principal_id = data.azurerm_client_config.current.object_id
      role         = "Purview Data Curator"
      scope        = azurerm_purview_account.governance.name
    }
    purview_data_reader = {
      principal_id = data.azurerm_client_config.current.object_id
      role         = "Purview Data Reader"
      scope        = azurerm_purview_account.governance.name
    }
    synapse_purview_access = var.enable_synapse_workspace ? {
      principal_id = azurerm_synapse_workspace.analytics[0].identity[0].principal_id
      role         = "Purview Data Curator"
      scope        = azurerm_purview_account.governance.name
    } : null
  }
}

# Configuration Summary
output "deployment_summary" {
  description = "Summary of deployed resources and configuration"
  value = {
    environment                    = var.environment
    purview_account_name          = azurerm_purview_account.governance.name
    storage_account_name          = azurerm_storage_account.data_lake.name
    synapse_workspace_enabled     = var.enable_synapse_workspace
    synapse_workspace_name        = var.enable_synapse_workspace ? azurerm_synapse_workspace.analytics[0].name : "Not deployed"
    diagnostic_logs_enabled       = var.enable_diagnostic_logs
    containers_created           = length(azurerm_storage_container.data_containers)
    purview_public_access        = var.purview_public_network_access
    data_classification_enabled  = var.enable_data_classification
  }
}

# Connection Information for Next Steps
output "next_steps" {
  description = "URLs and information for accessing deployed resources"
  value = {
    purview_studio_url = "https://web.purview.azure.com/resource/${azurerm_purview_account.governance.name}"
    azure_portal_url   = "https://portal.azure.com/#@/resource${azurerm_resource_group.governance.id}"
    synapse_studio_url = var.enable_synapse_workspace ? azurerm_synapse_workspace.analytics[0].connectivity_endpoints["web"] : "Not applicable"
    
    instructions = [
      "1. Access Purview Studio to register the Data Lake Storage as a data source",
      "2. Configure scan rules and schedules for automated data discovery",
      "3. Set up custom classification rules for your specific data patterns",
      "4. Review and validate role assignments for proper access control",
      "5. If Synapse is enabled, configure linked services for data integration",
      "6. Monitor diagnostic logs in Log Analytics workspace for governance insights"
    ]
  }
}

# Sample Data Information
output "sample_data_info" {
  description = "Information about created sample data files"
  value = {
    customer_data = {
      container = "sensitive-data"
      path      = "customers/customers.csv"
      content   = "Contains PII data for classification testing"
    }
    order_data = {
      container = "raw-data"
      path      = "orders/orders.csv"
      content   = "Contains transactional data for lineage testing"
    }
    note = "These sample files are automatically created for testing data governance features"
  }
}

# Cost Estimation Information
output "cost_estimation" {
  description = "Estimated monthly costs for deployed resources (approximate USD)"
  value = {
    purview_account      = "$100-300 (depends on scanning volume)"
    storage_account      = "$10-50 (depends on data volume and access patterns)"
    synapse_workspace    = var.enable_synapse_workspace ? "$50-200 (depends on compute usage)" : "$0 (not deployed)"
    log_analytics        = var.enable_diagnostic_logs ? "$5-20 (depends on log volume)" : "$0 (not enabled)"
    total_estimated      = "$165-570 per month"
    note                = "Costs vary significantly based on usage patterns. Monitor Azure Cost Management for actual costs."
  }
}