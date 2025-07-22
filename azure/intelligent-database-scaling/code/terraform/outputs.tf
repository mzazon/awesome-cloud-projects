# Output Values
# This file defines outputs that provide important information after deployment

# Resource Group Information
output "resource_group_name" {
  description = "Name of the created resource group containing all resources"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Azure region where all resources are deployed"
  value       = azurerm_resource_group.main.location
}

output "resource_group_id" {
  description = "Resource ID of the created resource group"
  value       = azurerm_resource_group.main.id
}

# SQL Database Information
output "sql_server_name" {
  description = "Name of the Azure SQL Server hosting the Hyperscale database"
  value       = azurerm_mssql_server.main.name
}

output "sql_server_fqdn" {
  description = "Fully qualified domain name of the SQL Server"
  value       = azurerm_mssql_server.main.fully_qualified_domain_name
}

output "sql_database_name" {
  description = "Name of the Hyperscale database configured for autonomous scaling"
  value       = azurerm_mssql_database.main.name
}

output "sql_database_id" {
  description = "Resource ID of the Hyperscale database"
  value       = azurerm_mssql_database.main.id
}

output "sql_database_current_sku" {
  description = "Current SKU configuration of the Hyperscale database"
  value       = azurerm_mssql_database.main.sku_name
}

output "sql_database_max_size_gb" {
  description = "Maximum size in GB configured for the database"
  value       = azurerm_mssql_database.main.max_size_gb
}

# SQL Server Connection Information
output "sql_connection_string" {
  description = "Connection string template for the SQL Database (password not included)"
  value       = "Server=${azurerm_mssql_server.main.fully_qualified_domain_name};Database=${azurerm_mssql_database.main.name};User Id=${var.sql_server_admin_username};Password=<password>;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
  sensitive   = false
}

output "sql_admin_username" {
  description = "Administrator username for the SQL Server"
  value       = var.sql_server_admin_username
  sensitive   = true
}

# Key Vault Information
output "key_vault_name" {
  description = "Name of the Key Vault storing credentials and configuration"
  value       = azurerm_key_vault.main.name
}

output "key_vault_uri" {
  description = "URI of the Key Vault for accessing secrets"
  value       = azurerm_key_vault.main.vault_uri
}

output "key_vault_id" {
  description = "Resource ID of the Key Vault"
  value       = azurerm_key_vault.main.id
}

# Logic Apps Information
output "logic_app_name" {
  description = "Name of the Logic App managing autonomous scaling"
  value       = azurerm_logic_app_workflow.scaling.name
}

output "logic_app_id" {
  description = "Resource ID of the scaling Logic App"
  value       = azurerm_logic_app_workflow.scaling.id
}

output "logic_app_managed_identity_principal_id" {
  description = "Principal ID of the Logic App's system-assigned managed identity"
  value       = azurerm_logic_app_workflow.scaling.identity[0].principal_id
}

output "logic_app_access_endpoint" {
  description = "Management endpoint for the Logic App workflow"
  value       = azurerm_logic_app_workflow.scaling.access_endpoint
}

output "logic_app_callback_url" {
  description = "Callback URL for the Logic App HTTP trigger"
  value       = azurerm_logic_app_trigger_http_request.scaling_trigger.callback_url
  sensitive   = true
}

# Monitoring and Alerting Information
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace for monitoring"
  value       = azurerm_log_analytics_workspace.main.name
}

output "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.id
}

output "log_analytics_workspace_customer_id" {
  description = "Customer ID (workspace ID) for the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.workspace_id
}

