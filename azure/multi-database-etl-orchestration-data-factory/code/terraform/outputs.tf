# Output values for Enterprise ETL Orchestration Infrastructure

# Resource Group Information
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.etl_orchestration.name
}

output "resource_group_location" {
  description = "Location of the resource group"
  value       = azurerm_resource_group.etl_orchestration.location
}

# Data Factory Information
output "data_factory_name" {
  description = "Name of the Azure Data Factory"
  value       = azurerm_data_factory.etl_orchestration.name
}

output "data_factory_id" {
  description = "Resource ID of the Azure Data Factory"
  value       = azurerm_data_factory.etl_orchestration.id
}

output "data_factory_managed_identity_principal_id" {
  description = "Principal ID of the Data Factory managed identity"
  value       = azurerm_data_factory.etl_orchestration.identity[0].principal_id
}

output "data_factory_managed_identity_tenant_id" {
  description = "Tenant ID of the Data Factory managed identity"
  value       = azurerm_data_factory.etl_orchestration.identity[0].tenant_id
}

# Integration Runtime Information
output "self_hosted_integration_runtime_name" {
  description = "Name of the self-hosted integration runtime"
  value       = azurerm_data_factory_integration_runtime_self_hosted.on_premises.name
}

output "self_hosted_integration_runtime_key" {
  description = "Authentication key for the self-hosted integration runtime"
  value       = azurerm_data_factory_integration_runtime_self_hosted.on_premises.primary_authorization_key
  sensitive   = true
}

output "self_hosted_integration_runtime_key_secondary" {
  description = "Secondary authentication key for the self-hosted integration runtime"
  value       = azurerm_data_factory_integration_runtime_self_hosted.on_premises.secondary_authorization_key
  sensitive   = true
}

# MySQL Server Information
output "mysql_server_name" {
  description = "Name of the MySQL Flexible Server"
  value       = azurerm_mysql_flexible_server.etl_target.name
}

output "mysql_server_fqdn" {
  description = "Fully qualified domain name of the MySQL server"
  value       = azurerm_mysql_flexible_server.etl_target.fqdn
}

output "mysql_server_id" {
  description = "Resource ID of the MySQL Flexible Server"
  value       = azurerm_mysql_flexible_server.etl_target.id
}

output "mysql_database_name" {
  description = "Name of the target database"
  value       = azurerm_mysql_flexible_database.consolidated_data.name
}

output "mysql_connection_string" {
  description = "Connection string for the MySQL server (without password)"
  value       = "server=${azurerm_mysql_flexible_server.etl_target.fqdn};port=3306;database=${azurerm_mysql_flexible_database.consolidated_data.name};uid=${var.mysql_admin_username};sslmode=required"
}

# Key Vault Information
output "key_vault_name" {
  description = "Name of the Azure Key Vault"
  value       = azurerm_key_vault.etl_secrets.name
}

output "key_vault_id" {
  description = "Resource ID of the Azure Key Vault"
  value       = azurerm_key_vault.etl_secrets.id
}

output "key_vault_uri" {
  description = "URI of the Azure Key Vault"
  value       = azurerm_key_vault.etl_secrets.vault_uri
}

# Log Analytics Information
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.etl_monitoring.name
}

output "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.etl_monitoring.id
}

output "log_analytics_workspace_primary_shared_key" {
  description = "Primary shared key for the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.etl_monitoring.primary_shared_key
  sensitive   = true
}

# Application Insights Information
output "application_insights_name" {
  description = "Name of the Application Insights instance"
  value       = azurerm_application_insights.etl_insights.name
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key for Application Insights"
  value       = azurerm_application_insights.etl_insights.instrumentation_key
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Connection string for Application Insights"
  value       = azurerm_application_insights.etl_insights.connection_string
  sensitive   = true
}

# Pipeline Information
output "etl_pipeline_name" {
  description = "Name of the ETL pipeline"
  value       = azurerm_data_factory_pipeline.multi_database_etl.name
}

output "etl_trigger_name" {
  description = "Name of the ETL trigger"
  value       = azurerm_data_factory_trigger_schedule.daily_etl.name
}

# Linked Services Information
output "mysql_source_linked_service_name" {
  description = "Name of the MySQL source linked service"
  value       = azurerm_data_factory_linked_service_mysql.source_mysql.name
}

