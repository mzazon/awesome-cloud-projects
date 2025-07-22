# Outputs for Azure GitOps CI/CD with Workload Identity and ArgoCD
# These outputs provide essential information for accessing and managing the deployed infrastructure

# Resource Group Information
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Location of the resource group"
  value       = azurerm_resource_group.main.location
}

# AKS Cluster Information
output "cluster_name" {
  description = "Name of the AKS cluster"
  value       = azurerm_kubernetes_cluster.aks.name
}

output "cluster_fqdn" {
  description = "FQDN of the AKS cluster"
  value       = azurerm_kubernetes_cluster.aks.fqdn
}

output "cluster_oidc_issuer_url" {
  description = "OIDC issuer URL of the AKS cluster for workload identity"
  value       = azurerm_kubernetes_cluster.aks.oidc_issuer_url
}

output "cluster_node_resource_group" {
  description = "Resource group containing the AKS cluster nodes"
  value       = azurerm_kubernetes_cluster.aks.node_resource_group
}

output "kube_config" {
  description = "Kubernetes configuration for kubectl access"
  value       = azurerm_kubernetes_cluster.aks.kube_config_raw
  sensitive   = true
}

# Azure Key Vault Information
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

# Managed Identity Information
output "managed_identity_name" {
  description = "Name of the user-assigned managed identity"
  value       = azurerm_user_assigned_identity.argocd.name
}

output "managed_identity_client_id" {
  description = "Client ID of the user-assigned managed identity"
  value       = azurerm_user_assigned_identity.argocd.client_id
}

output "managed_identity_principal_id" {
  description = "Principal ID of the user-assigned managed identity"
  value       = azurerm_user_assigned_identity.argocd.principal_id
}

output "managed_identity_tenant_id" {
  description = "Tenant ID of the user-assigned managed identity"
  value       = azurerm_user_assigned_identity.argocd.tenant_id
}

# ArgoCD Information
output "argocd_namespace" {
  description = "Kubernetes namespace where ArgoCD is deployed"
  value       = kubernetes_namespace.argocd.metadata[0].name
}

output "argocd_server_service_name" {
  description = "Name of the ArgoCD server service"
  value       = "argocd-server"
}

output "argocd_ui_loadbalancer_ip" {
  description = "LoadBalancer IP for ArgoCD UI (if enabled)"
  value       = var.enable_argocd_ui_loadbalancer ? try(kubernetes_service.argocd_server_lb[0].status[0].load_balancer[0].ingress[0].ip, "Pending") : "LoadBalancer not enabled"
}

# Sample Application Information
output "sample_app_namespace" {
  description = "Kubernetes namespace for the sample application"
  value       = kubernetes_namespace.sample_app.metadata[0].name
}

output "sample_app_service_account" {
  description = "Service account name for the sample application"
  value       = kubernetes_service_account.sample_app.metadata[0].name
}

# Secret Management Information
output "secret_provider_class_name" {
  description = "Name of the SecretProviderClass for Key Vault integration"
  value       = kubernetes_manifest.secret_provider_class.manifest.metadata.name
}

output "sample_secrets_stored" {
  description = "List of secret names stored in Key Vault"
  value       = keys(var.sample_secrets)
}

# Federated Identity Credentials
output "federated_identity_credentials" {
  description = "List of federated identity credentials created"
  value = [
    azurerm_federated_identity_credential.argocd_application_controller.name,
    azurerm_federated_identity_credential.argocd_server.name,
    azurerm_federated_identity_credential.sample_app.name
  ]
}

# ArgoCD Application Information
output "argocd_application_name" {
  description = "Name of the ArgoCD application for GitOps"
  value       = kubernetes_manifest.argocd_application.manifest.metadata.name
}

output "git_repository_url" {
  description = "Git repository URL configured for ArgoCD application"
  value       = var.git_repository_url
}

output "git_target_revision" {
  description = "Git target revision (branch/tag/commit) for ArgoCD application"
  value       = var.git_target_revision
}

