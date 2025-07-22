# Outputs for Azure Trusted Container Supply Chain Infrastructure

# Resource Group Information
output "resource_group_name" {
  description = "Name of the resource group containing all resources"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Azure region where resources are deployed"
  value       = azurerm_resource_group.main.location
}

output "resource_group_id" {
  description = "Resource ID of the resource group"
  value       = azurerm_resource_group.main.id
}

# Azure Attestation Service Information
output "attestation_provider_name" {
  description = "Name of the Azure Attestation provider"
  value       = azurerm_attestation_provider.main.name
}

output "attestation_provider_uri" {
  description = "URI of the Azure Attestation provider for API calls"
  value       = azurerm_attestation_provider.main.attestation_uri
}

output "attestation_provider_id" {
  description = "Resource ID of the Azure Attestation provider"
  value       = azurerm_attestation_provider.main.id
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

output "signing_key_name" {
  description = "Name of the container signing key in Key Vault"
  value       = azurerm_key_vault_key.container_signing.name
}

output "signing_key_id" {
  description = "Resource ID of the container signing key"
  value       = azurerm_key_vault_key.container_signing.id
}

output "signing_key_version_id" {
  description = "Versioned ID of the container signing key"
  value       = azurerm_key_vault_key.container_signing.versionless_id
}

# Azure Container Registry Information
output "container_registry_name" {
  description = "Name of the Azure Container Registry"
  value       = azurerm_container_registry.main.name
}

output "container_registry_login_server" {
  description = "Login server URL for the Container Registry"
  value       = azurerm_container_registry.main.login_server
}

output "container_registry_id" {
  description = "Resource ID of the Azure Container Registry"
  value       = azurerm_container_registry.main.id
}

output "container_registry_admin_username" {
  description = "Admin username for Container Registry (if admin is enabled)"
  value       = var.acr_admin_enabled ? azurerm_container_registry.main.admin_username : null
  sensitive   = false
}

# Note: Admin password is sensitive and should not be output
# Use Azure CLI: az acr credential show --name <registry-name> to retrieve

# Azure Image Builder Information
output "image_builder_template_name" {
  description = "Name of the Azure Image Builder template"
  value       = azurerm_image_builder_template.main.name
}

output "image_builder_template_id" {
  description = "Resource ID of the Azure Image Builder template"
  value       = azurerm_image_builder_template.main.id
}

# Managed Identity Information
output "managed_identity_name" {
  description = "Name of the managed identity used by Image Builder"
  value       = azurerm_user_assigned_identity.image_builder.name
}

output "managed_identity_id" {
  description = "Resource ID of the managed identity"
  value       = azurerm_user_assigned_identity.image_builder.id
}

output "managed_identity_principal_id" {
  description = "Principal ID of the managed identity for role assignments"
  value       = azurerm_user_assigned_identity.image_builder.principal_id
}

output "managed_identity_client_id" {
  description = "Client ID of the managed identity"
  value       = azurerm_user_assigned_identity.image_builder.client_id
}

# Shared Image Gallery Information
output "shared_image_gallery_name" {
  description = "Name of the Shared Image Gallery"
  value       = azurerm_shared_image_gallery.main.name
}

output "shared_image_gallery_id" {
  description = "Resource ID of the Shared Image Gallery"
  value       = azurerm_shared_image_gallery.main.id
}

output "shared_image_name" {
  description = "Name of the shared image definition"
  value       = azurerm_shared_image.trusted_image.name
}

output "shared_image_id" {
  description = "Resource ID of the shared image definition"
  value       = azurerm_shared_image.trusted_image.id
}

# Storage Account Information
output "storage_account_name" {
  description = "Name of the storage account for Image Builder artifacts"
  value       = azurerm_storage_account.image_builder.name
}

output "storage_account_id" {
  description = "Resource ID of the storage account"
  value       = azurerm_storage_account.image_builder.id
}

output "storage_container_name" {
  description = "Name of the storage container for image templates"
  value       = azurerm_storage_container.image_templates.name
}

# Log Analytics Workspace Information (if enabled)
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace (if diagnostic settings enabled)"
  value       = var.enable_diagnostic_settings ? azurerm_log_analytics_workspace.main[0].name : null
}

output "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics workspace (if diagnostic settings enabled)"
  value       = var.enable_diagnostic_settings ? azurerm_log_analytics_workspace.main[0].id : null
}

output "log_analytics_workspace_workspace_id" {
  description = "Workspace ID of the Log Analytics workspace for agent configuration"
  value       = var.enable_diagnostic_settings ? azurerm_log_analytics_workspace.main[0].workspace_id : null
}

