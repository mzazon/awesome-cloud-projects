# ==============================================================================
# TERRAFORM OUTPUTS
# ==============================================================================
# This file defines all the output values that will be returned after
# successful deployment of the blockchain supply chain transparency infrastructure.

# ==============================================================================
# RESOURCE GROUP OUTPUTS
# ==============================================================================

output "resource_group_name" {
  description = "The name of the resource group containing all resources"
  value       = azurerm_resource_group.main.name
}

output "resource_group_id" {
  description = "The ID of the resource group"
  value       = azurerm_resource_group.main.id
}

output "resource_group_location" {
  description = "The location of the resource group"
  value       = azurerm_resource_group.main.location
}

# ==============================================================================
# AZURE CONFIDENTIAL LEDGER OUTPUTS
# ==============================================================================

output "confidential_ledger_name" {
  description = "The name of the Confidential Ledger"
  value       = azurerm_confidential_ledger.main.name
}

output "confidential_ledger_id" {
  description = "The ID of the Confidential Ledger"
  value       = azurerm_confidential_ledger.main.id
}

output "confidential_ledger_endpoint" {
  description = "The endpoint URL of the Confidential Ledger for API access"
  value       = azurerm_confidential_ledger.main.ledger_endpoint
}

output "confidential_ledger_identity_service_endpoint" {
  description = "The identity service endpoint of the Confidential Ledger"
  value       = azurerm_confidential_ledger.main.identity_service_endpoint
}

# ==============================================================================
# AZURE COSMOS DB OUTPUTS
# ==============================================================================

output "cosmos_db_account_name" {
  description = "The name of the Cosmos DB account"
  value       = azurerm_cosmosdb_account.main.name
}

output "cosmos_db_account_id" {
  description = "The ID of the Cosmos DB account"
  value       = azurerm_cosmosdb_account.main.id
}

output "cosmos_db_endpoint" {
  description = "The endpoint URL of the Cosmos DB account"
  value       = azurerm_cosmosdb_account.main.endpoint
}

output "cosmos_db_read_endpoints" {
  description = "List of read endpoints for the Cosmos DB account"
  value       = azurerm_cosmosdb_account.main.read_endpoints
}

output "cosmos_db_write_endpoints" {
  description = "List of write endpoints for the Cosmos DB account"
  value       = azurerm_cosmosdb_account.main.write_endpoints
}

output "cosmos_db_primary_key" {
  description = "The primary master key for the Cosmos DB account"
  value       = azurerm_cosmosdb_account.main.primary_key
  sensitive   = true
}

output "cosmos_db_secondary_key" {
  description = "The secondary master key for the Cosmos DB account"
  value       = azurerm_cosmosdb_account.main.secondary_key
  sensitive   = true
}

output "cosmos_db_connection_strings" {
  description = "List of connection strings for the Cosmos DB account"
  value       = azurerm_cosmosdb_account.main.connection_strings
  sensitive   = true
}

output "cosmos_db_database_name" {
  description = "The name of the Cosmos DB SQL database"
  value       = azurerm_cosmosdb_sql_database.supply_chain_db.name
}

output "cosmos_db_products_container_name" {
  description = "The name of the products container"
  value       = azurerm_cosmosdb_sql_container.products.name
}

output "cosmos_db_transactions_container_name" {
  description = "The name of the transactions container"
  value       = azurerm_cosmosdb_sql_container.transactions.name
}

# ==============================================================================
# AZURE KEY VAULT OUTPUTS
# ==============================================================================

output "key_vault_name" {
  description = "The name of the Key Vault"
  value       = azurerm_key_vault.main.name
}

output "key_vault_id" {
  description = "The ID of the Key Vault"
  value       = azurerm_key_vault.main.id
}

output "key_vault_uri" {
  description = "The URI of the Key Vault"
  value       = azurerm_key_vault.main.vault_uri
}

output "key_vault_hsm_uri" {
  description = "The HSM URI of the Key Vault"
  value       = azurerm_key_vault.main.hsm_uri
}

