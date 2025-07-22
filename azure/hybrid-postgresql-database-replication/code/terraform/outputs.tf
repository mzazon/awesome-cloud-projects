# Outputs for Azure Hybrid PostgreSQL Database Replication Infrastructure
# This file defines the outputs that will be displayed after successful deployment

# Resource Group Information
output "resource_group_name" {
  description = "Name of the Azure resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_id" {
  description = "ID of the Azure resource group"
  value       = azurerm_resource_group.main.id
}

output "location" {
  description = "Azure region where resources are deployed"
  value       = azurerm_resource_group.main.location
}

# Azure Database for PostgreSQL Information
output "azure_postgresql_server_name" {
  description = "Name of the Azure Database for PostgreSQL Flexible Server"
  value       = azurerm_postgresql_flexible_server.main.name
}

output "azure_postgresql_server_fqdn" {
  description = "Fully qualified domain name of the Azure PostgreSQL server"
  value       = azurerm_postgresql_flexible_server.main.fqdn
}

output "azure_postgresql_server_id" {
  description = "ID of the Azure PostgreSQL server"
  value       = azurerm_postgresql_flexible_server.main.id
}

output "azure_postgresql_admin_username" {
  description = "Administrator username for Azure PostgreSQL server"
  value       = azurerm_postgresql_flexible_server.main.administrator_login
}

output "azure_postgresql_version" {
  description = "PostgreSQL version"
  value       = azurerm_postgresql_flexible_server.main.version
}

output "azure_postgresql_sku" {
  description = "SKU of the Azure PostgreSQL server"
  value       = azurerm_postgresql_flexible_server.main.sku_name
}

output "azure_postgresql_storage_mb" {
  description = "Storage size in MB for Azure PostgreSQL server"
  value       = azurerm_postgresql_flexible_server.main.storage_mb
}

output "azure_postgresql_backup_retention_days" {
  description = "Backup retention period in days"
  value       = azurerm_postgresql_flexible_server.main.backup_retention_days
}

output "azure_postgresql_connection_string" {
  description = "Connection string for Azure PostgreSQL server"
  value       = "Host=${azurerm_postgresql_flexible_server.main.fqdn};Database=postgres;Username=${azurerm_postgresql_flexible_server.main.administrator_login};Port=5432;SSL Mode=Require"
  sensitive   = false
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

output "data_factory_identity_principal_id" {
  description = "Principal ID of the Data Factory managed identity"
  value       = azurerm_data_factory.main.identity[0].principal_id
}

output "data_factory_identity_tenant_id" {
  description = "Tenant ID of the Data Factory managed identity"
  value       = azurerm_data_factory.main.identity[0].tenant_id
}

output "data_factory_pipeline_name" {
  description = "Name of the replication pipeline"
  value       = azurerm_data_factory_pipeline.replication.name
}

output "data_factory_trigger_name" {
  description = "Name of the scheduled replication trigger"
  value       = azurerm_data_factory_trigger_schedule.replication.name
}

# Event Grid Information
output "event_grid_topic_name" {
  description = "Name of the Event Grid topic"
  value       = azurerm_eventgrid_topic.main.name
}

output "event_grid_topic_id" {
  description = "ID of the Event Grid topic"
  value       = azurerm_eventgrid_topic.main.id
}

output "event_grid_endpoint" {
  description = "Endpoint URL for the Event Grid topic"
  value       = azurerm_eventgrid_topic.main.endpoint
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

# Log Analytics Workspace Information
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = var.enable_monitoring ? azurerm_log_analytics_workspace.main[0].name : null
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace"
  value       = var.enable_monitoring ? azurerm_log_analytics_workspace.main[0].id : null
}

output "log_analytics_workspace_workspace_id" {
  description = "Workspace ID of the Log Analytics workspace"
  value       = var.enable_monitoring ? azurerm_log_analytics_workspace.main[0].workspace_id : null
}

output "log_analytics_workspace_primary_shared_key" {
  description = "Primary shared key of the Log Analytics workspace"
  value       = var.enable_monitoring ? azurerm_log_analytics_workspace.main[0].primary_shared_key : null
  sensitive   = true
}

# Azure Arc Service Principal Information (if created)
output "arc_service_principal_application_id" {
  description = "Application ID of the Arc Data Controller service principal"
  value       = var.create_service_principal ? azuread_application.arc_data_controller[0].client_id : null
}

output "arc_service_principal_object_id" {
  description = "Object ID of the Arc Data Controller service principal"
  value       = var.create_service_principal ? azuread_service_principal.arc_data_controller[0].id : null
}

output "arc_service_principal_display_name" {
  description = "Display name of the Arc Data Controller service principal"
  value       = var.create_service_principal ? azuread_application.arc_data_controller[0].display_name : null
}

# Kubernetes Configuration
output "kubernetes_namespace" {
  description = "Kubernetes namespace for Arc data services"
  value       = kubernetes_namespace.arc_data.metadata[0].name
}

output "kubernetes_namespace_labels" {
  description = "Labels applied to the Kubernetes namespace"
  value       = kubernetes_namespace.arc_data.metadata[0].labels
}

# Arc PostgreSQL Configuration
output "arc_postgres_name" {
  description = "Name of the Arc-enabled PostgreSQL instance"
  value       = var.arc_postgres_name
}

output "arc_postgres_version" {
  description = "Version of the Arc-enabled PostgreSQL instance"
  value       = var.postgresql_version
}

output "arc_postgres_replicas" {
  description = "Number of replicas for Arc PostgreSQL"
  value       = var.arc_postgres_replicas
}

output "arc_postgres_cpu_requests" {
  description = "CPU requests for Arc PostgreSQL"
  value       = var.arc_postgres_cpu_requests
}

output "arc_postgres_cpu_limits" {
  description = "CPU limits for Arc PostgreSQL"
  value       = var.arc_postgres_cpu_limits
}

output "arc_postgres_memory_requests" {
  description = "Memory requests for Arc PostgreSQL"
  value       = var.arc_postgres_memory_requests
}

output "arc_postgres_memory_limits" {
  description = "Memory limits for Arc PostgreSQL"
  value       = var.arc_postgres_memory_limits
}

output "arc_postgres_storage_size" {
  description = "Storage size for Arc PostgreSQL data"
  value       = var.arc_postgres_storage_size
}

output "arc_postgres_logs_storage_size" {
  description = "Storage size for Arc PostgreSQL logs"
  value       = var.arc_postgres_logs_storage_size
}

# Monitoring and Alerting Information
output "monitoring_enabled" {
  description = "Whether monitoring is enabled"
  value       = var.enable_monitoring
}

output "diagnostic_logs_enabled" {
  description = "Whether diagnostic logs are enabled"
  value       = var.enable_diagnostic_logs
}

output "metrics_enabled" {
  description = "Whether metrics collection is enabled"
  value       = var.enable_metrics
}

output "replication_lag_alert_name" {
  description = "Name of the replication lag alert"
  value       = var.enable_monitoring ? azurerm_monitor_metric_alert.replication_lag[0].name : null
}

output "action_group_name" {
  description = "Name of the Azure Monitor action group"
  value       = var.enable_monitoring ? azurerm_monitor_action_group.main[0].name : null
}

# Network Configuration
output "allowed_ip_ranges" {
  description = "List of allowed IP ranges for PostgreSQL access"
  value       = var.allowed_ip_ranges
}

output "ssl_enforcement_enabled" {
  description = "Whether SSL enforcement is enabled"
  value       = var.enable_ssl
}

output "firewall_rules_enabled" {
  description = "Whether firewall rules are enabled"
  value       = var.enable_firewall_rules
}

# Deployment Information
output "deployment_timestamp" {
  description = "Timestamp of the deployment"
  value       = timestamp()
}

output "terraform_version" {
  description = "Terraform version used for deployment"
  value       = "~> 1.9.0"
}

output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_string.suffix.result
}

# Connection Commands and Instructions
output "azure_postgresql_connection_command" {
  description = "Command to connect to Azure PostgreSQL server using psql"
  value       = "PGPASSWORD='${var.postgresql_admin_password}' psql -h ${azurerm_postgresql_flexible_server.main.fqdn} -U ${azurerm_postgresql_flexible_server.main.administrator_login} -d postgres"
  sensitive   = true
}

output "arc_data_controller_deployment_command" {
  description = "Command to deploy Arc Data Controller (requires Azure CLI and kubectl)"
  value = var.create_service_principal ? join(" ", [
    "az arcdata dc create",
    "--name ${var.arc_data_controller_name}",
    "--resource-group ${azurerm_resource_group.main.name}",
    "--location ${azurerm_resource_group.main.location}",
    "--connectivity-mode ${var.arc_connectivity_mode}",
    "--namespace ${kubernetes_namespace.arc_data.metadata[0].name}",
    "--infrastructure onpremises",
    "--k8s-namespace ${kubernetes_namespace.arc_data.metadata[0].name}",
    "--use-k8s"
  ]) : "Service principal not created - manual configuration required"
}

output "arc_postgres_deployment_command" {
  description = "Command to deploy Arc-enabled PostgreSQL instance"
  value       = "kubectl apply -f postgres-config.yaml -n ${kubernetes_namespace.arc_data.metadata[0].name}"
}

# Important Notes and Next Steps
output "important_notes" {
  description = "Important notes about the deployment"
  value = {
    note1 = "Azure Arc Data Controller must be deployed manually using the Azure CLI and kubectl"
    note2 = "Arc-enabled PostgreSQL instance must be deployed using the provided Kubernetes configuration"
    note3 = "Data Factory pipeline requires manual configuration of the Arc PostgreSQL linked service"
    note4 = "Event Grid integration requires custom implementation for change data capture"
    note5 = "Monitor replication lag using Azure Monitor alerts and Log Analytics queries"
    note6 = "Ensure proper network connectivity between Kubernetes cluster and Azure services"
  }
}

output "next_steps" {
  description = "Next steps after Terraform deployment"
  value = [
    "1. Deploy Azure Arc Data Controller using the provided command",
    "2. Create Arc-enabled PostgreSQL instance using the generated Kubernetes configuration",
    "3. Configure Data Factory linked service for Arc PostgreSQL connection",
    "4. Set up Event Grid event subscription for change notifications",
    "5. Test end-to-end replication by inserting data in Arc PostgreSQL",
    "6. Monitor replication performance using Azure Monitor",
    "7. Configure backup and disaster recovery procedures",
    "8. Review and adjust security settings as needed"
  ]
}

# Security Information
output "security_considerations" {
  description = "Security considerations for the deployed infrastructure"
  value = {
    key_vault_access = "Key Vault stores sensitive credentials - ensure proper access policies"
    ssl_enforcement  = "SSL is ${var.enable_ssl ? "enabled" : "disabled"} for PostgreSQL connections"
    firewall_rules   = "Firewall rules are ${var.enable_firewall_rules ? "enabled" : "disabled"} - review IP ranges"
    service_principal = var.create_service_principal ? "Service principal created for Arc Data Controller" : "Manual service principal configuration required"
    managed_identity = "Data Factory uses system-assigned managed identity for secure access"
    network_security = "Review network security groups and virtual network configuration"
  }
}

# Cost Information
output "cost_optimization_tips" {
  description = "Tips for optimizing costs"
  value = [
    "Use Azure Hybrid Benefit for PostgreSQL if you have existing licenses",
    "Consider using reserved instances for predictable workloads",
    "Monitor Data Factory pipeline executions and optimize frequency",
    "Use Log Analytics workspace data retention policies to control costs",
    "Implement auto-scaling for Kubernetes cluster resources",
    "Review and optimize storage configurations for Arc PostgreSQL",
    "Use Azure Cost Management to track spending across all components"
  ]
}