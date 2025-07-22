# Output values for Azure Workload Identity and Container Storage Infrastructure

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
output "aks_cluster_name" {
  description = "Name of the AKS cluster"
  value       = azurerm_kubernetes_cluster.aks.name
}

output "aks_cluster_id" {
  description = "ID of the AKS cluster"
  value       = azurerm_kubernetes_cluster.aks.id
}

output "aks_cluster_fqdn" {
  description = "FQDN of the AKS cluster"
  value       = azurerm_kubernetes_cluster.aks.fqdn
}

output "aks_cluster_kubernetes_version" {
  description = "Kubernetes version of the AKS cluster"
  value       = azurerm_kubernetes_cluster.aks.kubernetes_version
}

output "oidc_issuer_url" {
  description = "OIDC issuer URL for the AKS cluster"
  value       = azurerm_kubernetes_cluster.aks.oidc_issuer_url
}

# Workload Identity Information
output "managed_identity_name" {
  description = "Name of the user-assigned managed identity"
  value       = azurerm_user_assigned_identity.workload_identity.name
}

output "managed_identity_client_id" {
  description = "Client ID of the user-assigned managed identity"
  value       = azurerm_user_assigned_identity.workload_identity.client_id
  sensitive   = true
}

output "managed_identity_principal_id" {
  description = "Principal ID of the user-assigned managed identity"
  value       = azurerm_user_assigned_identity.workload_identity.principal_id
  sensitive   = true
}

output "federated_credential_name" {
  description = "Name of the federated credential"
  value       = azurerm_federated_identity_credential.workload_identity.name
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

# Container Storage Information
output "container_storage_extension_name" {
  description = "Name of the Azure Container Storage extension"
  value       = var.enable_container_storage ? azurerm_kubernetes_cluster_extension.container_storage[0].name : null
}

output "container_storage_namespace" {
  description = "Namespace where Azure Container Storage is deployed"
  value       = var.enable_container_storage ? var.container_storage_release_namespace : null
}

output "storage_class_name" {
  description = "Name of the ephemeral storage class"
  value       = var.enable_container_storage ? kubernetes_storage_class_v1.ephemeral_storage[0].metadata[0].name : null
}

# Kubernetes Configuration
output "kubernetes_namespace" {
  description = "Kubernetes namespace for workload identity demo"
  value       = kubernetes_namespace.workload_identity_demo.metadata[0].name
}

output "service_account_name" {
  description = "Name of the Kubernetes service account"
  value       = kubernetes_service_account.workload_identity.metadata[0].name
}

output "service_account_namespace" {
  description = "Namespace of the Kubernetes service account"
  value       = kubernetes_service_account.workload_identity.metadata[0].namespace
}

# Test Workload Information
output "test_workload_enabled" {
  description = "Whether the test workload is enabled"
  value       = var.enable_test_workload
}

output "test_workload_deployment_name" {
  description = "Name of the test workload deployment"
  value       = var.enable_test_workload ? kubernetes_deployment_v1.workload_identity_test[0].metadata[0].name : null
}

# Connection Information
output "kube_config_raw" {
  description = "Raw kubeconfig for the AKS cluster"
  value       = azurerm_kubernetes_cluster.aks.kube_config_raw
  sensitive   = true
}

output "kube_config" {
  description = "Kubeconfig for the AKS cluster"
  value = {
    host                   = azurerm_kubernetes_cluster.aks.kube_config.0.host
    cluster_ca_certificate = azurerm_kubernetes_cluster.aks.kube_config.0.cluster_ca_certificate
    client_certificate     = azurerm_kubernetes_cluster.aks.kube_config.0.client_certificate
    client_key            = azurerm_kubernetes_cluster.aks.kube_config.0.client_key
  }
  sensitive = true
}

# CLI Commands for Manual Operations
output "kubectl_config_command" {
  description = "Command to configure kubectl"
  value       = "az aks get-credentials --resource-group ${azurerm_resource_group.main.name} --name ${azurerm_kubernetes_cluster.aks.name}"
}

output "key_vault_access_test_command" {
  description = "Command to test Key Vault access"
  value       = "az keyvault secret show --name storage-encryption-key --vault-name ${azurerm_key_vault.main.name}"
}

# Verification Commands
output "verification_commands" {
  description = "Commands to verify the deployment"
  value = {
    check_pods                = "kubectl get pods -n ${kubernetes_namespace.workload_identity_demo.metadata[0].name}"
    check_storage_pool       = var.enable_container_storage ? "kubectl get storagepool -n ${var.container_storage_release_namespace}" : "N/A - Container Storage not enabled"
    check_storage_class      = var.enable_container_storage ? "kubectl get storageclass ephemeral-storage" : "N/A - Container Storage not enabled"
    check_pvc               = var.enable_test_workload && var.enable_container_storage ? "kubectl get pvc -n ${kubernetes_namespace.workload_identity_demo.metadata[0].name}" : "N/A - Test workload or Container Storage not enabled"
    view_workload_logs      = var.enable_test_workload ? "kubectl logs -n ${kubernetes_namespace.workload_identity_demo.metadata[0].name} -l app=workload-identity-test --tail=20" : "N/A - Test workload not enabled"
    check_federated_creds   = "az identity federated-credential list --identity-name ${azurerm_user_assigned_identity.workload_identity.name} --resource-group ${azurerm_resource_group.main.name} --output table"
  }
}

# Cost Information
output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown (USD)"
  value = {
    aks_cluster     = "$73-$146 (based on node count and VM size)"
    key_vault       = "$1-$5 (based on operations)"
    managed_identity = "$0 (no charge for user-assigned identities)"
    storage         = "$5-$20 (based on ephemeral storage usage)"
    total_estimate  = "$79-$171 (excluding network egress)"
    note           = "Costs may vary based on usage patterns and Azure region"
  }
}

# Security Information
output "security_features" {
  description = "Security features enabled in this deployment"
  value = {
    workload_identity        = "Enabled - No stored secrets required"
    rbac_authorization      = "Enabled - Azure RBAC for Key Vault access"
    oidc_federation         = "Enabled - JWT token exchange"
    network_policies        = "Enabled - Azure CNI with network policies"
    ephemeral_os_disks      = "Enabled - Reduced attack surface"
    managed_identity        = "User-assigned identity with least privilege"
    key_vault_rbac          = "Enabled - Fine-grained access control"
  }
}

# Next Steps
output "next_steps" {
  description = "Next steps after deployment"
  value = {
    step_1 = "Run: ${output.verification_commands.value.kubectl_config_command}"
    step_2 = "Verify pods: ${output.verification_commands.value.check_pods}"
    step_3 = var.enable_test_workload ? "Check logs: ${output.verification_commands.value.view_workload_logs}" : "Deploy test workload by setting var.enable_test_workload = true"
    step_4 = var.enable_container_storage ? "Verify storage: ${output.verification_commands.value.check_storage_pool}" : "Enable container storage by setting var.enable_container_storage = true"
    step_5 = "Test Key Vault access: ${output.verification_commands.value.key_vault_access_test_command}"
  }
}