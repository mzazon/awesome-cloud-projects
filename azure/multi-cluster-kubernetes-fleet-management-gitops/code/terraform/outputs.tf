# Resource Group Outputs
output "resource_group_name" {
  description = "Name of the resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Location of the resource group"
  value       = azurerm_resource_group.main.location
}

# Fleet Manager Outputs
output "fleet_manager_name" {
  description = "Name of the Azure Kubernetes Fleet Manager"
  value       = azurerm_kubernetes_fleet_manager.main.name
}

output "fleet_manager_id" {
  description = "ID of the Azure Kubernetes Fleet Manager"
  value       = azurerm_kubernetes_fleet_manager.main.id
}

output "fleet_manager_fqdn" {
  description = "FQDN of the Azure Kubernetes Fleet Manager"
  value       = azurerm_kubernetes_fleet_manager.main.fqdn
}

# AKS Cluster Outputs
output "aks_cluster_names" {
  description = "Names of the AKS clusters"
  value       = azurerm_kubernetes_cluster.clusters[*].name
}

output "aks_cluster_ids" {
  description = "IDs of the AKS clusters"
  value       = azurerm_kubernetes_cluster.clusters[*].id
}

output "aks_cluster_fqdns" {
  description = "FQDNs of the AKS clusters"
  value       = azurerm_kubernetes_cluster.clusters[*].fqdn
}

output "aks_cluster_locations" {
  description = "Locations of the AKS clusters"
  value       = azurerm_kubernetes_cluster.clusters[*].location
}

output "aks_cluster_kube_configs" {
  description = "Kubernetes configurations for the AKS clusters"
  value       = azurerm_kubernetes_cluster.clusters[*].kube_config_raw
  sensitive   = true
}

output "aks_cluster_node_resource_groups" {
  description = "Node resource groups for the AKS clusters"
  value       = azurerm_kubernetes_cluster.clusters[*].node_resource_group
}

# Fleet Member Outputs
output "fleet_member_names" {
  description = "Names of the fleet members"
  value       = azurerm_kubernetes_fleet_member.members[*].name
}

output "fleet_member_ids" {
  description = "IDs of the fleet members"
  value       = azurerm_kubernetes_fleet_member.members[*].id
}

output "fleet_member_groups" {
  description = "Groups of the fleet members"
  value       = azurerm_kubernetes_fleet_member.members[*].group
}

# Service Principal Outputs
output "aso_service_principal_application_id" {
  description = "Application ID of the Azure Service Operator service principal"
  value       = azuread_service_principal.aso.application_id
}

output "aso_service_principal_object_id" {
  description = "Object ID of the Azure Service Operator service principal"
  value       = azuread_service_principal.aso.object_id
}

output "aso_service_principal_client_secret" {
  description = "Client secret of the Azure Service Operator service principal"
  value       = azuread_service_principal_password.aso.value
  sensitive   = true
}

# Container Registry Outputs
output "container_registry_name" {
  description = "Name of the Azure Container Registry"
  value       = azurerm_container_registry.main.name
}

output "container_registry_id" {
  description = "ID of the Azure Container Registry"
  value       = azurerm_container_registry.main.id
}

output "container_registry_login_server" {
  description = "Login server of the Azure Container Registry"
  value       = azurerm_container_registry.main.login_server
}

output "container_registry_admin_enabled" {
  description = "Whether admin is enabled for the Azure Container Registry"
  value       = azurerm_container_registry.main.admin_enabled
}

# Key Vault Outputs
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

output "key_vault_secret_names" {
  description = "Names of the secrets in the Key Vault"
  value       = [azurerm_key_vault_secret.database_connection.name]
}

# Storage Account Outputs
output "storage_account_names" {
  description = "Names of the regional storage accounts"
  value       = azurerm_storage_account.regional[*].name
}

output "storage_account_ids" {
  description = "IDs of the regional storage accounts"
  value       = azurerm_storage_account.regional[*].id
}

output "storage_account_primary_endpoints" {
  description = "Primary blob endpoints of the regional storage accounts"
  value       = azurerm_storage_account.regional[*].primary_blob_endpoint
}

output "storage_account_locations" {
  description = "Locations of the regional storage accounts"
  value       = azurerm_storage_account.regional[*].location
}

# Kubernetes Namespace Outputs
output "kubernetes_namespaces" {
  description = "Names of the Kubernetes namespaces created"
  value = {
    cert_manager    = var.cert_manager_namespace
    aso             = var.aso_namespace
    app             = var.app_namespace
    azure_resources = "azure-resources"
  }
}

# Application Outputs
output "application_name" {
  description = "Name of the deployed application"
  value       = "regional-app"
}

output "application_namespace" {
  description = "Namespace of the deployed application"
  value       = var.app_namespace
}

output "application_replicas" {
  description = "Number of replicas for the application"
  value       = var.app_replicas
}

# Configuration Outputs
output "regions" {
  description = "Regions where resources are deployed"
  value       = var.regions
}

output "random_suffix" {
  description = "Random suffix used for globally unique resource names"
  value       = random_string.suffix.result
}

output "subscription_id" {
  description = "Azure subscription ID"
  value       = data.azurerm_client_config.current.subscription_id
}

output "tenant_id" {
  description = "Azure tenant ID"
  value       = data.azurerm_client_config.current.tenant_id
}

# Connection Commands
output "kubectl_commands" {
  description = "Commands to connect to the AKS clusters"
  value = [
    for i, cluster in azurerm_kubernetes_cluster.clusters :
    "az aks get-credentials --resource-group ${azurerm_resource_group.main.name} --name ${cluster.name} --overwrite-existing"
  ]
}

output "fleet_management_commands" {
  description = "Commands to manage the fleet"
  value = {
    list_members = "az fleet member list --resource-group ${azurerm_resource_group.main.name} --fleet-name ${azurerm_kubernetes_fleet_manager.main.name} --output table"
    fleet_status = "az fleet show --resource-group ${azurerm_resource_group.main.name} --name ${azurerm_kubernetes_fleet_manager.main.name} --output table"
  }
}

output "validation_commands" {
  description = "Commands to validate the deployment"
  value = {
    check_acr     = "az acr show --name ${azurerm_container_registry.main.name} --query provisioningState -o tsv"
    check_keyvault = "az keyvault show --name ${azurerm_key_vault.main.name} --query provisioningState -o tsv"
    check_fleet   = "az fleet show --resource-group ${azurerm_resource_group.main.name} --name ${azurerm_kubernetes_fleet_manager.main.name} --query provisioningState -o tsv"
  }
}