output "git_path" {
  description = "Path within Git repository for application manifests"
  value       = var.git_path
}

# Monitoring Information
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace (if Azure Monitor is enabled)"
  value       = var.enable_azure_monitor ? azurerm_log_analytics_workspace.main[0].name : "Azure Monitor not enabled"
}

output "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics workspace (if Azure Monitor is enabled)"
  value       = var.enable_azure_monitor ? azurerm_log_analytics_workspace.main[0].id : "Azure Monitor not enabled"
}

# Connection Information
output "kubectl_connection_command" {
  description = "Command to configure kubectl for cluster access"
  value       = "az aks get-credentials --resource-group ${azurerm_resource_group.main.name} --name ${azurerm_kubernetes_cluster.aks.name}"
}

output "argocd_admin_password_command" {
  description = "Command to retrieve ArgoCD admin password"
  value       = "kubectl get secret argocd-initial-admin-secret -n ${kubernetes_namespace.argocd.metadata[0].name} -o jsonpath='{.data.password}' | base64 -d"
}

output "argocd_port_forward_command" {
  description = "Command to port-forward ArgoCD UI (if LoadBalancer is not enabled)"
  value       = var.enable_argocd_ui_loadbalancer ? "LoadBalancer enabled - check argocd_ui_loadbalancer_ip output" : "kubectl port-forward svc/argocd-server -n ${kubernetes_namespace.argocd.metadata[0].name} 8080:443"
}

# Validation Commands
output "validation_commands" {
  description = "Commands to validate the deployment"
  value = {
    check_cluster_status       = "kubectl get nodes"
    check_argocd_pods         = "kubectl get pods -n ${kubernetes_namespace.argocd.metadata[0].name}"
    check_sample_app_pods     = "kubectl get pods -n ${kubernetes_namespace.sample_app.metadata[0].name}"
    check_workload_identity   = "kubectl get serviceaccount ${kubernetes_service_account.sample_app.metadata[0].name} -n ${kubernetes_namespace.sample_app.metadata[0].name} -o yaml"
    check_secrets_mount       = "kubectl exec -it deployment/sample-app -n ${kubernetes_namespace.sample_app.metadata[0].name} -- ls -la /mnt/secrets"
    check_argocd_application  = "kubectl get application ${kubernetes_manifest.argocd_application.manifest.metadata.name} -n ${kubernetes_namespace.argocd.metadata[0].name}"
    verify_key_vault_access   = "kubectl exec -it deployment/sample-app -n ${kubernetes_namespace.sample_app.metadata[0].name} -- env | grep DATABASE_CONNECTION_STRING"
  }
}

# Cost Information
output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown (USD)"
  value = {
    aks_cluster     = "~$73.00 (3 Standard_D2s_v3 nodes)"
    key_vault       = "~$0.03 (per 10,000 operations)"
    log_analytics   = var.enable_azure_monitor ? "~$2.76 (per GB ingested)" : "Not enabled"
    load_balancer   = var.enable_argocd_ui_loadbalancer ? "~$21.90 (Standard LB)" : "Not enabled"
    total_estimated = var.enable_argocd_ui_loadbalancer ? "~$97.69/month" : "~$75.79/month"
    note           = "Costs may vary based on usage patterns and region"
  }
}

# Security and Compliance Information
output "security_features_enabled" {
  description = "Security features enabled in the deployment"
  value = {
    workload_identity           = "Enabled"
    rbac_authorization         = "Enabled"
    key_vault_rbac            = "Enabled"
    secrets_store_csi_driver  = "Enabled"
    azure_monitor             = var.enable_azure_monitor ? "Enabled" : "Disabled"
    azure_policy              = var.enable_azure_policy ? "Enabled" : "Disabled"
    network_policy            = var.enable_network_policy != "" ? var.enable_network_policy : "Disabled"
    managed_identity          = "User-assigned"
    oidc_issuer               = "Enabled"
    federated_credentials     = "3 configured"
  }
}