# ==============================================================================
# EVENT GRID OUTPUTS
# ==============================================================================

output "event_grid_topic_name" {
  description = "The name of the Event Grid topic"
  value       = azurerm_eventgrid_topic.main.name
}

output "event_grid_topic_id" {
  description = "The ID of the Event Grid topic"
  value       = azurerm_eventgrid_topic.main.id
}

output "event_grid_endpoint" {
  description = "The endpoint URL of the Event Grid topic"
  value       = azurerm_eventgrid_topic.main.endpoint
}

output "event_grid_primary_key" {
  description = "The primary access key for the Event Grid topic"
  value       = azurerm_eventgrid_topic.main.primary_access_key
  sensitive   = true
}

output "event_grid_secondary_key" {
  description = "The secondary access key for the Event Grid topic"
  value       = azurerm_eventgrid_topic.main.secondary_access_key
  sensitive   = true
}

# ==============================================================================
# STORAGE ACCOUNT OUTPUTS
# ==============================================================================

output "storage_account_name" {
  description = "The name of the storage account"
  value       = azurerm_storage_account.main.name
}

output "storage_account_id" {
  description = "The ID of the storage account"
  value       = azurerm_storage_account.main.id
}

output "storage_account_primary_endpoint" {
  description = "The primary blob endpoint of the storage account"
  value       = azurerm_storage_account.main.primary_blob_endpoint
}

output "storage_account_secondary_endpoint" {
  description = "The secondary blob endpoint of the storage account"
  value       = azurerm_storage_account.main.secondary_blob_endpoint
}

output "storage_account_primary_access_key" {
  description = "The primary access key for the storage account"
  value       = azurerm_storage_account.main.primary_access_key
  sensitive   = true
}

output "storage_account_secondary_access_key" {
  description = "The secondary access key for the storage account"
  value       = azurerm_storage_account.main.secondary_access_key
  sensitive   = true
}

output "storage_account_primary_connection_string" {
  description = "The primary connection string for the storage account"
  value       = azurerm_storage_account.main.primary_connection_string
  sensitive   = true
}

output "storage_documents_container_name" {
  description = "The name of the documents container"
  value       = azurerm_storage_container.documents.name
}

output "storage_certificates_container_name" {
  description = "The name of the certificates container"
  value       = azurerm_storage_container.certificates.name
}

# ==============================================================================
# LOGIC APP OUTPUTS
# ==============================================================================

output "logic_app_workflow_name" {
  description = "The name of the Logic App workflow"
  value       = azurerm_logic_app_workflow.main.name
}

output "logic_app_workflow_id" {
  description = "The ID of the Logic App workflow"
  value       = azurerm_logic_app_workflow.main.id
}

output "logic_app_access_endpoint" {
  description = "The access endpoint of the Logic App workflow"
  value       = azurerm_logic_app_workflow.main.access_endpoint
}

# ==============================================================================
# API MANAGEMENT OUTPUTS
# ==============================================================================

output "api_management_name" {
  description = "The name of the API Management service"
  value       = azurerm_api_management.main.name
}

output "api_management_id" {
  description = "The ID of the API Management service"
  value       = azurerm_api_management.main.id
}

output "api_management_gateway_url" {
  description = "The gateway URL of the API Management service"
  value       = azurerm_api_management.main.gateway_url
}

output "api_management_public_ip_addresses" {
  description = "List of public IP addresses of the API Management service"
  value       = azurerm_api_management.main.public_ip_addresses
}

output "api_management_private_ip_addresses" {
  description = "List of private IP addresses of the API Management service"
  value       = azurerm_api_management.main.private_ip_addresses
}

output "api_management_developer_portal_url" {
  description = "The developer portal URL of the API Management service"
  value       = azurerm_api_management.main.developer_portal_url
}

output "api_management_scm_url" {
  description = "The SCM URL of the API Management service"
  value       = azurerm_api_management.main.scm_url
}

output "supply_chain_api_name" {
  description = "The name of the supply chain API"
  value       = azurerm_api_management_api.supply_chain.name
}

