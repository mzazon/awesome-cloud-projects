# Resource Group outputs
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_id" {
  description = "ID of the created resource group"
  value       = azurerm_resource_group.main.id
}

output "location" {
  description = "Azure region where resources are deployed"
  value       = azurerm_resource_group.main.location
}

# Random suffix for reference
output "random_suffix" {
  description = "Random suffix used for resource names"
  value       = random_string.suffix.result
}

# Kubernetes cluster outputs
output "kubernetes_cluster_name" {
  description = "Name of the Kubernetes cluster"
  value       = data.azurerm_kubernetes_cluster.main.name
}

output "kubernetes_cluster_id" {
  description = "ID of the Kubernetes cluster"
  value       = data.azurerm_kubernetes_cluster.main.id
}

output "kubernetes_cluster_resource_group" {
  description = "Resource group of the Kubernetes cluster"
  value       = data.azurerm_kubernetes_cluster.main.resource_group_name
}

output "kubernetes_cluster_fqdn" {
  description = "FQDN of the Kubernetes cluster"
  value       = data.azurerm_kubernetes_cluster.main.fqdn
}

output "kubernetes_cluster_version" {
  description = "Version of the Kubernetes cluster"
  value       = data.azurerm_kubernetes_cluster.main.kubernetes_version
}

# Azure Arc Kubernetes outputs
output "arc_kubernetes_name" {
  description = "Name of the Arc-enabled Kubernetes cluster"
  value       = azapi_resource.arc_kubernetes.name
}

output "arc_kubernetes_id" {
  description = "ID of the Arc-enabled Kubernetes cluster"
  value       = azapi_resource.arc_kubernetes.id
}

# Log Analytics workspace outputs
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.name
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.id
}

output "log_analytics_workspace_customer_id" {
  description = "Customer ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.workspace_id
}

output "log_analytics_workspace_primary_shared_key" {
  description = "Primary shared key of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.primary_shared_key
  sensitive   = true
}

# Azure Arc Data Controller outputs
output "arc_data_controller_name" {
  description = "Name of the Arc Data Controller"
  value       = azapi_resource.arc_data_controller.name
}

output "arc_data_controller_id" {
  description = "ID of the Arc Data Controller"
  value       = azapi_resource.arc_data_controller.id
}

output "arc_data_controller_namespace" {
  description = "Kubernetes namespace of the Arc Data Controller"
  value       = var.arc_data_controller_namespace
}

# SQL Managed Instance outputs
output "sql_managed_instance_name" {
  description = "Name of the SQL Managed Instance"
  value       = azapi_resource.sql_managed_instance.name
}

output "sql_managed_instance_id" {
  description = "ID of the SQL Managed Instance"
  value       = azapi_resource.sql_managed_instance.id
}

output "sql_managed_instance_admin_username" {
  description = "Admin username for the SQL Managed Instance"
  value       = var.sql_mi_admin_username
  sensitive   = true
}

output "sql_managed_instance_tier" {
  description = "Service tier of the SQL Managed Instance"
  value       = var.sql_mi_service_tier
}

output "sql_managed_instance_cores_request" {
  description = "CPU cores request for the SQL Managed Instance"
  value       = var.sql_mi_cores_request
}

output "sql_managed_instance_cores_limit" {
  description = "CPU cores limit for the SQL Managed Instance"
  value       = var.sql_mi_cores_limit
}

output "sql_managed_instance_memory_request" {
  description = "Memory request for the SQL Managed Instance"
  value       = var.sql_mi_memory_request
}

output "sql_managed_instance_memory_limit" {
  description = "Memory limit for the SQL Managed Instance"
  value       = var.sql_mi_memory_limit
}

# Monitoring outputs
output "monitoring_enabled" {
  description = "Whether monitoring is enabled"
  value       = var.enable_monitoring
}

output "alerting_enabled" {
  description = "Whether alerting is enabled"
  value       = var.enable_alerting
}

output "action_group_name" {
  description = "Name of the monitoring action group"
  value       = var.enable_alerting ? azurerm_monitor_action_group.main[0].name : null
}

