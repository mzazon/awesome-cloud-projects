# Resource Group outputs
output "resource_group_name" {
  description = "Name of the resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Location of the resource group"
  value       = azurerm_resource_group.main.location
}

output "resource_group_id" {
  description = "ID of the resource group"
  value       = azurerm_resource_group.main.id
}

# DevCenter outputs
output "devcenter_name" {
  description = "Name of the Azure DevCenter"
  value       = azurerm_dev_center.main.name
}

output "devcenter_id" {
  description = "ID of the Azure DevCenter"
  value       = azurerm_dev_center.main.id
}

output "devcenter_uri" {
  description = "URI of the Azure DevCenter"
  value       = azurerm_dev_center.main.dev_center_uri
}

output "devcenter_managed_identity_principal_id" {
  description = "Principal ID of the DevCenter managed identity"
  value       = azurerm_dev_center.main.identity[0].principal_id
}

output "devcenter_managed_identity_tenant_id" {
  description = "Tenant ID of the DevCenter managed identity"
  value       = azurerm_dev_center.main.identity[0].tenant_id
}

# Project outputs
output "project_name" {
  description = "Name of the DevCenter project"
  value       = azurerm_dev_center_project.main.name
}

output "project_id" {
  description = "ID of the DevCenter project"
  value       = azurerm_dev_center_project.main.id
}

output "project_uri" {
  description = "URI of the DevCenter project"
  value       = azurerm_dev_center_project.main.dev_center_project_uri
}

output "project_description" {
  description = "Description of the DevCenter project"
  value       = azurerm_dev_center_project.main.description
}

# Dev Box outputs
output "devbox_definition_name" {
  description = "Name of the Dev Box definition"
  value       = azurerm_dev_center_dev_box_definition.main.name
}

output "devbox_definition_id" {
  description = "ID of the Dev Box definition"
  value       = azurerm_dev_center_dev_box_definition.main.id
}

output "devbox_pool_name" {
  description = "Name of the Dev Box pool"
  value       = azurerm_dev_center_dev_box_pool.main.name
}

output "devbox_pool_id" {
  description = "ID of the Dev Box pool"
  value       = azurerm_dev_center_dev_box_pool.main.id
}

output "devbox_sku_name" {
  description = "SKU name used for Dev Boxes"
  value       = azurerm_dev_center_dev_box_definition.main.sku_name
}

output "devbox_hibernate_support" {
  description = "Hibernation support setting for Dev Boxes"
  value       = azurerm_dev_center_dev_box_definition.main.hibernate_support
}

output "devbox_local_admin_enabled" {
  description = "Local administrator setting for Dev Boxes"
  value       = azurerm_dev_center_dev_box_pool.main.local_administrator_enabled
}

# Schedule outputs
output "auto_stop_schedule_name" {
  description = "Name of the auto-stop schedule"
  value       = azurerm_dev_center_dev_box_pool_schedule.auto_stop.name
}

output "auto_stop_schedule_id" {
  description = "ID of the auto-stop schedule"
  value       = azurerm_dev_center_dev_box_pool_schedule.auto_stop.id
}

output "auto_stop_time" {
  description = "Auto-stop time for Dev Boxes"
  value       = azurerm_dev_center_dev_box_pool_schedule.auto_stop.time
}

output "auto_stop_timezone" {
  description = "Timezone for auto-stop schedule"
  value       = azurerm_dev_center_dev_box_pool_schedule.auto_stop.time_zone
}

# Environment type outputs
output "environment_types" {
  description = "List of created environment types"
  value       = [for et in azurerm_dev_center_environment_type.main : et.name]
}

output "environment_type_ids" {
  description = "Map of environment type names to IDs"
  value       = { for et in azurerm_dev_center_environment_type.main : et.name => et.id }
}

output "project_environment_types" {
  description = "List of project environment types"
  value       = [for pet in azurerm_dev_center_project_environment_type.main : pet.name]
}

