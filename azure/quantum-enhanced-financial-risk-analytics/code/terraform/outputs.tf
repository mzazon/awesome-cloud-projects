# Outputs for Azure Quantum-Enhanced Financial Risk Analytics Infrastructure

# Resource Group Information
output "resource_group_name" {
  description = "Name of the resource group containing all resources"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Azure region where resources are deployed"
  value       = azurerm_resource_group.main.location
}

# Azure Synapse Analytics Outputs
output "synapse_workspace_name" {
  description = "Name of the Azure Synapse Analytics workspace"
  value       = azurerm_synapse_workspace.main.name
}

output "synapse_workspace_id" {
  description = "Resource ID of the Azure Synapse Analytics workspace"
  value       = azurerm_synapse_workspace.main.id
}

output "synapse_workspace_endpoint" {
  description = "Development endpoint URL for Synapse workspace"
  value       = azurerm_synapse_workspace.main.connectivity_endpoints.dev
}

output "synapse_workspace_sql_endpoint" {
  description = "SQL endpoint URL for Synapse workspace"
  value       = azurerm_synapse_workspace.main.connectivity_endpoints.sql
}

output "synapse_workspace_sql_on_demand_endpoint" {
  description = "SQL on-demand endpoint URL for Synapse workspace"
  value       = azurerm_synapse_workspace.main.connectivity_endpoints.sql_on_demand
}

output "synapse_spark_pool_name" {
  description = "Name of the Synapse Apache Spark pool"
  value       = azurerm_synapse_spark_pool.main.name
}

output "synapse_sql_administrator_login" {
  description = "SQL administrator login for Synapse workspace"
  value       = azurerm_synapse_workspace.main.sql_administrator_login
}

# Azure Quantum Outputs
output "quantum_workspace_name" {
  description = "Name of the Azure Quantum workspace"
  value       = azurerm_quantum_workspace.main.name
}

output "quantum_workspace_id" {
  description = "Resource ID of the Azure Quantum workspace"
  value       = azurerm_quantum_workspace.main.id
}

# Azure Machine Learning Outputs
output "ml_workspace_name" {
  description = "Name of the Azure Machine Learning workspace"
  value       = azurerm_machine_learning_workspace.main.name
}

output "ml_workspace_id" {
  description = "Resource ID of the Azure Machine Learning workspace"
  value       = azurerm_machine_learning_workspace.main.id
}

output "ml_workspace_endpoint" {
  description = "Discovery URL for the Azure Machine Learning workspace"
  value       = azurerm_machine_learning_workspace.main.discovery_url
}

output "ml_compute_cluster_name" {
  description = "Name of the Machine Learning compute cluster"
  value       = azurerm_machine_learning_compute_cluster.main.name
}

# Data Storage Outputs
output "data_lake_storage_name" {
  description = "Name of the Data Lake Storage Gen2 account"
  value       = azurerm_storage_account.data_lake.name
}

output "data_lake_storage_id" {
  description = "Resource ID of the Data Lake Storage account"
  value       = azurerm_storage_account.data_lake.id
}

output "data_lake_primary_endpoint" {
  description = "Primary blob endpoint for Data Lake Storage"
  value       = azurerm_storage_account.data_lake.primary_blob_endpoint
}

output "data_lake_primary_dfs_endpoint" {
  description = "Primary DFS endpoint for Data Lake Storage Gen2"
  value       = azurerm_storage_account.data_lake.primary_dfs_endpoint
}

output "storage_containers" {
  description = "List of created storage containers for financial data"
  value = {
    market_data    = azurerm_storage_container.market_data.name
    portfolio_data = azurerm_storage_container.portfolio_data.name
    risk_models    = azurerm_storage_container.risk_models.name
    quantum_results = azurerm_storage_container.quantum_results.name
  }
}

# Security and Access Outputs
output "key_vault_name" {
  description = "Name of the Azure Key Vault"
  value       = azurerm_key_vault.main.name
}

output "key_vault_id" {
  description = "Resource ID of the Azure Key Vault"
  value       = azurerm_key_vault.main.id
}

output "key_vault_uri" {
  description = "URI of the Azure Key Vault"
  value       = azurerm_key_vault.main.vault_uri
}

# Cosmos DB Outputs
output "cosmos_db_account_name" {
  description = "Name of the Cosmos DB account"
  value       = azurerm_cosmosdb_account.main.name
}

output "cosmos_db_endpoint" {
  description = "Endpoint URL for Cosmos DB account"
  value       = azurerm_cosmosdb_account.main.endpoint
}

output "cosmos_db_database_name" {
  description = "Name of the financial analytics database"
  value       = azurerm_cosmosdb_sql_database.financial_analytics.name
}

output "cosmos_db_containers" {
  description = "List of Cosmos DB containers for analytics data"
  value = {
    risk_metrics     = azurerm_cosmosdb_sql_container.risk_metrics.name
    quantum_results  = azurerm_cosmosdb_sql_container.quantum_results.name
  }
}

