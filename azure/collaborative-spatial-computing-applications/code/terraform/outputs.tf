# Outputs for Azure Spatial Computing Infrastructure
# These outputs provide essential information for application integration
# and verification of deployed resources

# Resource Group Information
output "resource_group_name" {
  description = "Name of the created resource group"
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

# Azure Remote Rendering Outputs
output "remote_rendering_account_name" {
  description = "Name of the Azure Remote Rendering account"
  value       = azurerm_mixed_reality_remote_rendering_account.main.name
}

output "remote_rendering_account_id" {
  description = "Account ID for Azure Remote Rendering service authentication"
  value       = azurerm_mixed_reality_remote_rendering_account.main.account_id
}

output "remote_rendering_account_domain" {
  description = "Account domain for Azure Remote Rendering service"
  value       = azurerm_mixed_reality_remote_rendering_account.main.account_domain
}

output "remote_rendering_primary_key" {
  description = "Primary access key for Azure Remote Rendering account"
  value       = azurerm_mixed_reality_remote_rendering_account.main.primary_access_key
  sensitive   = true
}

output "remote_rendering_secondary_key" {
  description = "Secondary access key for Azure Remote Rendering account"
  value       = azurerm_mixed_reality_remote_rendering_account.main.secondary_access_key
  sensitive   = true
}

# Azure Spatial Anchors Outputs
output "spatial_anchors_account_name" {
  description = "Name of the Azure Spatial Anchors account"
  value       = azurerm_mixed_reality_spatial_anchors_account.main.name
}

output "spatial_anchors_account_id" {
  description = "Account ID for Azure Spatial Anchors service authentication"
  value       = azurerm_mixed_reality_spatial_anchors_account.main.account_id
}

output "spatial_anchors_account_domain" {
  description = "Account domain for Azure Spatial Anchors service"
  value       = azurerm_mixed_reality_spatial_anchors_account.main.account_domain
}

output "spatial_anchors_primary_key" {
  description = "Primary access key for Azure Spatial Anchors account"
  value       = azurerm_mixed_reality_spatial_anchors_account.main.primary_access_key
  sensitive   = true
}

output "spatial_anchors_secondary_key" {
  description = "Secondary access key for Azure Spatial Anchors account"
  value       = azurerm_mixed_reality_spatial_anchors_account.main.secondary_access_key
  sensitive   = true
}

# Storage Account Outputs
output "storage_account_name" {
  description = "Name of the Azure Storage account for 3D assets"
  value       = azurerm_storage_account.models.name
}

output "storage_account_id" {
  description = "ID of the Azure Storage account"
  value       = azurerm_storage_account.models.id
}

output "storage_account_primary_endpoint" {
  description = "Primary blob endpoint for the storage account"
  value       = azurerm_storage_account.models.primary_blob_endpoint
}

output "storage_account_primary_key" {
  description = "Primary access key for the storage account"
  value       = data.azurerm_storage_account.models_data.primary_access_key
  sensitive   = true
}

output "storage_account_secondary_key" {
  description = "Secondary access key for the storage account"
  value       = data.azurerm_storage_account.models_data.secondary_access_key
  sensitive   = true
}

output "blob_container_name" {
  description = "Name of the blob container for 3D models"
  value       = azurerm_storage_container.models.name
}

output "blob_container_url" {
  description = "URL of the blob container for 3D models"
  value       = "${azurerm_storage_account.models.primary_blob_endpoint}${azurerm_storage_container.models.name}"
}

# Service Principal Outputs (when created)
output "service_principal_application_id" {
  description = "Application ID of the service principal for authentication"
  value       = var.create_service_principal ? azuread_application.spatial_app[0].application_id : null
}

output "service_principal_object_id" {
  description = "Object ID of the service principal"
  value       = var.create_service_principal ? azuread_service_principal.spatial_app[0].object_id : null
}

output "service_principal_client_secret" {
  description = "Client secret for service principal authentication"
  value       = var.create_service_principal ? azuread_service_principal_password.spatial_app[0].value : null
  sensitive   = true
}

output "service_principal_tenant_id" {
  description = "Tenant ID for service principal authentication"
  value       = data.azuread_client_config.current.tenant_id
}

# Monitoring Outputs (when enabled)
output "application_insights_name" {
  description = "Name of the Application Insights instance"
  value       = var.enable_monitoring ? azurerm_application_insights.main[0].name : null
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key for Application Insights"
  value       = var.enable_monitoring ? azurerm_application_insights.main[0].instrumentation_key : null
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Connection string for Application Insights"
  value       = var.enable_monitoring ? azurerm_application_insights.main[0].connection_string : null
  sensitive   = true
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace"
  value       = var.enable_monitoring ? azurerm_log_analytics_workspace.main[0].id : null
}

output "log_analytics_workspace_key" {
  description = "Primary shared key for Log Analytics workspace"
  value       = var.enable_monitoring ? azurerm_log_analytics_workspace.main[0].primary_shared_key : null
  sensitive   = true
}

# Unity Integration Outputs
output "unity_config_path" {
  description = "Path to the generated Unity configuration file"
  value       = var.enable_unity_config_generation ? local_file.unity_config[0].filename : null
}

output "spatial_sync_config_path" {
  description = "Path to the generated spatial synchronization configuration file"
  value       = var.enable_unity_config_generation ? local_file.spatial_sync_config[0].filename : null
}

# Connection Information for Applications
output "azure_connection_info" {
  description = "Complete connection information for Azure Mixed Reality services"
  value = {
    remote_rendering = {
      account_id     = azurerm_mixed_reality_remote_rendering_account.main.account_id
      account_domain = azurerm_mixed_reality_remote_rendering_account.main.account_domain
      endpoint       = "https://${azurerm_mixed_reality_remote_rendering_account.main.account_domain}"
    }
    spatial_anchors = {
      account_id     = azurerm_mixed_reality_spatial_anchors_account.main.account_id
      account_domain = azurerm_mixed_reality_spatial_anchors_account.main.account_domain
      endpoint       = "https://${azurerm_mixed_reality_spatial_anchors_account.main.account_domain}"
    }
    storage = {
      account_name   = azurerm_storage_account.models.name
      container_name = azurerm_storage_container.models.name
      blob_endpoint  = azurerm_storage_account.models.primary_blob_endpoint
    }
    authentication = var.create_service_principal ? {
      tenant_id     = data.azuread_client_config.current.tenant_id
      client_id     = azuread_application.spatial_app[0].application_id
      # Note: client_secret is output separately as sensitive
    } : null
  }
}

# SAS Token for Storage Container (24-hour validity)
output "storage_container_sas_url" {
  description = "SAS URL for secure access to the storage container (valid for 24 hours)"
  value = format("%s%s?%s",
    azurerm_storage_account.models.primary_blob_endpoint,
    azurerm_storage_container.models.name,
    "sp=rwdl&st=${formatdate("YYYY-MM-DD'T'hh:mm:ss'Z'", timestamp())}&se=${formatdate("YYYY-MM-DD'T'hh:mm:ss'Z'", timeadd(timestamp(), "24h"))}&sv=2022-11-02&sr=c"
  )
  sensitive = true
}

# Resource Summary
output "deployment_summary" {
  description = "Summary of deployed resources"
  value = {
    resource_group_name            = azurerm_resource_group.main.name
    location                      = azurerm_resource_group.main.location
    remote_rendering_account      = azurerm_mixed_reality_remote_rendering_account.main.name
    spatial_anchors_account       = azurerm_mixed_reality_spatial_anchors_account.main.name
    storage_account              = azurerm_storage_account.models.name
    blob_container               = azurerm_storage_container.models.name
    service_principal_created    = var.create_service_principal
    monitoring_enabled           = var.enable_monitoring
    unity_config_generated       = var.enable_unity_config_generation
    estimated_monthly_cost_usd   = "15-25 per hour of active Remote Rendering sessions"
  }
}

# Important Notes and Next Steps
output "post_deployment_notes" {
  description = "Important information and next steps after deployment"
  value = {
    security_notice = "Replace placeholder keys in Unity configuration with actual account keys from outputs"
    cost_notice     = "Azure Remote Rendering charges per active session hour. Monitor usage to control costs"
    retirement_notice = "Azure Remote Rendering retires Sept 30, 2025. Azure Spatial Anchors retires Nov 20, 2024"
    unity_setup = "Import MRTK 3.0 and Azure Mixed Reality SDKs into your Unity project"
    sample_models = "Upload sample 3D models to the created blob container for testing"
    collaboration = "Configure spatial anchor sharing for multi-user scenarios"
  }
}