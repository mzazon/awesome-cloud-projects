# Outputs for Azure Self-Service Infrastructure Provisioning Solution

# Resource Group Information
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Location of the created resource group"
  value       = azurerm_resource_group.main.location
}

output "resource_group_id" {
  description = "ID of the created resource group"
  value       = azurerm_resource_group.main.id
}

# Azure DevCenter Information
output "devcenter_name" {
  description = "Name of the Azure DevCenter"
  value       = azurerm_dev_center.main.name
}

output "devcenter_id" {
  description = "ID of the Azure DevCenter"
  value       = azurerm_dev_center.main.id
}

output "devcenter_identity_principal_id" {
  description = "Principal ID of the DevCenter managed identity"
  value       = azurerm_dev_center.main.identity[0].principal_id
}

output "devcenter_dev_center_uri" {
  description = "URI of the Azure DevCenter"
  value       = azurerm_dev_center.main.dev_center_uri
}

# DevCenter Project Information
output "project_name" {
  description = "Name of the DevCenter project"
  value       = azurerm_dev_center_project.development.name
}

output "project_id" {
  description = "ID of the DevCenter project"
  value       = azurerm_dev_center_project.development.id
}

output "project_dev_center_project_uri" {
  description = "URI of the DevCenter project"
  value       = azurerm_dev_center_project.development.dev_center_project_uri
}

output "project_environment_type" {
  description = "Environment type configured for the project"
  value       = azurerm_dev_center_project_environment_type.development.name
}

# Environment Catalog Information
output "catalog_name" {
  description = "Name of the environment catalog"
  value       = azurerm_dev_center_catalog.templates.name
}

output "catalog_id" {
  description = "ID of the environment catalog"
  value       = azurerm_dev_center_catalog.templates.id
}

output "catalog_repo_url" {
  description = "Git repository URL for environment templates"
  value       = var.catalog_repo_url
}

# Key Vault Information
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

# Event Grid Information
output "event_grid_topic_name" {
  description = "Name of the Event Grid topic"
  value       = azurerm_eventgrid_topic.deployment_events.name
}

output "event_grid_topic_id" {
  description = "ID of the Event Grid topic"
  value       = azurerm_eventgrid_topic.deployment_events.id
}

output "event_grid_topic_endpoint" {
  description = "Endpoint of the Event Grid topic"
  value       = azurerm_eventgrid_topic.deployment_events.endpoint
}

# Logic Apps Information
output "logic_app_approval_name" {
  description = "Name of the approval Logic App"
  value       = azurerm_logic_app_workflow.approval.name
}

output "logic_app_approval_id" {
  description = "ID of the approval Logic App"
  value       = azurerm_logic_app_workflow.approval.id
}

output "logic_app_approval_trigger_url" {
  description = "Trigger URL for the approval Logic App"
  value       = azurerm_logic_app_trigger_http_request.approval_trigger.callback_url
  sensitive   = true
}

output "logic_app_lifecycle_name" {
  description = "Name of the lifecycle management Logic App"
  value       = var.enable_lifecycle_management ? azurerm_logic_app_workflow.lifecycle[0].name : null
}

output "logic_app_lifecycle_id" {
  description = "ID of the lifecycle management Logic App"
  value       = var.enable_lifecycle_management ? azurerm_logic_app_workflow.lifecycle[0].id : null
}

# SQL Server and Database Information
output "sql_server_name" {
  description = "Name of the SQL Server"
  value       = azurerm_mssql_server.main.name
}

output "sql_server_id" {
  description = "ID of the SQL Server"
  value       = azurerm_mssql_server.main.id
}

output "sql_server_fqdn" {
  description = "Fully qualified domain name of the SQL Server"
  value       = azurerm_mssql_server.main.fully_qualified_domain_name
}

output "sql_database_name" {
  description = "Name of the SQL Database"
  value       = azurerm_mssql_database.webapp.name
}

