# Azure Container Registry and Container Instances Terraform Outputs
# This file defines all output values that will be displayed after deployment
# Outputs provide important information for accessing and managing the deployed resources

# Resource Group Information
output "resource_group_name" {
  description = "Name of the created Azure Resource Group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Azure region where the resource group was created"
  value       = azurerm_resource_group.main.location
}

output "resource_group_id" {
  description = "Azure Resource Manager ID of the resource group"
  value       = azurerm_resource_group.main.id
}

# Azure Container Registry Outputs
output "container_registry_name" {
  description = "Name of the Azure Container Registry"
  value       = azurerm_container_registry.acr.name
}

output "container_registry_login_server" {
  description = "Login server URL for the Azure Container Registry"
  value       = azurerm_container_registry.acr.login_server
}

output "container_registry_admin_username" {
  description = "Admin username for the Azure Container Registry"
  value       = azurerm_container_registry.acr.admin_username
  sensitive   = true
}

output "container_registry_admin_password" {
  description = "Admin password for the Azure Container Registry"
  value       = azurerm_container_registry.acr.admin_password
  sensitive   = true
}

output "container_registry_id" {
  description = "Azure Resource Manager ID of the container registry"
  value       = azurerm_container_registry.acr.id
}

output "container_registry_sku" {
  description = "SKU tier of the Azure Container Registry"
  value       = azurerm_container_registry.acr.sku
}

# Azure Container Instance Outputs
output "container_instance_name" {
  description = "Name of the Azure Container Instance"
  value       = azurerm_container_group.aci.name
}

output "container_instance_id" {
  description = "Azure Resource Manager ID of the container instance"
  value       = azurerm_container_group.aci.id
}

output "container_ip_address" {
  description = "Public IP address assigned to the container instance"
  value       = azurerm_container_group.aci.ip_address
}

output "container_fqdn" {
  description = "Fully Qualified Domain Name (FQDN) of the container instance"
  value       = azurerm_container_group.aci.fqdn
}

# Application Access Information
output "application_url" {
  description = "Complete URL to access the deployed web application"
  value       = azurerm_container_group.aci.ip_address != null ? "http://${azurerm_container_group.aci.ip_address}:${var.container_port}" : null
}

output "application_fqdn_url" {
  description = "Complete URL using FQDN to access the deployed web application"
  value       = azurerm_container_group.aci.fqdn != null ? "http://${azurerm_container_group.aci.fqdn}:${var.container_port}" : null
}

# Container Configuration
output "container_image" {
  description = "Full container image reference used in the deployment"
  value       = local.container_image_full
}

output "container_cpu" {
  description = "CPU cores allocated to the container"
  value       = var.container_cpu
}

output "container_memory" {
  description = "Memory in GB allocated to the container"
  value       = var.container_memory
}

output "container_port" {
  description = "Port number exposed by the container"
  value       = var.container_port
}

output "container_protocol" {
  description = "Network protocol used by the container port"
  value       = var.container_protocol
}

# Deployment Information
output "deployment_environment" {
  description = "Environment tag applied to the deployment"
  value       = var.environment
}

output "deployment_tags" {
  description = "All tags applied to the deployed resources"
  value       = local.common_tags
}

output "random_suffix" {
  description = "Random suffix used for unique resource naming (if enabled)"
  value       = var.use_random_suffix ? random_string.suffix[0].result : null
}

# Azure Configuration Context
output "azure_subscription_id" {
  description = "Azure subscription ID where resources were deployed"
  value       = data.azurerm_client_config.current.subscription_id
}

output "azure_tenant_id" {
  description = "Azure tenant ID of the deployment context"
  value       = data.azurerm_client_config.current.tenant_id
}

# Container Registry Identity Information
output "container_registry_identity_principal_id" {
  description = "Principal ID of the Container Registry's system-assigned managed identity"
  value       = try(azurerm_container_registry.acr.identity[0].principal_id, null)
}

output "container_registry_identity_tenant_id" {
  description = "Tenant ID of the Container Registry's system-assigned managed identity"
  value       = try(azurerm_container_registry.acr.identity[0].tenant_id, null)
}

# Quick Reference Commands
output "docker_login_command" {
  description = "Command to login to the container registry using Docker CLI"
  value       = "az acr login --name ${azurerm_container_registry.acr.name}"
}

output "docker_build_command" {
  description = "Sample command to build and tag a container image for this registry"
  value       = "docker build -t ${azurerm_container_registry.acr.login_server}/${var.container_image}:${var.container_image_tag} ."
}

output "docker_push_command" {
  description = "Command to push the container image to the registry"
  value       = "docker push ${azurerm_container_registry.acr.login_server}/${var.container_image}:${var.container_image_tag}"
}

# Resource Status and Health
output "container_state" {
  description = "Current state of the container instance"
  value       = azurerm_container_group.aci.id != null ? "Deployed" : "Unknown"
}

output "deployment_summary" {
  description = "Summary of the deployed infrastructure"
  value = {
    resource_group          = azurerm_resource_group.main.name
    location               = azurerm_resource_group.main.location
    container_registry     = azurerm_container_registry.acr.name
    registry_login_server  = azurerm_container_registry.acr.login_server 
    container_instance     = azurerm_container_group.aci.name
    public_ip             = azurerm_container_group.aci.ip_address
    fqdn                  = azurerm_container_group.aci.fqdn
    application_url       = azurerm_container_group.aci.ip_address != null ? "http://${azurerm_container_group.aci.ip_address}:${var.container_port}" : null
    container_image       = local.container_image_full
    environment          = var.environment
  }
}