# ===================================================================================
# Terraform Outputs: Intelligent Database Migration Orchestration
# Description: Output values for Azure Data Factory, Database Migration Service,
#              and supporting infrastructure for post-deployment configuration
# Version: 1.0
# ===================================================================================

# ===================================================================================
# RESOURCE GROUP OUTPUTS
# ===================================================================================

output "resource_group_name" {
  description = "Name of the resource group containing all migration resources"
  value       = data.azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Azure region where all resources are deployed"
  value       = var.location
}

# ===================================================================================
# AZURE DATA FACTORY OUTPUTS
# ===================================================================================

output "data_factory_name" {
  description = "Name of the Azure Data Factory instance"
  value       = azurerm_data_factory.main.name
}

output "data_factory_id" {
  description = "Resource ID of the Azure Data Factory instance"
  value       = azurerm_data_factory.main.id
}

output "data_factory_principal_id" {
  description = "Principal ID of the Data Factory managed identity for RBAC assignments"
  value       = azurerm_data_factory.main.identity[0].principal_id
}

output "data_factory_studio_url" {
  description = "URL to access the Data Factory Studio for workflow management"
  value       = "https://adf.azure.com/en/home?factory=%2Fsubscriptions%2F${data.azurerm_client_config.current.subscription_id}%2FresourceGroups%2F${data.azurerm_resource_group.main.name}%2Fproviders%2FMicrosoft.DataFactory%2Ffactories%2F${azurerm_data_factory.main.name}"
}

output "integration_runtime_name" {
  description = "Name of the self-hosted integration runtime for on-premises connectivity"
  value       = azurerm_data_factory_integration_runtime_self_hosted.main.name
}

output "integration_runtime_auth_key_1" {
  description = "First authentication key for setting up the self-hosted integration runtime"
  value       = azurerm_data_factory_integration_runtime_self_hosted.main.auth_key_1
  sensitive   = true
}

output "integration_runtime_auth_key_2" {
  description = "Second authentication key for setting up the self-hosted integration runtime"
  value       = azurerm_data_factory_integration_runtime_self_hosted.main.auth_key_2
  sensitive   = true
}

# ===================================================================================
# DATABASE MIGRATION SERVICE OUTPUTS
# ===================================================================================

output "database_migration_service_name" {
  description = "Name of the Database Migration Service instance"
  value       = azurerm_database_migration_service.main.name
}

output "database_migration_service_id" {
  description = "Resource ID of the Database Migration Service instance"
  value       = azurerm_database_migration_service.main.id
}

output "database_migration_service_sku" {
  description = "SKU configuration of the Database Migration Service"
  value       = azurerm_database_migration_service.main.sku_name
}

# ===================================================================================
# STORAGE ACCOUNT OUTPUTS
# ===================================================================================

output "storage_account_name" {
  description = "Name of the storage account for Airflow DAGs and migration artifacts"
  value       = azurerm_storage_account.main.name
}

output "storage_account_id" {
  description = "Resource ID of the storage account"
  value       = azurerm_storage_account.main.id
}

output "storage_account_primary_endpoint" {
  description = "Primary blob endpoint URL for the storage account"
  value       = azurerm_storage_account.main.primary_blob_endpoint
}

output "storage_account_primary_access_key" {
  description = "Primary access key for the storage account"
  value       = azurerm_storage_account.main.primary_access_key
  sensitive   = true
}

output "storage_account_connection_string" {
  description = "Connection string for the storage account"
  value       = azurerm_storage_account.main.primary_connection_string
  sensitive   = true
}

output "storage_container_names" {
  description = "List of storage container names created for the migration solution"
  value       = var.storage_container_names
}

# ===================================================================================
# MONITORING AND LOGGING OUTPUTS
# ===================================================================================

output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace for centralized logging"
  value       = azurerm_log_analytics_workspace.main.name
}

output "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.id
}

output "log_analytics_customer_id" {
  description = "Customer ID (workspace ID) for Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.workspace_id
}

output "log_analytics_primary_shared_key" {
  description = "Primary shared key for Log Analytics workspace authentication"
  value       = azurerm_log_analytics_workspace.main.primary_shared_key
  sensitive   = true
}

output "action_group_name" {
  description = "Name of the action group for alert notifications"
  value       = var.enable_monitoring ? azurerm_monitor_action_group.main[0].name : ""
}

output "action_group_id" {
  description = "Resource ID of the action group for alert notifications"
  value       = var.enable_monitoring ? azurerm_monitor_action_group.main[0].id : ""
}

output "application_insights_name" {
  description = "Name of the Application Insights instance for enhanced monitoring"
  value       = var.enable_monitoring ? azurerm_application_insights.main[0].name : ""
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key for Application Insights"
  value       = var.enable_monitoring ? azurerm_application_insights.main[0].instrumentation_key : ""
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Connection string for Application Insights"
  value       = var.enable_monitoring ? azurerm_application_insights.main[0].connection_string : ""
  sensitive   = true
}

# ===================================================================================
# NETWORKING OUTPUTS
# ===================================================================================

output "private_endpoint_enabled" {
  description = "Whether private endpoints are enabled for enhanced security"
  value       = var.enable_private_endpoints
}

output "storage_private_endpoint_id" {
  description = "Resource ID of the storage account private endpoint"
  value       = var.enable_private_endpoints ? azurerm_private_endpoint.storage_blob[0].id : ""
}

