# Output values for Azure cloud-native service connectivity infrastructure
# These outputs provide essential information for post-deployment configuration and integration

# Resource Group Information
output "resource_group_name" {
  description = "Name of the resource group containing all resources"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Location of the resource group"
  value       = azurerm_resource_group.main.location
}

# AKS Cluster Information
output "aks_cluster_name" {
  description = "Name of the AKS cluster"
  value       = azurerm_kubernetes_cluster.main.name
}

output "aks_cluster_id" {
  description = "Resource ID of the AKS cluster"
  value       = azurerm_kubernetes_cluster.main.id
}

output "aks_cluster_fqdn" {
  description = "FQDN of the AKS cluster"
  value       = azurerm_kubernetes_cluster.main.fqdn
}

output "aks_oidc_issuer_url" {
  description = "OIDC issuer URL for AKS cluster (required for workload identity)"
  value       = azurerm_kubernetes_cluster.main.oidc_issuer_url
}

output "aks_kube_config_raw" {
  description = "Raw Kubernetes configuration for AKS cluster"
  value       = azurerm_kubernetes_cluster.main.kube_config_raw
  sensitive   = true
}

output "aks_node_resource_group" {
  description = "Resource group containing AKS node resources"
  value       = azurerm_kubernetes_cluster.main.node_resource_group
}

# Managed Identity Information
output "managed_identity_name" {
  description = "Name of the user-assigned managed identity"
  value       = azurerm_user_assigned_identity.workload_identity.name
}

output "managed_identity_client_id" {
  description = "Client ID of the user-assigned managed identity"
  value       = azurerm_user_assigned_identity.workload_identity.client_id
}

output "managed_identity_principal_id" {
  description = "Principal ID of the user-assigned managed identity"
  value       = azurerm_user_assigned_identity.workload_identity.principal_id
}

output "managed_identity_resource_id" {
  description = "Resource ID of the user-assigned managed identity"
  value       = azurerm_user_assigned_identity.workload_identity.id
}

# Storage Account Information
output "storage_account_name" {
  description = "Name of the Azure Storage Account"
  value       = azurerm_storage_account.main.name
}

output "storage_account_primary_endpoint" {
  description = "Primary endpoint of the Azure Storage Account"
  value       = azurerm_storage_account.main.primary_blob_endpoint
}

output "storage_account_resource_id" {
  description = "Resource ID of the Azure Storage Account"
  value       = azurerm_storage_account.main.id
}

# SQL Server Information
output "sql_server_name" {
  description = "Name of the Azure SQL Server"
  value       = azurerm_mssql_server.main.name
}

output "sql_server_fqdn" {
  description = "Fully qualified domain name of the Azure SQL Server"
  value       = azurerm_mssql_server.main.fully_qualified_domain_name
}

output "sql_database_name" {
  description = "Name of the Azure SQL Database"
  value       = azurerm_mssql_database.main.name
}

output "sql_database_id" {
  description = "Resource ID of the Azure SQL Database"
  value       = azurerm_mssql_database.main.id
}

# Key Vault Information
output "key_vault_name" {
  description = "Name of the Azure Key Vault"
  value       = azurerm_key_vault.main.name
}

output "key_vault_uri" {
  description = "URI of the Azure Key Vault"
  value       = azurerm_key_vault.main.vault_uri
}

output "key_vault_id" {
  description = "Resource ID of the Azure Key Vault"
  value       = azurerm_key_vault.main.id
}

# Log Analytics Workspace Information
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics Workspace"
  value       = azurerm_log_analytics_workspace.main.name
}

output "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics Workspace"
  value       = azurerm_log_analytics_workspace.main.id
}

# Networking Information
output "service_cidr" {
  description = "Service CIDR used by the AKS cluster"
  value       = azurerm_kubernetes_cluster.main.network_profile[0].service_cidr
}

output "dns_service_ip" {
  description = "DNS service IP used by the AKS cluster"
  value       = azurerm_kubernetes_cluster.main.network_profile[0].dns_service_ip
}

# Random suffix for reference
output "random_suffix" {
  description = "Random suffix used for unique resource naming"
  value       = random_string.suffix.result
}

# Configuration Information for Kubernetes Resources
output "kubernetes_namespace" {
  description = "Kubernetes namespace name for applications"
  value       = var.namespace_name
}

output "kubernetes_service_account" {
  description = "Kubernetes service account name for workload identity"
  value       = var.service_account_name
}

# Connection Information for Service Connector
output "service_connector_targets" {
  description = "Target resources for Service Connector connections"
  value = {
    storage_account = {
      name        = azurerm_storage_account.main.name
      resource_id = azurerm_storage_account.main.id
    }
    sql_server = {
      name        = azurerm_mssql_server.main.name
      database    = azurerm_mssql_database.main.name
      resource_id = azurerm_mssql_database.main.id
    }
    key_vault = {
      name        = azurerm_key_vault.main.name
      resource_id = azurerm_key_vault.main.id
    }
  }
}

# Application Gateway for Containers Information
output "application_gateway_for_containers_name" {
  description = "Name that should be used for Application Gateway for Containers"
  value       = "agc-connectivity-${random_string.suffix.result}"
}

# Environment variables for application configuration
output "application_environment_variables" {
  description = "Environment variables to be used in application deployments"
  value = {
    AZURE_CLIENT_ID       = azurerm_user_assigned_identity.workload_identity.client_id
    STORAGE_ACCOUNT_NAME  = azurerm_storage_account.main.name
    KEY_VAULT_NAME        = azurerm_key_vault.main.name
    SQL_SERVER_NAME       = azurerm_mssql_server.main.name
    SQL_DATABASE_NAME     = azurerm_mssql_database.main.name
  }
}

# Tags applied to resources
output "resource_tags" {
  description = "Tags applied to all resources"
  value       = var.tags
}

# Deployment summary
output "deployment_summary" {
  description = "Summary of deployed resources and their purposes"
  value = {
    resource_group           = "Container for all cloud-native connectivity resources"
    aks_cluster             = "Kubernetes cluster with workload identity and Application Gateway for Containers addon"
    managed_identity        = "User-assigned identity for passwordless authentication"
    storage_account         = "Storage service for Service Connector integration"
    sql_server_database     = "Database service for Service Connector integration"
    key_vault              = "Secret management service for Service Connector integration"
    log_analytics          = "Monitoring and logging workspace for AKS cluster"
    federated_credential   = "Links managed identity to AKS cluster for workload identity"
    role_assignments       = "RBAC permissions for managed identity to access Azure services"
  }
}