output "mysql_target_linked_service_name" {
  description = "Name of the MySQL target linked service"
  value       = azurerm_data_factory_linked_service_mysql.target_mysql.name
}

output "key_vault_linked_service_name" {
  description = "Name of the Key Vault linked service"
  value       = azurerm_data_factory_linked_service_key_vault.etl_keyvault.name
}

# Dataset Information
output "source_dataset_name" {
  description = "Name of the source dataset"
  value       = azurerm_data_factory_dataset_mysql.source_dataset.name
}

output "target_dataset_name" {
  description = "Name of the target dataset"
  value       = azurerm_data_factory_dataset_mysql.target_dataset.name
}

# Monitoring Information
output "pipeline_failure_alert_name" {
  description = "Name of the pipeline failure alert (if enabled)"
  value       = var.enable_pipeline_failure_alert ? azurerm_monitor_metric_alert.pipeline_failure_alert[0].name : null
}

output "action_group_name" {
  description = "Name of the action group for alerts (if email addresses provided)"
  value       = length(var.alert_email_addresses) > 0 ? azurerm_monitor_action_group.etl_alerts[0].name : null
}

# Security Information
output "mysql_admin_username" {
  description = "MySQL administrator username"
  value       = var.mysql_admin_username
}

# Network Information
output "mysql_firewall_rules" {
  description = "List of MySQL firewall rules"
  value = concat(
    [azurerm_mysql_flexible_server_firewall_rule.allow_azure_services.name],
    [for rule in azurerm_mysql_flexible_server_firewall_rule.allowed_ips : rule.name]
  )
}

# Deployment Information
output "deployment_summary" {
  description = "Summary of deployed resources"
  value = {
    resource_group          = azurerm_resource_group.etl_orchestration.name
    data_factory           = azurerm_data_factory.etl_orchestration.name
    mysql_server           = azurerm_mysql_flexible_server.etl_target.name
    mysql_database         = azurerm_mysql_flexible_database.consolidated_data.name
    key_vault             = azurerm_key_vault.etl_secrets.name
    log_analytics         = azurerm_log_analytics_workspace.etl_monitoring.name
    application_insights  = azurerm_application_insights.etl_insights.name
    integration_runtime   = azurerm_data_factory_integration_runtime_self_hosted.on_premises.name
    pipeline              = azurerm_data_factory_pipeline.multi_database_etl.name
    trigger               = azurerm_data_factory_trigger_schedule.daily_etl.name
    high_availability     = var.mysql_high_availability_enabled
    monitoring_enabled    = var.enable_diagnostic_settings
    ssl_enforcement       = var.enable_ssl_enforcement
  }
}

# Next Steps Instructions
output "next_steps" {
  description = "Instructions for completing the setup"
  value = <<-EOT
    
    DEPLOYMENT COMPLETE! Next steps:
    
    1. Install Self-Hosted Integration Runtime:
       - Download from: https://www.microsoft.com/download/details.aspx?id=39717
       - Use authentication key: ${azurerm_data_factory_integration_runtime_self_hosted.on_premises.primary_authorization_key}
    
    2. Configure Source Database Access:
       - Update Key Vault secret 'mysql-source-connection-string' with actual connection details
       - Ensure network connectivity from on-premises to Azure
    
    3. Verify MySQL Target Database:
       - Connection: ${azurerm_mysql_flexible_server.etl_target.fqdn}:3306
       - Database: ${azurerm_mysql_flexible_database.consolidated_data.name}
       - Username: ${var.mysql_admin_username}
    
    4. Test Data Factory Pipeline:
       - Navigate to Azure Data Factory Studio
       - Run pipeline '${azurerm_data_factory_pipeline.multi_database_etl.name}' manually
       - Verify data transfer from source to target
    
    5. Monitor and Troubleshoot:
       - Check logs in Log Analytics: ${azurerm_log_analytics_workspace.etl_monitoring.name}
       - Monitor Application Insights: ${azurerm_application_insights.etl_insights.name}
       - Review pipeline runs in Data Factory Studio
    
    6. Security Considerations:
       - Restrict MySQL firewall rules to specific IP ranges
       - Review and update Key Vault access policies
       - Configure network security groups as needed
    
    7. Production Readiness:
       - Implement proper backup strategies
       - Configure disaster recovery
       - Set up additional monitoring and alerting
       - Review and adjust resource sizing based on workload
    
    For more information, visit: https://docs.microsoft.com/azure/data-factory/
    
  EOT
}