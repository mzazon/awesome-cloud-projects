# Outputs for Azure Advanced Network Segmentation with Service Mesh and DNS Private Zones
# These outputs provide essential information for accessing and managing the deployed infrastructure

# Resource Group Information
output "resource_group_name" {
  description = "Name of the resource group containing all resources"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Azure region where resources are deployed"
  value       = azurerm_resource_group.main.location
}

# Virtual Network Information
output "virtual_network_name" {
  description = "Name of the virtual network"
  value       = azurerm_virtual_network.main.name
}

output "virtual_network_id" {
  description = "Resource ID of the virtual network"
  value       = azurerm_virtual_network.main.id
}

output "virtual_network_address_space" {
  description = "Address space of the virtual network"
  value       = azurerm_virtual_network.main.address_space
}

# Subnet Information
output "aks_subnet_id" {
  description = "Resource ID of the AKS subnet"
  value       = azurerm_subnet.aks.id
}

output "app_gateway_subnet_id" {
  description = "Resource ID of the Application Gateway subnet"
  value       = azurerm_subnet.app_gateway.id
}

output "private_endpoints_subnet_id" {
  description = "Resource ID of the private endpoints subnet"
  value       = azurerm_subnet.private_endpoints.id
}

# AKS Cluster Information
output "aks_cluster_name" {
  description = "Name of the AKS cluster"
  value       = azurerm_kubernetes_cluster.aks_cluster.name
}

output "aks_cluster_id" {
  description = "Resource ID of the AKS cluster"
  value       = azurerm_kubernetes_cluster.aks_cluster.id
}

output "aks_cluster_fqdn" {
  description = "FQDN of the AKS cluster API server"
  value       = azurerm_kubernetes_cluster.aks_cluster.fqdn
}

output "aks_cluster_kubernetes_version" {
  description = "Kubernetes version of the AKS cluster"
  value       = azurerm_kubernetes_cluster.aks_cluster.kubernetes_version
}

output "aks_cluster_node_resource_group" {
  description = "Resource group containing AKS node resources"
  value       = azurerm_kubernetes_cluster.aks_cluster.node_resource_group
}

# AKS Cluster Credentials (sensitive)
output "aks_cluster_kube_config" {
  description = "kubectl configuration for the AKS cluster"
  value       = azurerm_kubernetes_cluster.aks_cluster.kube_config_raw
  sensitive   = true
}

output "aks_cluster_host" {
  description = "Kubernetes API server endpoint"
  value       = azurerm_kubernetes_cluster.aks_cluster.kube_config.0.host
  sensitive   = true
}

output "aks_cluster_client_certificate" {
  description = "Client certificate for Kubernetes API authentication"
  value       = azurerm_kubernetes_cluster.aks_cluster.kube_config.0.client_certificate
  sensitive   = true
}

output "aks_cluster_client_key" {
  description = "Client key for Kubernetes API authentication"
  value       = azurerm_kubernetes_cluster.aks_cluster.kube_config.0.client_key
  sensitive   = true
}

output "aks_cluster_ca_certificate" {
  description = "Cluster CA certificate for Kubernetes API verification"
  value       = azurerm_kubernetes_cluster.aks_cluster.kube_config.0.cluster_ca_certificate
  sensitive   = true
}

# AKS Identity Information
output "aks_cluster_identity_principal_id" {
  description = "Principal ID of the AKS cluster managed identity"
  value       = azurerm_kubernetes_cluster.aks_cluster.identity[0].principal_id
}

output "aks_cluster_identity_tenant_id" {
  description = "Tenant ID of the AKS cluster managed identity"
  value       = azurerm_kubernetes_cluster.aks_cluster.identity[0].tenant_id
}

# Service Mesh Information
output "istio_addon_enabled" {
  description = "Whether Istio service mesh addon is enabled"
  value       = var.enable_istio_addon
}

output "istio_version" {
  description = "Version of Istio deployed"
  value       = var.istio_version
}

# DNS Private Zone Information
output "private_dns_zone_name" {
  description = "Name of the private DNS zone for internal service discovery"
  value       = azurerm_private_dns_zone.main.name
}

output "private_dns_zone_id" {
  description = "Resource ID of the private DNS zone"
  value       = azurerm_private_dns_zone.main.id
}

# DNS Records Information
output "frontend_service_dns_record" {
  description = "DNS A record for frontend service"
  value       = "frontend-service.${azurerm_private_dns_zone.main.name}"
}

output "backend_service_dns_record" {
  description = "DNS A record for backend service"
  value       = "backend-service.${azurerm_private_dns_zone.main.name}"
}

output "database_service_dns_record" {
  description = "DNS A record for database service"
  value       = "database-service.${azurerm_private_dns_zone.main.name}"
}

# Application Gateway Information
output "application_gateway_name" {
  description = "Name of the Application Gateway"
  value       = azurerm_application_gateway.main.name
}

output "application_gateway_id" {
  description = "Resource ID of the Application Gateway"
  value       = azurerm_application_gateway.main.id
}

output "application_gateway_public_ip" {
  description = "Public IP address of the Application Gateway"
  value       = azurerm_public_ip.app_gateway.ip_address
}

