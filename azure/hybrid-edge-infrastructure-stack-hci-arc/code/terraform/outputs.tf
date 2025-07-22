# Output values for Azure Stack HCI and Azure Arc edge computing infrastructure
# These outputs provide important information for deployment verification and integration

# Resource Group Information
output "resource_group_id" {
  description = "The resource ID of the edge infrastructure resource group"
  value       = azurerm_resource_group.edge_infrastructure.id
}

output "resource_group_name" {
  description = "The name of the edge infrastructure resource group"
  value       = azurerm_resource_group.edge_infrastructure.name
}

output "resource_group_location" {
  description = "The Azure region where the resource group is deployed"
  value       = azurerm_resource_group.edge_infrastructure.location
}

# Azure Stack HCI Cluster Information
output "hci_cluster_id" {
  description = "The resource ID of the Azure Stack HCI cluster"
  value       = azurerm_stack_hci_cluster.edge_cluster.id
}

output "hci_cluster_name" {
  description = "The name of the Azure Stack HCI cluster"
  value       = azurerm_stack_hci_cluster.edge_cluster.name
}

output "hci_cluster_location" {
  description = "The location of the Azure Stack HCI cluster"
  value       = azurerm_stack_hci_cluster.edge_cluster.location
}

# Azure Arc Service Principal Information
output "arc_service_principal_id" {
  description = "The Application ID of the Azure Arc service principal for onboarding"
  value       = azuread_service_principal.arc_sp.application_id
  sensitive   = true
}

output "arc_service_principal_object_id" {
  description = "The Object ID of the Azure Arc service principal"
  value       = azuread_service_principal.arc_sp.object_id
  sensitive   = true
}

output "arc_service_principal_secret" {
  description = "The password for the Azure Arc service principal"
  value       = azuread_service_principal_password.arc_sp_password.value
  sensitive   = true
}

output "arc_tenant_id" {
  description = "The Azure tenant ID for Arc registration"
  value       = data.azuread_client_config.current.tenant_id
}

# Monitoring and Logging Information
output "log_analytics_workspace_id" {
  description = "The customer ID (workspace ID) of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.edge_monitoring.workspace_id
}

output "log_analytics_workspace_resource_id" {
  description = "The resource ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.edge_monitoring.id
}

output "log_analytics_workspace_name" {
  description = "The name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.edge_monitoring.name
}

output "log_analytics_primary_shared_key" {
  description = "The primary shared key for the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.edge_monitoring.primary_shared_key
  sensitive   = true
}

output "application_insights_instrumentation_key" {
  description = "The instrumentation key for Application Insights (if enabled)"
  value       = var.enable_application_insights ? azurerm_application_insights.edge_monitoring[0].instrumentation_key : null
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "The connection string for Application Insights (if enabled)"
  value       = var.enable_application_insights ? azurerm_application_insights.edge_monitoring[0].connection_string : null
  sensitive   = true
}

# Storage Account Information
output "storage_account_id" {
  description = "The resource ID of the edge storage account"
  value       = azurerm_storage_account.edge_storage.id
}

output "storage_account_name" {
  description = "The name of the edge storage account"
  value       = azurerm_storage_account.edge_storage.name
}

output "storage_account_primary_connection_string" {
  description = "The primary connection string for the storage account"
  value       = azurerm_storage_account.edge_storage.primary_connection_string
  sensitive   = true
}

output "storage_account_primary_access_key" {
  description = "The primary access key for the storage account"
  value       = azurerm_storage_account.edge_storage.primary_access_key
  sensitive   = true
}

output "storage_container_name" {
  description = "The name of the storage container for edge synchronization"
  value       = azurerm_storage_container.edge_sync.name
}

output "storage_file_share_name" {
  description = "The name of the file share for edge synchronization"
  value       = azurerm_storage_share.edge_file_sync.name
}

output "storage_file_share_url" {
  description = "The URL of the file share for edge synchronization"
  value       = azurerm_storage_share.edge_file_sync.url
}

# Key Vault Information (if enabled)
output "key_vault_id" {
  description = "The resource ID of the Key Vault (if enabled)"
  value       = var.enable_key_vault ? azurerm_key_vault.edge_secrets[0].id : null
}

output "key_vault_name" {
  description = "The name of the Key Vault (if enabled)"
  value       = var.enable_key_vault ? azurerm_key_vault.edge_secrets[0].name : null
}

output "key_vault_uri" {
  description = "The URI of the Key Vault (if enabled)"
  value       = var.enable_key_vault ? azurerm_key_vault.edge_secrets[0].vault_uri : null
}

# Network Information
output "virtual_network_id" {
  description = "The resource ID of the virtual network"
  value       = azurerm_virtual_network.edge_network.id
}

output "virtual_network_name" {
  description = "The name of the virtual network"
  value       = azurerm_virtual_network.edge_network.name
}

output "subnet_id" {
  description = "The resource ID of the edge subnet"
  value       = azurerm_subnet.edge_subnet.id
}

