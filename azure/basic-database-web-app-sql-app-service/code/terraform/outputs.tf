# Output Values for Basic Database Web App Infrastructure
# These outputs provide important information about the deployed resources

# Resource Group Information
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Location of the resource group"
  value       = azurerm_resource_group.main.location
}

# Web Application Outputs
output "web_app_name" {
  description = "Name of the deployed web application"
  value       = azurerm_windows_web_app.main.name
}

output "web_app_url" {
  description = "Default URL of the web application"
  value       = "https://${azurerm_windows_web_app.main.default_hostname}"
}

output "web_app_hostname" {
  description = "Default hostname of the web application"
  value       = azurerm_windows_web_app.main.default_hostname
}

output "web_app_id" {
  description = "Resource ID of the web application"
  value       = azurerm_windows_web_app.main.id
}

output "web_app_managed_identity_principal_id" {
  description = "Principal ID of the web app's system-assigned managed identity"
  value       = var.enable_system_assigned_identity ? azurerm_windows_web_app.main.identity[0].principal_id : null
}

output "web_app_managed_identity_tenant_id" {
  description = "Tenant ID of the web app's system-assigned managed identity"
  value       = var.enable_system_assigned_identity ? azurerm_windows_web_app.main.identity[0].tenant_id : null
}

# App Service Plan Outputs
output "app_service_plan_name" {
  description = "Name of the App Service Plan"
  value       = azurerm_service_plan.main.name
}

output "app_service_plan_id" {
  description = "Resource ID of the App Service Plan"
  value       = azurerm_service_plan.main.id
}

output "app_service_plan_sku" {
  description = "SKU of the App Service Plan"
  value       = azurerm_service_plan.main.sku_name
}

# SQL Database Server Outputs
output "sql_server_name" {
  description = "Name of the SQL Database server"
  value       = azurerm_mssql_server.main.name
}

output "sql_server_fqdn" {
  description = "Fully qualified domain name of the SQL Database server"
  value       = azurerm_mssql_server.main.fully_qualified_domain_name
}

output "sql_server_id" {
  description = "Resource ID of the SQL Database server"
  value       = azurerm_mssql_server.main.id
}

output "sql_admin_username" {
  description = "Administrator username for the SQL Database server"
  value       = azurerm_mssql_server.main.administrator_login
}

# SQL Database Outputs
output "sql_database_name" {
  description = "Name of the SQL Database"
  value       = azurerm_mssql_database.main.name
}

output "sql_database_id" {
  description = "Resource ID of the SQL Database"
  value       = azurerm_mssql_database.main.id
}

output "sql_database_sku" {
  description = "SKU of the SQL Database"
  value       = azurerm_mssql_database.main.sku_name
}

output "sql_database_max_size_gb" {
  description = "Maximum size of the SQL Database in GB"
  value       = azurerm_mssql_database.main.max_size_gb
}

# Database Connection Information
output "connection_string" {
  description = "SQL Database connection string for applications"
  value       = "Server=tcp:${azurerm_mssql_server.main.fully_qualified_domain_name},1433;Initial Catalog=${azurerm_mssql_database.main.name};Persist Security Info=False;User ID=${azurerm_mssql_server.main.administrator_login};Password=<password>;MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
  sensitive   = false
}

output "jdbc_connection_string" {
  description = "JDBC connection string for Java applications"
  value       = "jdbc:sqlserver://${azurerm_mssql_server.main.fully_qualified_domain_name}:1433;database=${azurerm_mssql_database.main.name};user=${azurerm_mssql_server.main.administrator_login};password=<password>;encrypt=true;trustServerCertificate=false;hostNameInCertificate=*.database.windows.net;loginTimeout=30;"
  sensitive   = false
}

# Application Insights Outputs (conditional)
output "application_insights_instrumentation_key" {
  description = "Application Insights instrumentation key"
  value       = var.enable_monitoring ? azurerm_application_insights.main[0].instrumentation_key : null
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Application Insights connection string"
  value       = var.enable_monitoring ? azurerm_application_insights.main[0].connection_string : null
  sensitive   = true
}

output "application_insights_app_id" {
  description = "Application Insights application ID"
  value       = var.enable_monitoring ? azurerm_application_insights.main[0].app_id : null
}

# Security and Compliance Information
output "firewall_rules" {
  description = "List of configured firewall rules"
  value = var.allow_azure_services_access ? [
    {
      name             = "AllowAzureServices"
      start_ip_address = "0.0.0.0"
      end_ip_address   = "0.0.0.0"
    }
  ] : []
}

output "backup_retention_days" {
  description = "Number of days backups are retained"
  value       = var.backup_retention_days
}

# Cost Management Information
output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown (USD, approximate)"
  value = {
    app_service_plan = var.app_service_sku_size == "B1" ? "~$13.14" : "varies by SKU"
    sql_database     = var.sql_sku_name == "Basic" ? "~$4.90" : "varies by SKU"
    total_estimated  = var.app_service_sku_size == "B1" && var.sql_sku_name == "Basic" ? "~$18.04" : "varies by configuration"
    note            = "Costs are estimates and may vary by region and usage patterns"
  }
}

# Deployment Information
output "deployment_metadata" {
  description = "Metadata about the Terraform deployment"
  value = {
    terraform_version = "~> 1.0"
    azurerm_version   = "~> 3.0"
    deployment_time   = timestamp()
    random_suffix     = local.random_suffix
    environment       = var.environment
    project_name      = var.project_name
  }
}

# Azure CLI Commands for Verification
output "verification_commands" {
  description = "Azure CLI commands to verify the deployment"
  value = {
    check_web_app = "az webapp show --name ${azurerm_windows_web_app.main.name} --resource-group ${azurerm_resource_group.main.name}"
    check_database = "az sql db show --name ${azurerm_mssql_database.main.name} --server ${azurerm_mssql_server.main.name} --resource-group ${azurerm_resource_group.main.name}"
    test_connectivity = "curl -I https://${azurerm_windows_web_app.main.default_hostname}"
    view_logs = "az webapp log tail --name ${azurerm_windows_web_app.main.name} --resource-group ${azurerm_resource_group.main.name}"
  }
}

# Resource Tags Applied
output "applied_tags" {
  description = "Tags applied to all resources"
  value       = local.common_tags
}