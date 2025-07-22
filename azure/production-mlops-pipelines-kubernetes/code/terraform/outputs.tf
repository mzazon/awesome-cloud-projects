# Outputs for MLOps Pipeline with AKS and Azure Machine Learning
# This file defines all outputs that will be displayed after deployment

# Resource Group Information
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.mlops.name
}

output "resource_group_location" {
  description = "Location of the created resource group"
  value       = azurerm_resource_group.mlops.location
}

output "resource_group_id" {
  description = "ID of the created resource group"
  value       = azurerm_resource_group.mlops.id
}

# Azure Machine Learning Workspace Information
output "ml_workspace_name" {
  description = "Name of the Azure Machine Learning workspace"
  value       = azurerm_machine_learning_workspace.mlops_workspace.name
}

output "ml_workspace_id" {
  description = "ID of the Azure Machine Learning workspace"
  value       = azurerm_machine_learning_workspace.mlops_workspace.id
}

output "ml_workspace_discovery_url" {
  description = "Discovery URL for the Azure Machine Learning workspace"
  value       = azurerm_machine_learning_workspace.mlops_workspace.discovery_url
}

# Azure Kubernetes Service Information
output "aks_cluster_name" {
  description = "Name of the AKS cluster"
  value       = azurerm_kubernetes_cluster.mlops_aks.name
}

output "aks_cluster_id" {
  description = "ID of the AKS cluster"
  value       = azurerm_kubernetes_cluster.mlops_aks.id
}

output "aks_cluster_fqdn" {
  description = "FQDN of the AKS cluster"
  value       = azurerm_kubernetes_cluster.mlops_aks.fqdn
}

output "aks_cluster_private_fqdn" {
  description = "Private FQDN of the AKS cluster"
  value       = azurerm_kubernetes_cluster.mlops_aks.private_fqdn
}

output "aks_cluster_kube_config" {
  description = "Kubernetes configuration for the AKS cluster"
  value       = azurerm_kubernetes_cluster.mlops_aks.kube_config_raw
  sensitive   = true
}

output "aks_cluster_node_resource_group" {
  description = "Resource group containing the AKS cluster nodes"
  value       = azurerm_kubernetes_cluster.mlops_aks.node_resource_group
}

output "aks_cluster_identity_principal_id" {
  description = "Principal ID of the AKS cluster managed identity"
  value       = azurerm_kubernetes_cluster.mlops_aks.identity[0].principal_id
}

output "aks_cluster_kubelet_identity_object_id" {
  description = "Object ID of the AKS cluster kubelet identity"
  value       = azurerm_kubernetes_cluster.mlops_aks.kubelet_identity[0].object_id
}

# Azure Container Registry Information
output "acr_name" {
  description = "Name of the Azure Container Registry"
  value       = azurerm_container_registry.mlops_acr.name
}

output "acr_id" {
  description = "ID of the Azure Container Registry"
  value       = azurerm_container_registry.mlops_acr.id
}

output "acr_login_server" {
  description = "Login server for the Azure Container Registry"
  value       = azurerm_container_registry.mlops_acr.login_server
}

output "acr_admin_username" {
  description = "Admin username for the Azure Container Registry"
  value       = azurerm_container_registry.mlops_acr.admin_username
  sensitive   = true
}

output "acr_admin_password" {
  description = "Admin password for the Azure Container Registry"
  value       = azurerm_container_registry.mlops_acr.admin_password
  sensitive   = true
}

# Storage Account Information
output "storage_account_name" {
  description = "Name of the ML workspace storage account"
  value       = azurerm_storage_account.mlops_storage.name
}

output "storage_account_id" {
  description = "ID of the ML workspace storage account"
  value       = azurerm_storage_account.mlops_storage.id
}

output "storage_account_primary_access_key" {
  description = "Primary access key for the storage account"
  value       = azurerm_storage_account.mlops_storage.primary_access_key
  sensitive   = true
}

output "storage_account_primary_blob_endpoint" {
  description = "Primary blob endpoint for the storage account"
  value       = azurerm_storage_account.mlops_storage.primary_blob_endpoint
}

output "diagnostic_storage_account_name" {
  description = "Name of the diagnostic storage account"
  value       = azurerm_storage_account.diagnostic_storage.name
}

# Key Vault Information
output "key_vault_name" {
  description = "Name of the Key Vault"
  value       = azurerm_key_vault.mlops_kv.name
}

output "key_vault_id" {
  description = "ID of the Key Vault"
  value       = azurerm_key_vault.mlops_kv.id
}

output "key_vault_uri" {
  description = "URI of the Key Vault"
  value       = azurerm_key_vault.mlops_kv.vault_uri
}

# Application Insights Information
output "application_insights_name" {
  description = "Name of the Application Insights instance"
  value       = azurerm_application_insights.mlops_insights.name
}

output "application_insights_id" {
  description = "ID of the Application Insights instance"
  value       = azurerm_application_insights.mlops_insights.id
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key for Application Insights"
  value       = azurerm_application_insights.mlops_insights.instrumentation_key
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Connection string for Application Insights"
  value       = azurerm_application_insights.mlops_insights.connection_string
  sensitive   = true
}

