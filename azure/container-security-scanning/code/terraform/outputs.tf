# Output Values for Container Security Scanning Infrastructure
# This file defines all output values that will be displayed after deployment

# Resource Group Information
output "resource_group_name" {
  description = "Name of the resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Location of the resource group"
  value       = azurerm_resource_group.main.location
}

output "resource_group_id" {
  description = "Resource ID of the resource group"
  value       = azurerm_resource_group.main.id
}

# Azure Container Registry Information
output "acr_name" {
  description = "Name of the Azure Container Registry"
  value       = azurerm_container_registry.main.name
}

output "acr_login_server" {
  description = "Login server URL of the Azure Container Registry"
  value       = azurerm_container_registry.main.login_server
}

output "acr_id" {
  description = "Resource ID of the Azure Container Registry"
  value       = azurerm_container_registry.main.id
}

output "acr_resource_group_name" {
  description = "Resource group name of the Azure Container Registry"
  value       = azurerm_container_registry.main.resource_group_name
}

# Service Principal Information (conditional)
output "service_principal_application_id" {
  description = "Application ID of the service principal for DevOps integration"
  value       = var.create_service_principal ? azuread_application.devops[0].application_id : null
  sensitive   = true
}

output "service_principal_object_id" {
  description = "Object ID of the service principal"
  value       = var.create_service_principal ? azuread_service_principal.devops[0].object_id : null
}

output "service_principal_password" {
  description = "Password for the service principal"
  value       = var.create_service_principal ? azuread_service_principal_password.devops[0].value : null
  sensitive   = true
}

# Log Analytics Workspace Information
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.name
}

output "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.id
}

output "log_analytics_workspace_workspace_id" {
  description = "Workspace ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.workspace_id
}

output "log_analytics_workspace_primary_shared_key" {
  description = "Primary shared key of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.primary_shared_key
  sensitive   = true
}

# AKS Cluster Information (conditional)
output "aks_cluster_name" {
  description = "Name of the AKS cluster"
  value       = var.create_aks_cluster ? azurerm_kubernetes_cluster.main[0].name : null
}

output "aks_cluster_id" {
  description = "Resource ID of the AKS cluster"
  value       = var.create_aks_cluster ? azurerm_kubernetes_cluster.main[0].id : null
}

output "aks_cluster_fqdn" {
  description = "FQDN of the AKS cluster"
  value       = var.create_aks_cluster ? azurerm_kubernetes_cluster.main[0].fqdn : null
}

output "aks_cluster_kube_config" {
  description = "Raw kubeconfig for the AKS cluster"
  value       = var.create_aks_cluster ? azurerm_kubernetes_cluster.main[0].kube_config_raw : null
  sensitive   = true
}

output "aks_cluster_node_resource_group" {
  description = "Resource group containing AKS cluster nodes"
  value       = var.create_aks_cluster ? azurerm_kubernetes_cluster.main[0].node_resource_group : null
}

# Microsoft Defender Information
output "defender_for_containers_pricing_tier" {
  description = "Pricing tier for Microsoft Defender for Containers"
  value       = var.defender_for_containers_enabled ? azurerm_security_center_subscription_pricing.containers[0].tier : null
}

output "defender_for_container_registries_pricing_tier" {
  description = "Pricing tier for Microsoft Defender for Container Registries"
  value       = var.defender_for_container_registries_enabled ? azurerm_security_center_subscription_pricing.container_registries[0].tier : null
}

# Azure Policy Information
output "policy_assignments" {
  description = "List of Azure Policy assignments created"
  value = var.enable_policy_enforcement ? {
    container_registry_vulnerability_assessment = azurerm_resource_policy_assignment.container_registry_vulnerability_assessment[0].id
    container_registry_trusted_services         = azurerm_resource_policy_assignment.container_registry_trusted_services[0].id
    container_registry_disable_anonymous_pull   = azurerm_resource_policy_assignment.container_registry_disable_anonymous_pull[0].id
  } : {}
}

# Monitor Information
output "action_group_id" {
  description = "Resource ID of the action group for security alerts"
  value       = var.enable_security_alerts ? azurerm_monitor_action_group.security_alerts[0].id : null
}

output "activity_log_alert_id" {
  description = "Resource ID of the activity log alert"
  value       = var.enable_security_alerts ? azurerm_monitor_activity_log_alert.security_events[0].id : null
}

# Diagnostic Settings Information
output "acr_diagnostic_setting_id" {
  description = "Resource ID of the ACR diagnostic setting"
  value       = azurerm_monitor_diagnostic_setting.acr.id
}

output "aks_diagnostic_setting_id" {
  description = "Resource ID of the AKS diagnostic setting"
  value       = var.create_aks_cluster ? azurerm_monitor_diagnostic_setting.aks[0].id : null
}

# Network Security Information
output "acr_network_rule_set" {
  description = "Network rule set configuration for the container registry"
  value = {
    default_action = azurerm_container_registry.main.network_rule_set[0].default_action
    ip_rules       = azurerm_container_registry.main.network_rule_set[0].ip_rule
  }
}

# Security Contact Information
output "security_contact_email" {
  description = "Email address for security contact"
  value       = var.enable_security_alerts && length(var.alert_email_addresses) > 0 ? azurerm_security_center_contact.main[0].email : null
}

# Random Suffix for Resource Naming
output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_string.suffix.result
}

# Container Registry Policies
output "acr_policies" {
  description = "Container registry policies configuration"
  value = {
    quarantine_policy_enabled = var.acr_quarantine_policy_enabled
    trust_policy_enabled      = var.acr_trust_policy_enabled
    retention_policy_days     = var.acr_retention_policy_days
  }
}

# Connection Strings and Commands
output "docker_login_command" {
  description = "Docker login command for the container registry"
  value       = "az acr login --name ${azurerm_container_registry.main.name}"
}

output "kubectl_config_command" {
  description = "Command to configure kubectl for the AKS cluster"
  value       = var.create_aks_cluster ? "az aks get-credentials --resource-group ${azurerm_resource_group.main.name} --name ${azurerm_kubernetes_cluster.main[0].name}" : null
}

# Validation and Testing Information
output "validation_commands" {
  description = "Commands to validate the deployment"
  value = {
    check_acr_status = "az acr show --name ${azurerm_container_registry.main.name} --resource-group ${azurerm_resource_group.main.name}"
    check_defender_status = "az security pricing show --name Containers"
    list_policy_assignments = "az policy assignment list --resource-group ${azurerm_resource_group.main.name}"
    check_diagnostic_settings = "az monitor diagnostic-settings list --resource ${azurerm_container_registry.main.id}"
  }
}

# Cost Estimation Information
output "cost_estimation" {
  description = "Estimated monthly costs for the deployed resources"
  value = {
    acr_standard_tier = "$5.00/month"
    log_analytics_workspace = "$2.30/GB/month"
    defender_for_containers = "$7.00/vCore/month"
    aks_cluster = "$73.00/month (2 Standard_D2s_v3 nodes)"
    total_estimated = "$85-100/month"
  }
}