output "action_group_id" {
  description = "ID of the monitoring action group"
  value       = var.enable_alerting ? azurerm_monitor_action_group.main[0].id : null
}

output "cpu_alert_name" {
  description = "Name of the CPU utilization alert"
  value       = var.enable_alerting ? azurerm_monitor_metric_alert.cpu_alert[0].name : null
}

output "storage_alert_name" {
  description = "Name of the storage utilization alert"
  value       = var.enable_alerting ? azurerm_monitor_metric_alert.storage_alert[0].name : null
}

output "workbook_name" {
  description = "Name of the monitoring workbook"
  value       = var.enable_monitoring ? azurerm_application_insights_workbook.main[0].name : null
}

output "workbook_id" {
  description = "ID of the monitoring workbook"
  value       = var.enable_monitoring ? azurerm_application_insights_workbook.main[0].id : null
}

# Security and governance outputs
output "azure_policy_enabled" {
  description = "Whether Azure Policy is enabled"
  value       = var.enable_azure_policy
}

output "rbac_enabled" {
  description = "Whether RBAC is enabled"
  value       = var.enable_rbac
}

output "policy_assignment_name" {
  description = "Name of the Azure Policy assignment"
  value       = var.enable_azure_policy ? azurerm_resource_policy_assignment.arc_security[0].name : null
}

output "policy_assignment_id" {
  description = "ID of the Azure Policy assignment"
  value       = var.enable_azure_policy ? azurerm_resource_policy_assignment.arc_security[0].id : null
}

# Connection information
output "connection_information" {
  description = "Information for connecting to the deployed resources"
  value = {
    arc_data_controller = {
      name      = azapi_resource.arc_data_controller.name
      namespace = var.arc_data_controller_namespace
    }
    sql_managed_instance = {
      name      = azapi_resource.sql_managed_instance.name
      namespace = var.arc_data_controller_namespace
      username  = var.sql_mi_admin_username
    }
    monitoring = {
      log_analytics_workspace = azurerm_log_analytics_workspace.main.name
      workbook_name           = var.enable_monitoring ? azurerm_application_insights_workbook.main[0].name : null
    }
  }
}

# Kubectl commands for verification
output "kubectl_commands" {
  description = "Useful kubectl commands for verification"
  value = {
    check_namespace = "kubectl get namespace ${var.arc_data_controller_namespace}"
    check_pods      = "kubectl get pods -n ${var.arc_data_controller_namespace}"
    check_services  = "kubectl get svc -n ${var.arc_data_controller_namespace}"
    check_secrets   = "kubectl get secrets -n ${var.arc_data_controller_namespace}"
  }
}

# Azure CLI commands for verification
output "azure_cli_commands" {
  description = "Useful Azure CLI commands for verification"
  value = {
    check_arc_data_controller = "az arcdata dc status show --resource-group ${azurerm_resource_group.main.name} --name ${azapi_resource.arc_data_controller.name}"
    check_sql_managed_instance = "az sql mi-arc show --resource-group ${azurerm_resource_group.main.name} --name ${azapi_resource.sql_managed_instance.name}"
    check_monitoring_data = "az monitor log-analytics query --workspace ${azurerm_log_analytics_workspace.main.workspace_id} --analytics-query \"AzureActivity | where ResourceProvider == 'Microsoft.AzureArcData' | take 10\""
  }
}

# Cost estimation information
output "cost_estimation" {
  description = "Cost estimation information"
  value = {
    log_analytics_workspace = "~$2-10/month depending on data ingestion"
    aks_cluster = var.create_aks_cluster ? "~$73/month for ${var.aks_node_count} ${var.aks_node_vm_size} nodes" : "Using existing cluster"
    sql_managed_instance = "~$10-50/month depending on usage and tier"
    monitoring_alerts = var.enable_alerting ? "~$0.10/alert evaluation" : "Not enabled"
    total_estimated = "~$85-133/month (excluding existing cluster costs)"
  }
}

# Tags applied to resources
output "tags" {
  description = "Tags applied to all resources"
  value       = var.tags
}