# Log Analytics Information
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.mlops_logs.name
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.mlops_logs.id
}

output "log_analytics_workspace_primary_shared_key" {
  description = "Primary shared key for the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.mlops_logs.primary_shared_key
  sensitive   = true
}

# Node Pool Information
output "ml_node_pool_name" {
  description = "Name of the ML node pool"
  value       = azurerm_kubernetes_cluster_node_pool.ml_pool.name
}

output "ml_node_pool_id" {
  description = "ID of the ML node pool"
  value       = azurerm_kubernetes_cluster_node_pool.ml_pool.id
}

# Monitoring Information
output "action_group_name" {
  description = "Name of the action group for alerts"
  value       = azurerm_monitor_action_group.mlops_alerts.name
}

output "action_group_id" {
  description = "ID of the action group for alerts"
  value       = azurerm_monitor_action_group.mlops_alerts.id
}

# Connection Information for Applications
output "connection_info" {
  description = "Connection information for applications and services"
  value = {
    ml_workspace_name     = azurerm_machine_learning_workspace.mlops_workspace.name
    resource_group_name   = azurerm_resource_group.mlops.name
    aks_cluster_name      = azurerm_kubernetes_cluster.mlops_aks.name
    acr_login_server      = azurerm_container_registry.mlops_acr.login_server
    location              = azurerm_resource_group.mlops.location
    subscription_id       = data.azurerm_client_config.current.subscription_id
  }
}

# Deployment Commands
output "deployment_commands" {
  description = "Useful commands for working with the deployed infrastructure"
  value = {
    get_aks_credentials = "az aks get-credentials --resource-group ${azurerm_resource_group.mlops.name} --name ${azurerm_kubernetes_cluster.mlops_aks.name}"
    acr_login          = "az acr login --name ${azurerm_container_registry.mlops_acr.name}"
    ml_workspace_config = "az ml workspace show --name ${azurerm_machine_learning_workspace.mlops_workspace.name} --resource-group ${azurerm_resource_group.mlops.name}"
  }
}

# Post-deployment Setup Commands
output "post_deployment_setup" {
  description = "Commands to run after deployment for ML extension setup"
  value = {
    install_ml_extension = "az k8s-extension create --name ml-extension --cluster-name ${azurerm_kubernetes_cluster.mlops_aks.name} --resource-group ${azurerm_resource_group.mlops.name} --extension-type Microsoft.AzureML.Kubernetes --cluster-type managedClusters --scope cluster --auto-upgrade-minor-version true"
    attach_aks_to_ml    = "az ml compute attach --resource-group ${azurerm_resource_group.mlops.name} --workspace-name ${azurerm_machine_learning_workspace.mlops_workspace.name} --type Kubernetes --name aks-compute --resource-id ${azurerm_kubernetes_cluster.mlops_aks.id} --identity-type SystemAssigned --namespace azureml"
  }
}

# Resource URLs (for Azure Portal access)
output "azure_portal_urls" {
  description = "Direct URLs to resources in Azure Portal"
  value = {
    resource_group        = "https://portal.azure.com/#@/resource${azurerm_resource_group.mlops.id}"
    ml_workspace         = "https://portal.azure.com/#@/resource${azurerm_machine_learning_workspace.mlops_workspace.id}"
    aks_cluster          = "https://portal.azure.com/#@/resource${azurerm_kubernetes_cluster.mlops_aks.id}"
    container_registry   = "https://portal.azure.com/#@/resource${azurerm_container_registry.mlops_acr.id}"
    application_insights = "https://portal.azure.com/#@/resource${azurerm_application_insights.mlops_insights.id}"
    log_analytics       = "https://portal.azure.com/#@/resource${azurerm_log_analytics_workspace.mlops_logs.id}"
  }
}

# Cost Estimation Information
output "cost_estimation" {
  description = "Estimated monthly costs for the deployed resources"
  value = {
    message = "Cost estimation varies by region and usage. Main cost drivers are:"
    components = [
      "AKS cluster nodes (${var.aks_system_vm_size} x ${var.aks_system_min_nodes}-${var.aks_system_max_nodes})",
      "ML node pool (${var.aks_ml_vm_size} x ${var.aks_ml_min_nodes}-${var.aks_ml_max_nodes})",
      "Azure Container Registry (${var.acr_sku})",
      "Storage accounts (Standard_LRS)",
      "Application Insights and Log Analytics (pay-per-use)",
      "Azure Machine Learning workspace (compute charges apply when used)"
    ]
    note = "Use Azure Pricing Calculator for precise estimates based on your usage patterns"
  }
}

# Security Information
output "security_considerations" {
  description = "Security recommendations for the deployed infrastructure"
  value = {
    recommendations = [
      "Rotate ACR admin credentials regularly or use managed identity",
      "Implement network security groups for AKS subnets",
      "Enable Azure Policy for AKS governance",
      "Configure private endpoints for enhanced security",
      "Use Azure Key Vault for secrets management",
      "Enable audit logging for all resources",
      "Implement proper RBAC for Azure ML workspace"
    ]
  }
}