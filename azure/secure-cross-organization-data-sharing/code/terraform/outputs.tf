# Outputs for Azure Data Share and Service Fabric Cross-Organization Collaboration

# Resource Group Information
output "provider_resource_group_name" {
  description = "Name of the data provider resource group"
  value       = azurerm_resource_group.provider.name
}

output "consumer_resource_group_name" {
  description = "Name of the data consumer resource group"
  value       = azurerm_resource_group.consumer.name
}

output "deployment_location" {
  description = "Azure region where resources are deployed"
  value       = var.location
}

# Data Share Information
output "data_share_account_name" {
  description = "Name of the Azure Data Share account"
  value       = azurerm_data_share_account.main.name
}

output "data_share_account_id" {
  description = "Resource ID of the Azure Data Share account"
  value       = azurerm_data_share_account.main.id
}

output "data_share_name" {
  description = "Name of the created data share"
  value       = azurerm_data_share.financial_collaboration.name
}

output "data_share_description" {
  description = "Description of the created data share"
  value       = azurerm_data_share.financial_collaboration.description
}

# Service Fabric Cluster Information
output "service_fabric_cluster_name" {
  description = "Name of the Service Fabric cluster"
  value       = azurerm_service_fabric_cluster.main.name
}

output "service_fabric_management_endpoint" {
  description = "Management endpoint for the Service Fabric cluster"
  value       = azurerm_service_fabric_cluster.main.management_endpoint
}

output "service_fabric_client_endpoint" {
  description = "Client connection endpoint for the Service Fabric cluster"
  value       = "https://${azurerm_service_fabric_cluster.main.name}.${var.location}.cloudapp.azure.com:19000"
}

output "service_fabric_explorer_url" {
  description = "URL for Service Fabric Explorer"
  value       = "https://${azurerm_service_fabric_cluster.main.name}.${var.location}.cloudapp.azure.com:19080/Explorer"
}

output "service_fabric_certificate_thumbprint" {
  description = "Thumbprint of the Service Fabric cluster certificate"
  value       = azurerm_key_vault_certificate.service_fabric.thumbprint
  sensitive   = true
}

# Storage Account Information
output "provider_storage_account_name" {
  description = "Name of the data provider storage account"
  value       = azurerm_storage_account.provider.name
}

output "consumer_storage_account_name" {
  description = "Name of the data consumer storage account"
  value       = azurerm_storage_account.consumer.name
}

output "provider_storage_primary_endpoint" {
  description = "Primary blob endpoint for the provider storage account"
  value       = azurerm_storage_account.provider.primary_blob_endpoint
}

output "consumer_storage_primary_endpoint" {
  description = "Primary blob endpoint for the consumer storage account"
  value       = azurerm_storage_account.consumer.primary_blob_endpoint
}

output "shared_datasets_container_name" {
  description = "Name of the container for shared datasets"
  value       = azurerm_storage_container.shared_datasets.name
}

output "sample_data_blob_url" {
  description = "URL of the sample data blob (if created)"
  value       = var.sample_data_enabled ? "${azurerm_storage_account.provider.primary_blob_endpoint}${azurerm_storage_container.shared_datasets.name}/${azurerm_storage_blob.sample_data[0].name}" : null
}

# Key Vault Information
output "provider_key_vault_name" {
  description = "Name of the data provider Key Vault"
  value       = azurerm_key_vault.provider.name
}

output "consumer_key_vault_name" {
  description = "Name of the data consumer Key Vault"
  value       = azurerm_key_vault.consumer.name
}

output "provider_key_vault_uri" {
  description = "URI of the data provider Key Vault"
  value       = azurerm_key_vault.provider.vault_uri
}

output "consumer_key_vault_uri" {
  description = "URI of the data consumer Key Vault"
  value       = azurerm_key_vault.consumer.vault_uri
}

# Network Information
output "virtual_network_name" {
  description = "Name of the virtual network"
  value       = azurerm_virtual_network.main.name
}

output "virtual_network_id" {
  description = "Resource ID of the virtual network"
  value       = azurerm_virtual_network.main.id
}

output "service_fabric_subnet_id" {
  description = "Resource ID of the Service Fabric subnet"
  value       = azurerm_subnet.service_fabric.id
}

output "private_endpoints_subnet_id" {
  description = "Resource ID of the private endpoints subnet"
  value       = azurerm_subnet.private_endpoints.id
}

# Monitoring Information
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.name
}

output "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.id
}

output "log_analytics_workspace_key" {
  description = "Primary shared key for the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.primary_shared_key
  sensitive   = true
}

