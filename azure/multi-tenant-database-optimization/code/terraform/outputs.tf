# Outputs for Azure Multi-Tenant Database Architecture
# This file defines all output values that provide important information about the deployed resources

# Resource Group Information
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Location of the resource group"
  value       = azurerm_resource_group.main.location
}

output "resource_group_id" {
  description = "Resource ID of the created resource group"
  value       = azurerm_resource_group.main.id
}

# SQL Server Information
output "sql_server_name" {
  description = "Name of the Azure SQL Server"
  value       = azurerm_mssql_server.main.name
}

output "sql_server_fqdn" {
  description = "Fully qualified domain name of the SQL Server"
  value       = azurerm_mssql_server.main.fully_qualified_domain_name
}

output "sql_server_id" {
  description = "Resource ID of the SQL Server"
  value       = azurerm_mssql_server.main.id
}

output "sql_admin_username" {
  description = "Administrator username for SQL Server"
  value       = azurerm_mssql_server.main.administrator_login
}

output "sql_admin_password" {
  description = "Administrator password for SQL Server (sensitive)"
  value       = local.sql_admin_password
  sensitive   = true
}

# Elastic Pool Information
output "elastic_pool_name" {
  description = "Name of the elastic database pool"
  value       = azurerm_mssql_elasticpool.main.name
}

output "elastic_pool_id" {
  description = "Resource ID of the elastic pool"
  value       = azurerm_mssql_elasticpool.main.id
}

output "elastic_pool_edition" {
  description = "Edition of the elastic pool"
  value       = azurerm_mssql_elasticpool.main.sku[0].tier
}

output "elastic_pool_capacity" {
  description = "DTU capacity of the elastic pool"
  value       = azurerm_mssql_elasticpool.main.sku[0].capacity
}

output "elastic_pool_max_size_gb" {
  description = "Maximum size of the elastic pool in GB"
  value       = azurerm_mssql_elasticpool.main.max_size_gb
}

# Tenant Database Information
output "tenant_database_names" {
  description = "List of tenant database names"
  value       = [for db in azurerm_mssql_database.tenant_databases : db.name]
}

output "tenant_database_ids" {
  description = "List of tenant database resource IDs"
  value       = [for db in azurerm_mssql_database.tenant_databases : db.id]
}

output "tenant_count" {
  description = "Number of tenant databases created"
  value       = length(azurerm_mssql_database.tenant_databases)
}

# Database Connection Information
output "tenant_database_connection_info" {
  description = "Connection information for each tenant database"
  value = {
    for db in azurerm_mssql_database.tenant_databases : db.name => {
      server_name   = azurerm_mssql_server.main.name
      server_fqdn   = azurerm_mssql_server.main.fully_qualified_domain_name
      database_name = db.name
      database_id   = db.id
      elastic_pool  = azurerm_mssql_elasticpool.main.name
    }
  }
}

# Connection String Template
output "connection_string_template" {
  description = "Template for SQL Server connection strings"
  value       = "Server=tcp:${azurerm_mssql_server.main.fully_qualified_domain_name},1433;Initial Catalog={{DATABASE_NAME}};Persist Security Info=False;User ID=${azurerm_mssql_server.main.administrator_login};Password={{PASSWORD}};MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
}

# Backup and Recovery Information
output "recovery_services_vault_name" {
  description = "Name of the Recovery Services Vault"
  value       = azurerm_recovery_services_vault.main.name
}

output "recovery_services_vault_id" {
  description = "Resource ID of the Recovery Services Vault"
  value       = azurerm_recovery_services_vault.main.id
}

output "data_protection_backup_vault_name" {
  description = "Name of the Data Protection Backup Vault"
  value       = azurerm_data_protection_backup_vault.main.name
}

output "data_protection_backup_vault_id" {
  description = "Resource ID of the Data Protection Backup Vault"
  value       = azurerm_data_protection_backup_vault.main.id
}

output "backup_storage_redundancy" {
  description = "Backup storage redundancy configuration"
  value       = var.backup_storage_redundancy
}

# Monitoring and Logging Information
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.name
}