output "application_gateway_fqdn" {
  description = "FQDN of the Application Gateway public IP"
  value       = azurerm_public_ip.app_gateway.fqdn
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

output "log_analytics_primary_shared_key" {
  description = "Primary shared key for Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.primary_shared_key
  sensitive   = true
}

# Kubernetes Namespaces Information (if deployed)
output "frontend_namespace" {
  description = "Name of the frontend namespace"
  value       = var.deploy_sample_applications ? kubernetes_namespace.frontend[0].metadata[0].name : null
}

output "backend_namespace" {
  description = "Name of the backend namespace"
  value       = var.deploy_sample_applications ? kubernetes_namespace.backend[0].metadata[0].name : null
}

output "database_namespace" {
  description = "Name of the database namespace"
  value       = var.deploy_sample_applications ? kubernetes_namespace.database[0].metadata[0].name : null
}

# Application Service Information (if deployed)
output "frontend_service_name" {
  description = "Name of the frontend Kubernetes service"
  value       = var.deploy_sample_applications ? kubernetes_service.frontend[0].metadata[0].name : null
}

output "backend_service_name" {
  description = "Name of the backend Kubernetes service"
  value       = var.deploy_sample_applications ? kubernetes_service.backend[0].metadata[0].name : null
}

output "database_service_name" {
  description = "Name of the database Kubernetes service"
  value       = var.deploy_sample_applications ? kubernetes_service.database[0].metadata[0].name : null
}

# Service IPs (if deployed)
output "frontend_service_cluster_ip" {
  description = "Cluster IP of the frontend service"
  value       = var.deploy_sample_applications ? kubernetes_service.frontend[0].spec[0].cluster_ip : null
}

output "backend_service_cluster_ip" {
  description = "Cluster IP of the backend service"
  value       = var.deploy_sample_applications ? kubernetes_service.backend[0].spec[0].cluster_ip : null
}

output "database_service_cluster_ip" {
  description = "Cluster IP of the database service"
  value       = var.deploy_sample_applications ? kubernetes_service.database[0].spec[0].cluster_ip : null
}

# Monitoring Information
output "monitor_action_group_id" {
  description = "Resource ID of the Azure Monitor action group"
  value       = azurerm_monitor_action_group.main.id
}

output "high_latency_alert_id" {
  description = "Resource ID of the high latency metric alert"
  value       = azurerm_monitor_metric_alert.high_latency.id
}

# Connection Information
output "kubectl_command" {
  description = "Command to configure kubectl for the AKS cluster"
  value       = "az aks get-credentials --resource-group ${azurerm_resource_group.main.name} --name ${azurerm_kubernetes_cluster.aks_cluster.name}"
}

output "application_url" {
  description = "URL to access the deployed application through Application Gateway"
  value       = "http://${azurerm_public_ip.app_gateway.ip_address}"
}

# Security Information
output "network_security_group_id" {
  description = "Resource ID of the AKS network security group"
  value       = azurerm_network_security_group.aks.id
}

output "azure_rbac_enabled" {
  description = "Whether Azure RBAC is enabled for Kubernetes authorization"
  value       = var.enable_azure_rbac
}

output "azure_policy_enabled" {
  description = "Whether Azure Policy addon is enabled"
  value       = var.enable_azure_policy
}

# Deployment Configuration
output "sample_applications_deployed" {
  description = "Whether sample applications were deployed"
  value       = var.deploy_sample_applications
}

output "monitoring_addons_enabled" {
  description = "Whether monitoring addons are enabled"
  value       = var.enable_monitoring_addons
}

# Random Suffix for Reference
output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_string.suffix.result
}

# Complete Resource Names
output "complete_resource_names" {
  description = "Map of all resource names with their complete identifiers"
  value = {
    resource_group           = azurerm_resource_group.main.name
    virtual_network         = azurerm_virtual_network.main.name
    aks_cluster            = azurerm_kubernetes_cluster.aks_cluster.name
    application_gateway    = azurerm_application_gateway.main.name
    log_analytics_workspace = azurerm_log_analytics_workspace.main.name
    private_dns_zone       = azurerm_private_dns_zone.main.name
    public_ip              = azurerm_public_ip.app_gateway.name
    network_security_group = azurerm_network_security_group.aks.name
  }
}

# Access Instructions
output "access_instructions" {
  description = "Instructions for accessing and managing the deployed infrastructure"
  value = {
    configure_kubectl = "az aks get-credentials --resource-group ${azurerm_resource_group.main.name} --name ${azurerm_kubernetes_cluster.aks_cluster.name}"
    access_application = "curl http://${azurerm_public_ip.app_gateway.ip_address}"
    view_logs = "az monitor log-analytics workspace show --resource-group ${azurerm_resource_group.main.name} --workspace-name ${azurerm_log_analytics_workspace.main.name}"
    check_istio = "kubectl get pods -n aks-istio-system"
    verify_dns = "kubectl exec -it <pod-name> -- nslookup frontend-service.${azurerm_private_dns_zone.main.name}"
  }
}