output "application_insights_name" {
  description = "Name of the Application Insights instance for enhanced monitoring"
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

# Alert Configuration Information
output "action_group_name" {
  description = "Name of the action group handling scaling alerts"
  value       = azurerm_monitor_action_group.scaling_alerts.name
}

output "action_group_id" {
  description = "Resource ID of the scaling alerts action group"
  value       = azurerm_monitor_action_group.scaling_alerts.id
}

output "cpu_scale_up_alert_name" {
  description = "Name of the CPU scale-up alert rule"
  value       = azurerm_monitor_metric_alert.cpu_scale_up.name
}

output "cpu_scale_down_alert_name" {
  description = "Name of the CPU scale-down alert rule"
  value       = azurerm_monitor_metric_alert.cpu_scale_down.name
}

# Scaling Configuration Information
output "scaling_configuration" {
  description = "Summary of autonomous scaling configuration"
  value = {
    initial_vcores              = local.initial_vcores
    min_vcores                 = var.min_vcores
    max_vcores                 = var.max_vcores
    scaling_step_size          = var.scaling_step_size
    cpu_scale_up_threshold     = var.cpu_scale_up_threshold
    cpu_scale_down_threshold   = var.cpu_scale_down_threshold
    scale_up_window_minutes    = var.scale_up_evaluation_window_minutes
    scale_down_window_minutes  = var.scale_down_evaluation_window_minutes
  }
}

# Storage Account Information
output "storage_account_name" {
  description = "Name of the storage account used for diagnostics and Logic Apps"
  value       = azurerm_storage_account.main.name
}

output "storage_account_primary_endpoint" {
  description = "Primary blob endpoint of the storage account"
  value       = azurerm_storage_account.main.primary_blob_endpoint
}

# Security and Access Information
output "firewall_rules" {
  description = "List of configured SQL Server firewall rules"
  value = merge(
    {
      azure_services = {
        name     = azurerm_mssql_firewall_rule.allow_azure_services.name
        start_ip = azurerm_mssql_firewall_rule.allow_azure_services.start_ip_address
        end_ip   = azurerm_mssql_firewall_rule.allow_azure_services.end_ip_address
      }
    },
    {
      for idx, rule in azurerm_mssql_firewall_rule.custom_ranges :
      rule.name => {
        name     = rule.name
        start_ip = rule.start_ip_address
        end_ip   = rule.end_ip_address
      }
    }
  )
}

# Cost Management Information
output "budget_configuration" {
  description = "Cost budget configuration (if enabled)"
  value = var.enable_cost_alerts ? {
    budget_name     = azurerm_consumption_budget_resource_group.main[0].name
    monthly_limit   = var.monthly_budget_limit
    alert_threshold = 80
  } : null
}

# Deployment Summary
output "deployment_summary" {
  description = "Summary of the deployed autonomous scaling solution"
  value = {
    solution_name           = "Autonomous Database Scaling"
    environment            = var.environment
    project_name           = var.project_name
    deployment_date        = timestamp()
    resource_count         = 15  # Approximate count of major resources
    hyperscale_database    = "${azurerm_mssql_server.main.name}/${azurerm_mssql_database.main.name}"
    scaling_automation     = azurerm_logic_app_workflow.scaling.name
    monitoring_workspace   = azurerm_log_analytics_workspace.main.name
    security_vault        = azurerm_key_vault.main.name
  }
}

# Validation and Testing Information
output "validation_queries" {
  description = "Sample queries for validating the deployment"
  value = {
    check_database_status = "SELECT name, state_desc, service_objective FROM sys.databases WHERE name = '${azurerm_mssql_database.main.name}'"
    check_cpu_metrics     = "Monitor CPU percentage in Azure Portal under ${azurerm_mssql_database.main.name} > Metrics"
    logic_app_runs        = "Check Logic App run history in Azure Portal under ${azurerm_logic_app_workflow.scaling.name}"
    alert_status          = "View alert rules in Azure Portal under Monitor > Alerts"
  }
}

# Troubleshooting Information
output "troubleshooting_info" {
  description = "Key information for troubleshooting the autonomous scaling solution"
  value = {
    logic_app_managed_identity = azurerm_logic_app_workflow.scaling.identity[0].principal_id
    required_permissions = [
      "SQL DB Contributor on Resource Group",
      "Key Vault Secrets User on Key Vault",
      "Log Analytics Contributor on Workspace"
    ]
    key_vault_secrets = [
      "sql-admin-username",
      "sql-admin-password"
    ]
    monitoring_endpoints = {
      log_analytics = azurerm_log_analytics_workspace.main.workspace_id
      app_insights  = azurerm_application_insights.main.app_id
    }
  }
}

# Connection and Access URLs
output "azure_portal_links" {
  description = "Direct links to key resources in Azure Portal"
  value = {
    resource_group = "https://portal.azure.com/#@/resource/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${azurerm_resource_group.main.name}/overview"
    sql_database   = "https://portal.azure.com/#@/resource${azurerm_mssql_database.main.id}/overview"
    logic_app      = "https://portal.azure.com/#@/resource${azurerm_logic_app_workflow.scaling.id}/overview"
    key_vault      = "https://portal.azure.com/#@/resource${azurerm_key_vault.main.id}/overview"
    log_analytics  = "https://portal.azure.com/#@/resource${azurerm_log_analytics_workspace.main.id}/overview"
  }
}

# Next Steps Information
output "next_steps" {
  description = "Recommended next steps after deployment"
  value = [
    "1. Test database connection using the provided connection string",
    "2. Verify Logic App workflow execution in Azure Portal",
    "3. Check CPU metrics and alert rules configuration",
    "4. Review Log Analytics workspace for scaling operation logs",
    "5. Consider enabling additional security features for production use",
    "6. Set up custom dashboards in Azure Monitor for scaling insights",
    "7. Test scaling behavior by generating CPU load on the database"
  ]
}