output "sql_database_id" {
  description = "ID of the SQL Database"
  value       = azurerm_mssql_database.webapp.id
}

output "sql_admin_username" {
  description = "SQL Server administrator username"
  value       = var.sql_admin_username
}

# Web Application Information
output "webapp_name" {
  description = "Name of the sample web application"
  value       = azurerm_linux_web_app.sample.name
}

output "webapp_id" {
  description = "ID of the sample web application"
  value       = azurerm_linux_web_app.sample.id
}

output "webapp_url" {
  description = "URL of the sample web application"
  value       = "https://${azurerm_linux_web_app.sample.default_hostname}"
}

output "webapp_identity_principal_id" {
  description = "Principal ID of the web app managed identity"
  value       = azurerm_linux_web_app.sample.identity[0].principal_id
}

# Service Connector Information
output "service_connector_name" {
  description = "Name of the Service Connector"
  value       = azurerm_app_service_connection.webapp_sql.name
}

output "service_connector_id" {
  description = "ID of the Service Connector"
  value       = azurerm_app_service_connection.webapp_sql.id
}

# Storage Account Information
output "storage_account_name" {
  description = "Name of the storage account for Event Grid dead letter"
  value       = azurerm_storage_account.events.name
}

output "storage_account_id" {
  description = "ID of the storage account"
  value       = azurerm_storage_account.events.id
}

output "storage_account_primary_endpoint" {
  description = "Primary blob endpoint of the storage account"
  value       = azurerm_storage_account.events.primary_blob_endpoint
}

# Random Suffix
output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = local.suffix
}

# Deployment Information
output "subscription_id" {
  description = "Azure subscription ID where resources are deployed"
  value       = data.azurerm_client_config.current.subscription_id
}

output "tenant_id" {
  description = "Azure tenant ID"
  value       = data.azurerm_client_config.current.tenant_id
}

output "deployment_identity" {
  description = "Object ID of the identity used for deployment"
  value       = data.azurerm_client_config.current.object_id
}

# Connection Information for Developers
output "developer_portal_url" {
  description = "URL for developers to access the DevCenter portal"
  value       = "https://devportal.microsoft.com/"
}

output "azure_cli_commands" {
  description = "Azure CLI commands for developers to interact with environments"
  value = {
    list_environments = "az devcenter dev environment list --project-name ${azurerm_dev_center_project.development.name} --dev-center-name ${azurerm_dev_center.main.name}"
    create_environment = "az devcenter dev environment create --project-name ${azurerm_dev_center_project.development.name} --dev-center-name ${azurerm_dev_center.main.name} --environment-name <env-name> --environment-type ${azurerm_dev_center_project_environment_type.development.name} --catalog-name ${azurerm_dev_center_catalog.templates.name} --environment-definition-name <definition-name>"
    delete_environment = "az devcenter dev environment delete --project-name ${azurerm_dev_center_project.development.name} --dev-center-name ${azurerm_dev_center.main.name} --environment-name <env-name> --user-id me"
  }
}

# Resource URLs for Management
output "resource_urls" {
  description = "Azure portal URLs for key resources"
  value = {
    resource_group = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${azurerm_resource_group.main.name}"
    devcenter      = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_dev_center.main.id}"
    project        = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_dev_center_project.development.id}"
    key_vault      = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_key_vault.main.id}"
    logic_apps     = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_logic_app_workflow.approval.id}"
    event_grid     = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_eventgrid_topic.deployment_events.id}"
    webapp         = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_linux_web_app.sample.id}"
    sql_server     = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_mssql_server.main.id}"
  }
}

# Environment Configuration
output "environment_configuration" {
  description = "Configuration details for environment management"
  value = {
    max_environments_per_user = var.max_dev_boxes_per_user
    environment_type         = var.project_environment_type
    environment_expiry_days  = var.environment_expiry_days
    lifecycle_management    = var.enable_lifecycle_management
    catalog_sync_status     = "Check Azure Portal for catalog synchronization status"
  }
}