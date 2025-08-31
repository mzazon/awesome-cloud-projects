# Primary application access outputs
output "application_url" {
  description = "The HTTPS URL of the deployed container application"
  value       = var.ingress_enabled ? "https://${azurerm_container_app.main.latest_revision_fqdn}" : null
}

output "application_fqdn" {
  description = "The fully qualified domain name of the container application"
  value       = var.ingress_enabled ? azurerm_container_app.main.latest_revision_fqdn : null
}

# Resource identification outputs
output "resource_group_name" {
  description = "Name of the Azure resource group containing all resources"
  value       = azurerm_resource_group.main.name
}

output "resource_group_id" {
  description = "Azure resource ID of the resource group"
  value       = azurerm_resource_group.main.id
}

output "location" {
  description = "Azure region where resources were deployed"
  value       = azurerm_resource_group.main.location
}

# Container Apps specific outputs
output "container_app_name" {
  description = "Name of the deployed container application"
  value       = azurerm_container_app.main.name
}

output "container_app_id" {
  description = "Azure resource ID of the container application"
  value       = azurerm_container_app.main.id
}

output "container_app_environment_name" {
  description = "Name of the Container Apps environment"
  value       = azurerm_container_app_environment.main.name
}

output "container_app_environment_id" {
  description = "Azure resource ID of the Container Apps environment"
  value       = azurerm_container_app_environment.main.id
}

output "container_app_environment_default_domain" {
  description = "Default domain of the Container Apps environment"
  value       = azurerm_container_app_environment.main.default_domain
}

# Monitoring and observability outputs
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace for monitoring"
  value       = azurerm_log_analytics_workspace.main.name
}

output "log_analytics_workspace_id" {
  description = "Azure resource ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.id
}

output "log_analytics_workspace_workspace_id" {
  description = "Workspace ID for Log Analytics (used for monitoring queries)"
  value       = azurerm_log_analytics_workspace.main.workspace_id
  sensitive   = true
}

output "log_analytics_primary_shared_key" {
  description = "Primary shared key for Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.primary_shared_key
  sensitive   = true
}

# Application configuration outputs
output "container_image" {
  description = "Container image deployed to the application"
  value       = var.container_image
}

output "container_port" {
  description = "Port the container listens on"
  value       = var.container_port
}

output "scaling_configuration" {
  description = "Scaling configuration for the container application"
  value = {
    min_replicas = var.min_replicas
    max_replicas = var.max_replicas
  }
}

output "resource_allocation" {
  description = "Resource allocation per container replica"
  value = {
    cpu    = var.cpu_requests
    memory = var.memory_requests
  }
}

# Environment and deployment information
output "environment" {
  description = "Environment designation for the deployment"
  value       = var.environment
}

output "random_suffix" {
  description = "Random suffix used for unique resource naming"
  value       = local.suffix
}

output "deployment_tags" {
  description = "Tags applied to all resources in this deployment"
  value       = local.common_tags
}

# Management commands for reference
output "management_commands" {
  description = "Useful Azure CLI commands for managing this deployment"
  value = {
    view_app_logs     = "az containerapp logs show --name ${azurerm_container_app.main.name} --resource-group ${azurerm_resource_group.main.name} --follow"
    view_app_details  = "az containerapp show --name ${azurerm_container_app.main.name} --resource-group ${azurerm_resource_group.main.name}"
    scale_app         = "az containerapp update --name ${azurerm_container_app.main.name} --resource-group ${azurerm_resource_group.main.name} --min-replicas <min> --max-replicas <max>"
    restart_app       = "az containerapp revision restart --name ${azurerm_container_app.main.name} --resource-group ${azurerm_resource_group.main.name}"
  }
}

# Validation outputs for testing
output "ingress_enabled" {
  description = "Whether external ingress is enabled for the application"
  value       = var.ingress_enabled
}

output "latest_revision_name" {
  description = "Name of the latest revision of the container application"
  value       = azurerm_container_app.main.latest_revision_name
}

output "outbound_ip_addresses" {
  description = "Outbound IP addresses of the Container Apps environment"
  value       = azurerm_container_app_environment.main.static_ip_address
}