# Virtual Network Information (if created)
output "virtual_network_name" {
  description = "Name of the virtual network (if created)"
  value       = var.create_virtual_network ? azurerm_virtual_network.main[0].name : null
}

output "virtual_network_id" {
  description = "Resource ID of the virtual network (if created)"
  value       = var.create_virtual_network ? azurerm_virtual_network.main[0].id : null
}

output "image_builder_subnet_id" {
  description = "Resource ID of the Image Builder subnet (if VNet created)"
  value       = var.create_virtual_network ? azurerm_subnet.image_builder[0].id : null
}

output "container_registry_subnet_id" {
  description = "Resource ID of the Container Registry subnet (if VNet created)"
  value       = var.create_virtual_network ? azurerm_subnet.container_registry[0].id : null
}

# Deployment Information
output "deployment_timestamp" {
  description = "Timestamp when the infrastructure was deployed"
  value       = timestamp()
}

output "terraform_version" {
  description = "Version of Terraform used for deployment"
  value       = "1.5.0+"
}

# Security and Access Information
output "key_vault_rbac_enabled" {
  description = "Whether RBAC authorization is enabled for Key Vault"
  value       = azurerm_key_vault.main.enable_rbac_authorization
}

output "container_registry_trust_policy_enabled" {
  description = "Whether trust policy (content trust) is enabled for Container Registry"
  value       = var.acr_sku == "Premium" && var.acr_trust_policy_enabled
}

output "container_registry_quarantine_policy_enabled" {
  description = "Whether quarantine policy is enabled for Container Registry"
  value       = var.acr_sku == "Premium" && var.acr_quarantine_policy_enabled
}

# Usage Instructions and Next Steps
output "next_steps" {
  description = "Instructions for using the deployed infrastructure"
  value = {
    "1_trigger_image_build" = "az resource invoke-action --resource-group ${azurerm_resource_group.main.name} --resource-type Microsoft.VirtualMachineImages/imageTemplates --name ${azurerm_image_builder_template.main.name} --api-version 2024-02-01 --action Run"
    "2_monitor_build_status" = "az resource show --resource-group ${azurerm_resource_group.main.name} --resource-type Microsoft.VirtualMachineImages/imageTemplates --name ${azurerm_image_builder_template.main.name} --api-version 2024-02-01 --query 'properties.lastRunStatus.runState'"
    "3_access_attestation_service" = "Use attestation URI: ${azurerm_attestation_provider.main.attestation_uri}"
    "4_container_registry_login" = "az acr login --name ${azurerm_container_registry.main.name}"
    "5_view_built_image" = "Check Shared Image Gallery: ${azurerm_shared_image_gallery.main.name}"
  }
}

# Configuration Summary
output "configuration_summary" {
  description = "Summary of key configuration settings"
  value = {
    environment                        = var.environment
    location                          = var.location
    key_vault_sku                     = var.key_vault_sku
    container_registry_sku            = var.acr_sku
    image_builder_vm_size             = var.image_builder_vm_size
    signing_key_type                  = var.signing_key_type
    diagnostic_settings_enabled       = var.enable_diagnostic_settings
    virtual_network_created           = var.create_virtual_network
    content_trust_enabled             = var.acr_sku == "Premium" && var.acr_trust_policy_enabled
    quarantine_policy_enabled         = var.acr_sku == "Premium" && var.acr_quarantine_policy_enabled
  }
}

# Connection Strings and Access Points
output "connection_information" {
  description = "Connection information for applications and services"
  value = {
    attestation_endpoint     = azurerm_attestation_provider.main.attestation_uri
    key_vault_url           = azurerm_key_vault.main.vault_uri
    container_registry_url  = "https://${azurerm_container_registry.main.login_server}"
    shared_image_gallery_id = azurerm_shared_image_gallery.main.id
  }
  sensitive = false
}

# Cost Management Information
output "cost_management_tags" {
  description = "Tags applied to resources for cost tracking"
  value = {
    project     = var.project_name
    environment = var.environment
    managed_by  = "Terraform"
  }
}

# Security Contact Information
output "security_recommendations" {
  description = "Security recommendations for the deployed infrastructure"
  value = {
    "key_vault_access" = "Review and regularly rotate signing keys"
    "container_registry" = "Enable vulnerability scanning in Azure Security Center"
    "attestation_policies" = "Regularly review and update attestation policies"
    "network_security" = var.create_virtual_network ? "Network security groups are configured" : "Consider implementing virtual network for enhanced security"
    "monitoring" = var.enable_diagnostic_settings ? "Diagnostic settings are enabled" : "Consider enabling diagnostic settings for monitoring"
  }
}