output "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.id
}

output "application_insights_name" {
  description = "Name of the Application Insights instance"
  value       = azurerm_application_insights.main.name
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key for Application Insights"
  value       = azurerm_application_insights.main.instrumentation_key
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Connection string for Application Insights"
  value       = azurerm_application_insights.main.connection_string
  sensitive   = true
}

# Cost Management Information
output "budget_name" {
  description = "Name of the cost management budget"
  value       = azurerm_consumption_budget_resource_group.main.name
}

output "monthly_budget_amount" {
  description = "Monthly budget amount in USD"
  value       = azurerm_consumption_budget_resource_group.main.amount
}

output "budget_alert_threshold" {
  description = "Budget alert threshold percentage"
  value       = var.budget_alert_threshold
}

# Storage Account Information
output "audit_storage_account_name" {
  description = "Name of the storage account for audit logs"
  value       = azurerm_storage_account.audit.name
}

output "audit_storage_account_id" {
  description = "Resource ID of the audit storage account"
  value       = azurerm_storage_account.audit.id
}

# Security Information
output "sql_server_security_features" {
  description = "Enabled security features for the SQL Server"
  value = {
    automatic_tuning_enabled    = true
    vulnerability_assessment    = true
    threat_detection           = true
    auditing_enabled           = true
    azure_ad_authentication    = true
    minimum_tls_version        = azurerm_mssql_server.main.minimum_tls_version
  }
}

# Network Access Information
output "firewall_rules" {
  description = "Configured firewall rules for the SQL Server"
  value = {
    azure_services_allowed = var.allow_azure_services
    custom_ip_ranges      = var.allowed_ip_ranges
  }
}

# Performance and Configuration Information
output "elastic_pool_performance_settings" {
  description = "Performance settings for the elastic pool"
  value = {
    edition          = var.elastic_pool_edition
    dtu_capacity     = var.elastic_pool_dtu
    storage_mb       = var.elastic_pool_storage_mb
    min_dtu_per_db   = var.database_dtu_min
    max_dtu_per_db   = var.database_dtu_max
  }
}

# Deployment Information
output "deployment_info" {
  description = "Information about the deployment"
  value = {
    deployment_time    = timestamp()
    terraform_version  = "~> 1.8.0"
    azurerm_version   = "~> 3.115.0"
    random_suffix     = local.random_suffix
    environment       = var.environment
    project_name      = var.project_name
  }
}

# Management URLs
output "management_urls" {
  description = "Azure portal URLs for managing resources"
  value = {
    resource_group_url = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_resource_group.main.id}"
    sql_server_url     = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_mssql_server.main.id}"
    elastic_pool_url   = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_mssql_elasticpool.main.id}"
    backup_vault_url   = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_data_protection_backup_vault.main.id}"
    cost_management_url = "https://portal.azure.com/#blade/Microsoft_Azure_CostManagement/Menu/costanalysis/scope/%2Fsubscriptions%2F${data.azurerm_subscription.current.subscription_id}%2FresourceGroups%2F${azurerm_resource_group.main.name}"
  }
}

# Quick Start Commands
output "quick_start_commands" {
  description = "Useful commands for getting started with the deployed resources"
  value = {
    connect_to_sql_server = "sqlcmd -S ${azurerm_mssql_server.main.fully_qualified_domain_name} -U ${azurerm_mssql_server.main.administrator_login} -P [PASSWORD] -N -l 30"
    list_databases       = "az sql db list --server ${azurerm_mssql_server.main.name} --resource-group ${azurerm_resource_group.main.name} --output table"
    check_pool_usage     = "az sql elastic-pool show --name ${azurerm_mssql_elasticpool.main.name} --server ${azurerm_mssql_server.main.name} --resource-group ${azurerm_resource_group.main.name}"
    view_costs          = "az consumption usage list --start-date $(date -d '-7 days' +%Y-%m-%d) --end-date $(date +%Y-%m-%d) --output table"
  }
}

# Resource Tags
output "resource_tags" {
  description = "Tags applied to all resources"
  value       = local.common_tags
}