# Azure AD Application Information
output "service_fabric_cluster_application_id" {
  description = "Application ID of the Service Fabric cluster Azure AD application"
  value       = azuread_application.service_fabric_cluster.application_id
}

output "service_fabric_client_application_id" {
  description = "Application ID of the Service Fabric client Azure AD application"
  value       = azuread_application.service_fabric_client.application_id
}

# Security Information
output "data_share_managed_identity_principal_id" {
  description = "Principal ID of the Data Share account managed identity"
  value       = azurerm_data_share_account.main.identity[0].principal_id
}

output "data_share_managed_identity_tenant_id" {
  description = "Tenant ID of the Data Share account managed identity"
  value       = azurerm_data_share_account.main.identity[0].tenant_id
}

# Deployment Configuration
output "random_suffix" {
  description = "Random suffix used in resource naming"
  value       = local.resource_suffix
}

output "environment" {
  description = "Environment name"
  value       = var.environment
}

output "project_name" {
  description = "Project name"
  value       = var.project_name
}

# Connection Strings and URLs (marked as sensitive)
output "provider_storage_connection_string" {
  description = "Connection string for the provider storage account"
  value       = azurerm_storage_account.provider.primary_connection_string
  sensitive   = true
}

output "consumer_storage_connection_string" {
  description = "Connection string for the consumer storage account"
  value       = azurerm_storage_account.consumer.primary_connection_string
  sensitive   = true
}

# Dataset Information
output "sample_dataset_info" {
  description = "Information about the sample dataset"
  value = var.sample_data_enabled ? {
    enabled       = true
    blob_name     = azurerm_storage_blob.sample_data[0].name
    container     = azurerm_storage_container.shared_datasets.name
    storage_account = azurerm_storage_account.provider.name
    content_type  = azurerm_storage_blob.sample_data[0].content_type
  } : {
    enabled = false
  }
}

# Monitoring and Alerting
output "action_group_id" {
  description = "Resource ID of the monitoring action group (if created)"
  value       = var.enable_monitoring_alerts && length(var.alert_email_addresses) > 0 ? azurerm_monitor_action_group.main[0].id : null
}

# Tags Applied
output "common_tags" {
  description = "Common tags applied to all resources"
  value       = local.common_tags
}

# Resource Naming Convention
output "naming_convention" {
  description = "Naming convention used for resources"
  value = {
    provider_rg   = local.naming_convention.provider_rg
    consumer_rg   = local.naming_convention.consumer_rg
    data_share    = local.naming_convention.data_share
    sf_cluster    = local.naming_convention.sf_cluster
    kv_provider   = local.naming_convention.kv_provider
    kv_consumer   = local.naming_convention.kv_consumer
    st_provider   = local.naming_convention.st_provider
    st_consumer   = local.naming_convention.st_consumer
    log_analytics = local.naming_convention.log_analytics
    vnet          = local.naming_convention.vnet
  }
}

# Validation and Testing Information
output "validation_commands" {
  description = "Commands to validate the deployment"
  value = {
    check_data_share = "az datashare account show --account-name ${azurerm_data_share_account.main.name} --resource-group ${azurerm_resource_group.provider.name} --output table"
    check_service_fabric = "az sf cluster show --cluster-name ${azurerm_service_fabric_cluster.main.name} --resource-group ${azurerm_resource_group.provider.name} --output table"
    list_storage_blobs = "az storage blob list --container-name ${azurerm_storage_container.shared_datasets.name} --account-name ${azurerm_storage_account.provider.name} --output table"
    check_key_vault = "az keyvault secret list --vault-name ${azurerm_key_vault.provider.name} --output table"
  }
}

# Next Steps Information
output "next_steps" {
  description = "Suggested next steps after deployment"
  value = [
    "1. Connect to Service Fabric Explorer: ${azurerm_service_fabric_cluster.main.management_endpoint}/Explorer",
    "2. Deploy governance microservices to the Service Fabric cluster",
    "3. Configure data share invitations for consumer organizations",
    "4. Set up monitoring alerts and governance policies",
    "5. Test data sharing workflows with sample datasets",
    "6. Implement custom governance logic in Service Fabric applications"
  ]
}

# Security Recommendations
output "security_recommendations" {
  description = "Security recommendations for the deployment"
  value = [
    "1. Configure private endpoints for storage accounts in production",
    "2. Implement Azure AD B2B for cross-organization user access",
    "3. Set up conditional access policies for Service Fabric access",
    "4. Enable Azure Defender for Storage and Key Vault",
    "5. Configure network security groups with restrictive rules",
    "6. Implement data classification and retention policies",
    "7. Set up Azure Policy for governance automation",
    "8. Enable audit logging for all data access operations"
  ]
}