output "subnet_name" {
  description = "The name of the edge subnet"
  value       = azurerm_subnet.edge_subnet.name
}

output "network_security_group_id" {
  description = "The resource ID of the network security group"
  value       = azurerm_network_security_group.edge_nsg.id
}

# Data Collection and Monitoring
output "data_collection_rule_id" {
  description = "The resource ID of the data collection rule for HCI monitoring"
  value       = azurerm_monitor_data_collection_rule.hci_monitoring.id
}

output "data_collection_rule_name" {
  description = "The name of the data collection rule for HCI monitoring"
  value       = azurerm_monitor_data_collection_rule.hci_monitoring.name
}

# Storage Sync Information
output "storage_sync_service_id" {
  description = "The resource ID of the storage sync service"
  value       = azurerm_storage_sync.edge_sync_service.id
}

output "storage_sync_service_name" {
  description = "The name of the storage sync service"
  value       = azurerm_storage_sync.edge_sync_service.name
}

output "storage_sync_group_id" {
  description = "The resource ID of the storage sync group"
  value       = azurerm_storage_sync_group.edge_sync_group.id
}

# Backup Information (if enabled)
output "recovery_services_vault_id" {
  description = "The resource ID of the Recovery Services vault (if enabled)"
  value       = var.enable_backup ? azurerm_recovery_services_vault.edge_backup[0].id : null
}

output "recovery_services_vault_name" {
  description = "The name of the Recovery Services vault (if enabled)"
  value       = var.enable_backup ? azurerm_recovery_services_vault.edge_backup[0].name : null
}

output "backup_policy_id" {
  description = "The resource ID of the backup policy (if enabled)"
  value       = var.enable_backup ? azurerm_backup_policy_vm.hci_backup_policy[0].id : null
}

# Policy Information (if enabled)
output "hci_security_policy_id" {
  description = "The resource ID of the HCI security policy (if enabled)"
  value       = var.enable_azure_policy ? azurerm_policy_definition.hci_security_baseline[0].id : null
}

output "hci_security_assignment_id" {
  description = "The resource ID of the HCI security policy assignment (if enabled)"
  value       = var.enable_azure_policy ? azurerm_resource_group_policy_assignment.hci_security[0].id : null
}

# Cost Management Information (if enabled)
output "budget_id" {
  description = "The resource ID of the cost management budget (if enabled)"
  value       = var.enable_cost_management ? azurerm_consumption_budget_resource_group.edge_budget[0].id : null
}

# Alert Information
output "action_group_id" {
  description = "The resource ID of the monitoring action group"
  value       = azurerm_monitor_action_group.edge_alerts.id
}

output "hci_health_alert_id" {
  description = "The resource ID of the HCI cluster health alert"
  value       = azurerm_monitor_metric_alert.hci_health.id
}

# Configuration Commands for Edge Deployment
output "arc_onboarding_command" {
  description = "Command to onboard servers to Azure Arc (use with appropriate server connection)"
  value = format(
    "azcmagent connect --service-principal-id %s --service-principal-secret %s --resource-group %s --tenant-id %s --location %s --subscription-id %s --cloud AzureCloud",
    azuread_service_principal.arc_sp.application_id,
    azuread_service_principal_password.arc_sp_password.value,
    azurerm_resource_group.edge_infrastructure.name,
    data.azuread_client_config.current.tenant_id,
    azurerm_resource_group.edge_infrastructure.location,
    data.azurerm_client_config.current.subscription_id
  )
  sensitive = true
}

output "hci_registration_info" {
  description = "Information needed for HCI cluster registration"
  value = {
    cluster_name    = azurerm_stack_hci_cluster.edge_cluster.name
    resource_group  = azurerm_resource_group.edge_infrastructure.name
    subscription_id = data.azurerm_client_config.current.subscription_id
    tenant_id       = data.azuread_client_config.current.tenant_id
    location        = azurerm_resource_group.edge_infrastructure.location
  }
}

# Random suffix used for resource naming
output "resource_suffix" {
  description = "The random suffix used for resource naming in this deployment"
  value       = local.resource_suffix
}

# Common tags applied to resources
output "common_tags" {
  description = "The common tags applied to all resources in this deployment"
  value       = local.common_tags
}

# Summary information
output "deployment_summary" {
  description = "Summary of the deployed edge computing infrastructure"
  value = {
    resource_group           = azurerm_resource_group.edge_infrastructure.name
    location                = azurerm_resource_group.edge_infrastructure.location
    hci_cluster             = azurerm_stack_hci_cluster.edge_cluster.name
    log_analytics_workspace = azurerm_log_analytics_workspace.edge_monitoring.name
    storage_account         = azurerm_storage_account.edge_storage.name
    key_vault_enabled       = var.enable_key_vault
    backup_enabled          = var.enable_backup
    policy_enabled          = var.enable_azure_policy
    cost_management_enabled = var.enable_cost_management
    deployment_timestamp    = timestamp()
  }
}