output "project_environment_type_ids" {
  description = "Map of project environment type names to IDs"
  value       = { for pet in azurerm_dev_center_project_environment_type.main : pet.name => pet.id }
}

# Catalog outputs
output "catalog_name" {
  description = "Name of the DevCenter catalog"
  value       = azurerm_dev_center_catalog.quickstart.name
}

output "catalog_id" {
  description = "ID of the DevCenter catalog"
  value       = azurerm_dev_center_catalog.quickstart.id
}

output "catalog_repo_url" {
  description = "Repository URL of the catalog"
  value       = var.catalog_repo_url
}

output "catalog_branch" {
  description = "Branch of the catalog repository"
  value       = var.catalog_branch
}

output "catalog_path" {
  description = "Path within the catalog repository"
  value       = var.catalog_path
}

# Network outputs
output "virtual_network_name" {
  description = "Name of the virtual network"
  value       = azurerm_virtual_network.devbox_vnet.name
}

output "virtual_network_id" {
  description = "ID of the virtual network"
  value       = azurerm_virtual_network.devbox_vnet.id
}

output "subnet_name" {
  description = "Name of the Dev Box subnet"
  value       = azurerm_subnet.devbox_subnet.name
}

output "subnet_id" {
  description = "ID of the Dev Box subnet"
  value       = azurerm_subnet.devbox_subnet.id
}

output "network_connection_name" {
  description = "Name of the network connection"
  value       = azurerm_dev_center_network_connection.main.name
}

output "network_connection_id" {
  description = "ID of the network connection"
  value       = azurerm_dev_center_network_connection.main.id
}

# Access information outputs
output "developer_portal_url" {
  description = "URL for the developer portal"
  value       = "https://devportal.microsoft.com"
}

output "developer_access_instructions" {
  description = "Instructions for developer access"
  value       = <<-EOF
    Developers can access their self-service infrastructure at:
    
    Developer Portal: https://devportal.microsoft.com
    Project Name: ${azurerm_dev_center_project.main.name}
    
    Available actions:
    - Create and manage Dev Boxes
    - Deploy environment templates
    - Access development tools and resources
    
    Dev Box Configuration:
    - SKU: ${azurerm_dev_center_dev_box_definition.main.sku_name}
    - Auto-stop: ${azurerm_dev_center_dev_box_pool_schedule.auto_stop.time} (${azurerm_dev_center_dev_box_pool_schedule.auto_stop.time_zone})
    - Local Admin: ${azurerm_dev_center_dev_box_pool.main.local_administrator_enabled ? "Enabled" : "Disabled"}
    - Hibernation: ${azurerm_dev_center_dev_box_definition.main.hibernate_support}
  EOF
}

# Subscription and tenant information
output "subscription_id" {
  description = "Azure subscription ID"
  value       = data.azurerm_client_config.current.subscription_id
}

output "tenant_id" {
  description = "Azure tenant ID"
  value       = data.azurerm_client_config.current.tenant_id
}

output "current_user_object_id" {
  description = "Object ID of the current user"
  value       = data.azuread_user.current.object_id
}

# Cost and management information
output "cost_estimation_note" {
  description = "Cost estimation information"
  value       = <<-EOF
    Cost Estimation:
    - Dev Boxes: $5-10/hour when running (automatically stopped at ${azurerm_dev_center_dev_box_pool_schedule.auto_stop.time})
    - Deployment Environments: Usage-based pricing for deployed resources
    - Storage: Additional charges for Dev Box storage and snapshots
    
    Cost Optimization:
    - Auto-stop schedule configured for ${azurerm_dev_center_dev_box_pool_schedule.auto_stop.time}
    - Hibernation enabled: ${azurerm_dev_center_dev_box_definition.main.hibernate_support}
    - Monitor usage through Azure Cost Management
  EOF
}

# Tags applied to resources
output "resource_tags" {
  description = "Common tags applied to resources"
  value       = local.common_tags
}

# Random suffix used (if enabled)
output "resource_suffix" {
  description = "Random suffix used for resource names"
  value       = local.suffix
  sensitive   = false
}