# Monitoring Outputs
output "application_insights_name" {
  description = "Name of Application Insights instance"
  value       = var.enable_monitoring ? azurerm_application_insights.main[0].name : null
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

output "log_analytics_workspace_name" {
  description = "Name of Log Analytics workspace"
  value       = var.enable_monitoring ? azurerm_log_analytics_workspace.main[0].name : null
}

output "log_analytics_workspace_id" {
  description = "Resource ID of Log Analytics workspace"
  value       = var.enable_monitoring ? azurerm_log_analytics_workspace.main[0].id : null
}

# Network Outputs
output "virtual_network_name" {
  description = "Name of the virtual network (if private endpoints enabled)"
  value       = var.enable_private_endpoints ? azurerm_virtual_network.main[0].name : null
}

output "private_endpoints_subnet_name" {
  description = "Name of the private endpoints subnet"
  value       = var.enable_private_endpoints ? azurerm_subnet.private_endpoints[0].name : null
}

# Service Principal and Identity Outputs
output "synapse_workspace_principal_id" {
  description = "Principal ID of Synapse workspace managed identity"
  value       = azurerm_synapse_workspace.main.identity[0].principal_id
}

output "ml_workspace_principal_id" {
  description = "Principal ID of ML workspace managed identity"
  value       = azurerm_machine_learning_workspace.main.identity[0].principal_id
}

output "ml_compute_principal_id" {
  description = "Principal ID of ML compute cluster managed identity"
  value       = azurerm_machine_learning_compute_cluster.main.identity[0].principal_id
}

# Configuration and Connection Information
output "deployment_configuration" {
  description = "Key configuration details for the deployed infrastructure"
  value = {
    environment           = var.environment
    project_name         = var.project_name
    location             = var.location
    resource_suffix      = local.suffix
    quantum_enabled      = true
    monitoring_enabled   = var.enable_monitoring
    private_endpoints    = var.enable_private_endpoints
    spark_pool_config    = {
      node_size = var.spark_pool_node_size
      min_nodes = var.spark_pool_min_nodes
      max_nodes = var.spark_pool_max_nodes
    }
  }
}

# Quick Start Commands
output "quick_start_commands" {
  description = "Useful commands to get started with the deployed infrastructure"
  value = {
    # Azure CLI commands for accessing resources
    login_synapse = "az synapse workspace show --name ${azurerm_synapse_workspace.main.name} --resource-group ${azurerm_resource_group.main.name}"
    
    # Python SDK connection examples
    quantum_connection = "from azure.quantum import Workspace; workspace = Workspace(subscription_id='<subscription>', resource_group='${azurerm_resource_group.main.name}', name='${azurerm_quantum_workspace.main.name}')"
    
    # Storage access
    storage_connection = "az storage account show-connection-string --name ${azurerm_storage_account.data_lake.name} --resource-group ${azurerm_resource_group.main.name}"
    
    # Key Vault access
    key_vault_secrets = "az keyvault secret list --vault-name ${azurerm_key_vault.main.name}"
  }
}

# Important URLs and Endpoints
output "important_urls" {
  description = "Important URLs for accessing deployed services"
  value = {
    synapse_studio     = "https://web.azuresynapse.net?workspace=${azurerm_synapse_workspace.main.name}"
    ml_studio          = "https://ml.azure.com/workspaces/${azurerm_machine_learning_workspace.main.id}"
    azure_portal       = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_resource_group.main.id}"
    quantum_workspace  = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_quantum_workspace.main.id}"
    key_vault         = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_key_vault.main.id}"
    cosmos_db         = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_cosmosdb_account.main.id}"
  }
}

# Cost Management Information
output "cost_management_info" {
  description = "Information for monitoring and managing costs"
  value = {
    resource_group_id = azurerm_resource_group.main.id
    primary_cost_drivers = [
      "Synapse Analytics Workspace and Spark Pool",
      "Azure Quantum Workspace (pay-per-use)",
      "Machine Learning Compute Cluster",
      "Data Lake Storage Gen2",
      "Cosmos DB with provisioned throughput"
    ]
    cost_optimization_tips = [
      "Auto-pause Spark pools when not in use",
      "Scale down ML compute clusters during off-hours",
      "Use Cosmos DB autoscale for variable workloads",
      "Monitor quantum usage and optimize algorithms",
      "Implement data lifecycle policies for storage"
    ]
  }
}

# Security Configuration Summary
output "security_summary" {
  description = "Summary of security configurations applied"
  value = {
    key_vault_enabled     = true
    managed_identities    = true
    private_endpoints     = var.enable_private_endpoints
    tls_min_version      = "TLS1_2"
    firewall_configured  = true
    backup_enabled       = true
    soft_delete_enabled  = true
    rbac_configured      = true
    encryption_at_rest   = true
  }
}