output "supply_chain_api_id" {
  description = "The ID of the supply chain API"
  value       = azurerm_api_management_api.supply_chain.id
}

# ==============================================================================
# MONITORING OUTPUTS
# ==============================================================================

output "log_analytics_workspace_name" {
  description = "The name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.name
}

output "log_analytics_workspace_id" {
  description = "The workspace ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.workspace_id
}

output "log_analytics_workspace_primary_shared_key" {
  description = "The primary shared key of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.primary_shared_key
  sensitive   = true
}

output "log_analytics_workspace_secondary_shared_key" {
  description = "The secondary shared key of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.secondary_shared_key
  sensitive   = true
}

output "application_insights_name" {
  description = "The name of the Application Insights component"
  value       = azurerm_application_insights.main.name
}

output "application_insights_id" {
  description = "The ID of the Application Insights component"
  value       = azurerm_application_insights.main.id
}

output "application_insights_app_id" {
  description = "The application ID of the Application Insights component"
  value       = azurerm_application_insights.main.app_id
}

output "application_insights_instrumentation_key" {
  description = "The instrumentation key of the Application Insights component"
  value       = azurerm_application_insights.main.instrumentation_key
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "The connection string of the Application Insights component"
  value       = azurerm_application_insights.main.connection_string
  sensitive   = true
}

# ==============================================================================
# MANAGED IDENTITY OUTPUTS
# ==============================================================================

output "managed_identity_name" {
  description = "The name of the user-assigned managed identity"
  value       = azurerm_user_assigned_identity.logic_app_identity.name
}

output "managed_identity_id" {
  description = "The ID of the user-assigned managed identity"
  value       = azurerm_user_assigned_identity.logic_app_identity.id
}

output "managed_identity_principal_id" {
  description = "The principal ID of the user-assigned managed identity"
  value       = azurerm_user_assigned_identity.logic_app_identity.principal_id
}

output "managed_identity_client_id" {
  description = "The client ID of the user-assigned managed identity"
  value       = azurerm_user_assigned_identity.logic_app_identity.client_id
}

# ==============================================================================
# AZURE AD OUTPUTS
# ==============================================================================

output "azure_ad_application_id" {
  description = "The application ID of the Azure AD application"
  value       = azuread_application.ledger_app.application_id
}

output "azure_ad_application_object_id" {
  description = "The object ID of the Azure AD application"
  value       = azuread_application.ledger_app.object_id
}

output "azure_ad_service_principal_id" {
  description = "The object ID of the Azure AD service principal"
  value       = azuread_service_principal.ledger_sp.object_id
}

output "azure_ad_service_principal_application_id" {
  description = "The application ID of the Azure AD service principal"
  value       = azuread_service_principal.ledger_sp.application_id
}

# ==============================================================================
# ALERT OUTPUTS
# ==============================================================================

output "action_group_name" {
  description = "The name of the monitor action group"
  value       = azurerm_monitor_action_group.main.name
}

output "action_group_id" {
  description = "The ID of the monitor action group"
  value       = azurerm_monitor_action_group.main.id
}

output "high_transaction_volume_alert_name" {
  description = "The name of the high transaction volume alert"
  value       = azurerm_monitor_metric_alert.high_transaction_volume.name
}

output "high_transaction_volume_alert_id" {
  description = "The ID of the high transaction volume alert"
  value       = azurerm_monitor_metric_alert.high_transaction_volume.id
}

# ==============================================================================
# DIAGNOSTIC SETTINGS OUTPUTS
# ==============================================================================

output "cosmos_diagnostics_name" {
  description = "The name of the Cosmos DB diagnostic settings"
  value       = azurerm_monitor_diagnostic_setting.cosmos_diagnostics.name
}

output "cosmos_diagnostics_id" {
  description = "The ID of the Cosmos DB diagnostic settings"
  value       = azurerm_monitor_diagnostic_setting.cosmos_diagnostics.id
}

output "eventgrid_diagnostics_name" {
  description = "The name of the Event Grid diagnostic settings"
  value       = azurerm_monitor_diagnostic_setting.eventgrid_diagnostics.name
}