output "storage_private_endpoint_ip" {
  description = "Private IP address of the storage account private endpoint"
  value       = var.enable_private_endpoints ? azurerm_private_endpoint.storage_blob[0].private_service_connection[0].private_ip_address : ""
}

# ===================================================================================
# DEPLOYMENT CONFIGURATION OUTPUTS
# ===================================================================================

output "alert_rules_created" {
  description = "List of metric alert rules created for monitoring"
  value       = var.enable_monitoring ? [for alert in var.alert_rules : alert.name] : []
}

output "diagnostic_settings_enabled" {
  description = "Whether diagnostic settings are enabled for resources"
  value       = var.enable_diagnostic_settings
}

output "rbac_assignments_enabled" {
  description = "Whether RBAC role assignments are enabled"
  value       = var.enable_rbac_assignments
}

# ===================================================================================
# NEXT STEPS AND CONFIGURATION COMMANDS
# ===================================================================================

output "integration_runtime_setup_command" {
  description = "Command to install and configure the self-hosted integration runtime"
  value       = "Download IR from: https://www.microsoft.com/en-us/download/details.aspx?id=39717 and use auth key from integration_runtime_auth_key_1 output"
}

output "airflow_dag_upload_command" {
  description = "Azure CLI command template for uploading Airflow DAGs to storage"
  value       = "az storage blob upload --container-name airflow-dags --file <dag-file-path> --name <dag-name> --account-name ${azurerm_storage_account.main.name} --account-key <use-storage-account-primary-access-key>"
}

output "migration_project_creation_guide" {
  description = "Guide for creating migration projects in Database Migration Service"
  value       = "Use Azure portal or Azure CLI to create migration projects: az dms project create --service-name ${azurerm_database_migration_service.main.name} --resource-group ${data.azurerm_resource_group.main.name} --project-name <project-name> --source-platform SQL --target-platform AzureSqlDatabase"
}

output "monitoring_dashboard_url" {
  description = "URL to access Azure Monitor dashboards for migration monitoring"
  value       = "https://portal.azure.com/#@/dashboard/arm/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${data.azurerm_resource_group.main.name}/providers/Microsoft.Portal/dashboards/migration-monitoring"
}

output "next_steps" {
  description = "Next steps for completing the migration orchestration setup"
  value = [
    "1. Install Self-hosted Integration Runtime on on-premises server using the authentication key",
    "2. Configure linked services for your on-premises SQL Server instances in Data Factory Studio",
    "3. Set up Workflow Orchestration Manager environment in Data Factory Studio",
    "4. Upload Airflow DAGs to the 'airflow-dags' storage container using the provided command",
    "5. Configure database connection strings and migration parameters in Data Factory",
    "6. Test connectivity between on-premises databases and Azure services",
    "7. Create migration projects in Database Migration Service for each database",
    "8. Configure Azure Monitor dashboards for real-time migration monitoring",
    "9. Set up additional alert rules based on specific migration requirements",
    "10. Run end-to-end testing of the migration orchestration workflow"
  ]
}

# ===================================================================================
# COST OPTIMIZATION OUTPUTS
# ===================================================================================

output "estimated_monthly_cost_usd" {
  description = "Estimated monthly cost in USD for the deployed resources (approximation)"
  value = {
    data_factory        = "~$50-100"
    database_migration  = "~$100-200"
    storage_account     = "~$10-30"
    log_analytics      = "~$20-50"
    monitoring         = "~$10-20"
    total_estimate     = "~$190-400"
    note               = "Costs vary based on usage, data volume, and region. Use Azure Cost Calculator for precise estimates."
  }
}

output "cost_optimization_tips" {
  description = "Tips for optimizing costs of the migration infrastructure"
  value = [
    "Use Azure Cost Management to monitor and optimize resource usage",
    "Schedule Data Factory pipelines to run during off-peak hours",
    "Implement lifecycle policies for storage accounts to move old data to cooler tiers",
    "Set up budget alerts to monitor spending",
    "Consider using Azure Reserved Instances for long-term workloads",
    "Clean up unused migration resources after completion",
    "Use Azure Advisor recommendations for cost optimization"
  ]
}

# ===================================================================================
# SECURITY AND COMPLIANCE OUTPUTS
# ===================================================================================

output "security_recommendations" {
  description = "Security recommendations for the migration infrastructure"
  value = [
    "Enable private endpoints for production workloads",
    "Configure Azure Key Vault for storing sensitive connection strings",
    "Implement network security groups to restrict access",
    "Enable Azure Security Center for threat detection",
    "Use Azure AD authentication where possible",
    "Regularly rotate access keys and connection strings",
    "Enable audit logging for all database operations",
    "Implement data encryption at rest and in transit"
  ]
}

output "compliance_features" {
  description = "Compliance and governance features enabled in the deployment"
  value = {
    data_encryption     = "TLS 1.2 minimum, storage encryption enabled"
    access_control      = "RBAC assignments for service principals"
    monitoring         = "Comprehensive logging and alerting enabled"
    backup_retention   = "Storage container delete retention configured"
    audit_trail        = "Azure Activity Log and diagnostic settings enabled"
    network_security   = "Private endpoints available for enhanced security"
  }
}