output "eventgrid_diagnostics_id" {
  description = "The ID of the Event Grid diagnostic settings"
  value       = azurerm_monitor_diagnostic_setting.eventgrid_diagnostics.id
}

# ==============================================================================
# INFRASTRUCTURE SUMMARY OUTPUTS
# ==============================================================================

output "deployment_summary" {
  description = "Summary of the deployed infrastructure"
  value = {
    resource_group_name           = azurerm_resource_group.main.name
    location                     = azurerm_resource_group.main.location
    confidential_ledger_endpoint = azurerm_confidential_ledger.main.ledger_endpoint
    cosmos_db_endpoint           = azurerm_cosmosdb_account.main.endpoint
    api_management_gateway_url   = azurerm_api_management.main.gateway_url
    event_grid_endpoint          = azurerm_eventgrid_topic.main.endpoint
    storage_account_name         = azurerm_storage_account.main.name
    key_vault_uri               = azurerm_key_vault.main.vault_uri
    logic_app_workflow_name     = azurerm_logic_app_workflow.main.name
    application_insights_app_id  = azurerm_application_insights.main.app_id
    log_analytics_workspace_id   = azurerm_log_analytics_workspace.main.workspace_id
  }
}

# ==============================================================================
# CONNECTION INFORMATION OUTPUTS
# ==============================================================================

output "connection_info" {
  description = "Connection information for external systems"
  value = {
    cosmos_db_connection_string = "AccountEndpoint=${azurerm_cosmosdb_account.main.endpoint};AccountKey=${azurerm_cosmosdb_account.main.primary_key};"
    storage_connection_string   = azurerm_storage_account.main.primary_connection_string
    event_grid_endpoint         = azurerm_eventgrid_topic.main.endpoint
    key_vault_uri              = azurerm_key_vault.main.vault_uri
    ledger_endpoint            = azurerm_confidential_ledger.main.ledger_endpoint
    api_gateway_url            = azurerm_api_management.main.gateway_url
    application_insights_key    = azurerm_application_insights.main.instrumentation_key
  }
  sensitive = true
}

# ==============================================================================
# TESTING ENDPOINTS
# ==============================================================================

output "testing_endpoints" {
  description = "Endpoints for testing the supply chain solution"
  value = {
    supply_chain_api_url = "${azurerm_api_management.main.gateway_url}/supply-chain/transactions"
    logic_app_trigger_url = azurerm_logic_app_workflow.main.access_endpoint
    cosmos_db_data_explorer_url = "https://cosmos.azure.com/?account=${azurerm_cosmosdb_account.main.name}"
    application_insights_url = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_application_insights.main.id}"
    key_vault_url = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_key_vault.main.id}"
  }
}

# ==============================================================================
# AZURE PORTAL URLS
# ==============================================================================

output "azure_portal_urls" {
  description = "Azure portal URLs for managing resources"
  value = {
    resource_group_url = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_resource_group.main.id}"
    confidential_ledger_url = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_confidential_ledger.main.id}"
    cosmos_db_url = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_cosmosdb_account.main.id}"
    api_management_url = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_api_management.main.id}"
    logic_app_url = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_logic_app_workflow.main.id}"
    storage_account_url = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_storage_account.main.id}"
    key_vault_url = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_key_vault.main.id}"
    log_analytics_url = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_log_analytics_workspace.main.id}"
    application_insights_url = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_application_insights.main.id}"
  }
}

# ==============================================================================
# NEXT STEPS
# ==============================================================================

output "next_steps" {
  description = "Next steps to complete the supply chain solution setup"
  value = [
    "1. Configure Logic App workflow with the provided endpoints",
    "2. Set up API Management policies and authentication",
    "3. Test the end-to-end transaction flow using the testing endpoints",
    "4. Configure monitoring alerts and dashboards",
    "5. Set up Event Grid subscriptions for downstream systems",
    "6. Configure backup and disaster recovery policies",
    "7. Review and adjust security settings as needed",
    "8. Create documentation for supply chain partners"
  ]
}