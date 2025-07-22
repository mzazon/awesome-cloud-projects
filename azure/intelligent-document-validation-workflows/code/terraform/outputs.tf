# Output values for Azure document validation workflow infrastructure
# These outputs provide essential information for integration, monitoring,
# and post-deployment configuration of the document processing solution

# Resource group information
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Location of the resource group"
  value       = azurerm_resource_group.main.location
}

output "resource_group_id" {
  description = "Resource ID of the created resource group"
  value       = azurerm_resource_group.main.id
}

# Azure AI Document Intelligence outputs
output "document_intelligence_name" {
  description = "Name of the Azure AI Document Intelligence service"
  value       = azurerm_cognitive_account.document_intelligence.name
}

output "document_intelligence_endpoint" {
  description = "Endpoint URL for Azure AI Document Intelligence service"
  value       = azurerm_cognitive_account.document_intelligence.endpoint
}

output "document_intelligence_id" {
  description = "Resource ID of the Document Intelligence service"
  value       = azurerm_cognitive_account.document_intelligence.id
}

output "document_intelligence_custom_subdomain" {
  description = "Custom subdomain for Document Intelligence service"
  value       = azurerm_cognitive_account.document_intelligence.custom_subdomain_name
}

# Storage account outputs
output "storage_account_name" {
  description = "Name of the storage account for document processing"
  value       = azurerm_storage_account.main.name
}

output "storage_account_id" {
  description = "Resource ID of the storage account"
  value       = azurerm_storage_account.main.id
}

output "storage_account_primary_blob_endpoint" {
  description = "Primary blob endpoint for the storage account"
  value       = azurerm_storage_account.main.primary_blob_endpoint
}

output "storage_containers" {
  description = "List of created storage containers"
  value       = [for container in azurerm_storage_container.containers : container.name]
}

output "storage_account_primary_web_endpoint" {
  description = "Primary web endpoint for static website hosting"
  value       = azurerm_storage_account.main.primary_web_endpoint
}

# Key Vault outputs
output "key_vault_name" {
  description = "Name of the Key Vault for secure credential storage"
  value       = azurerm_key_vault.main.name
}

output "key_vault_id" {
  description = "Resource ID of the Key Vault"
  value       = azurerm_key_vault.main.id
}

output "key_vault_uri" {
  description = "URI of the Key Vault"
  value       = azurerm_key_vault.main.vault_uri
}

# Logic Apps outputs
output "logic_app_name" {
  description = "Name of the Logic Apps Standard instance"
  value       = azurerm_logic_app_standard.main.name
}

output "logic_app_id" {
  description = "Resource ID of the Logic Apps Standard instance"
  value       = azurerm_logic_app_standard.main.id
}

output "logic_app_default_hostname" {
  description = "Default hostname for the Logic Apps Standard instance"
  value       = azurerm_logic_app_standard.main.default_hostname
}

output "logic_app_managed_identity_principal_id" {
  description = "Principal ID of the Logic Apps managed identity"
  value       = azurerm_logic_app_standard.main.identity[0].principal_id
}

output "logic_app_managed_identity_tenant_id" {
  description = "Tenant ID of the Logic Apps managed identity"
  value       = azurerm_logic_app_standard.main.identity[0].tenant_id
}

# App Service Plan outputs
output "app_service_plan_name" {
  description = "Name of the App Service Plan for Logic Apps"
  value       = azurerm_service_plan.logic_apps.name
}

output "app_service_plan_id" {
  description = "Resource ID of the App Service Plan"
  value       = azurerm_service_plan.logic_apps.id
}

output "app_service_plan_sku" {
  description = "SKU of the App Service Plan"
  value       = azurerm_service_plan.logic_apps.sku_name
}

# Monitoring and logging outputs
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.name
}

output "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.id
}

output "log_analytics_workspace_primary_shared_key" {
  description = "Primary shared key for Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.primary_shared_key
  sensitive   = true
}

output "application_insights_name" {
  description = "Name of the Application Insights instance"
  value       = azurerm_application_insights.main.name
}

output "application_insights_id" {
  description = "Resource ID of the Application Insights instance"
  value       = azurerm_application_insights.main.id
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key for Application Insights"
  value       = azurerm_application_insights.main.instrumentation_key
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Connection string for Application Insights"
  value       = azurerm_application_insights.main.connection_string
  sensitive   = true
}

# Security and access outputs
output "allowed_ip_ranges" {
  description = "List of IP ranges allowed to access resources"
  value       = var.allowed_ip_ranges
}

output "private_endpoints_enabled" {
  description = "Whether private endpoints are enabled"
  value       = var.enable_private_endpoints
}

# Virtual network outputs (if private endpoints are enabled)
output "virtual_network_name" {
  description = "Name of the virtual network (if private endpoints enabled)"
  value       = var.enable_private_endpoints ? azurerm_virtual_network.main[0].name : null
}

output "virtual_network_id" {
  description = "Resource ID of the virtual network (if private endpoints enabled)"
  value       = var.enable_private_endpoints ? azurerm_virtual_network.main[0].id : null
}

output "subnet_ids" {
  description = "Map of subnet names to their resource IDs (if private endpoints enabled)"
  value       = var.enable_private_endpoints ? { for k, v in azurerm_subnet.private_endpoints : k => v.id } : {}
}

# Private endpoint outputs (if enabled)
output "private_endpoint_storage_id" {
  description = "Resource ID of the storage account private endpoint"
  value       = var.enable_private_endpoints ? azurerm_private_endpoint.storage[0].id : null
}

output "private_endpoint_key_vault_id" {
  description = "Resource ID of the Key Vault private endpoint"
  value       = var.enable_private_endpoints ? azurerm_private_endpoint.key_vault[0].id : null
}

output "private_endpoint_cognitive_id" {
  description = "Resource ID of the Cognitive Services private endpoint"
  value       = var.enable_private_endpoints ? azurerm_private_endpoint.cognitive[0].id : null
}

# Monitoring and alerting outputs
output "action_group_name" {
  description = "Name of the monitoring action group"
  value       = azurerm_monitor_action_group.main.name
}

output "action_group_id" {
  description = "Resource ID of the monitoring action group"
  value       = azurerm_monitor_action_group.main.id
}

output "document_intelligence_alert_id" {
  description = "Resource ID of the Document Intelligence failure alert"
  value       = azurerm_monitor_metric_alert.document_intelligence_failures.id
}

output "logic_apps_alert_id" {
  description = "Resource ID of the Logic Apps failure alert"
  value       = azurerm_monitor_metric_alert.logic_apps_failures.id
}

# Configuration and validation outputs
output "document_validation_rules" {
  description = "Document validation rules configuration"
  value       = var.document_validation_rules
}

output "environment" {
  description = "Environment designation for the deployment"
  value       = var.environment
}

output "project_name" {
  description = "Project name used for resource naming"
  value       = var.project_name
}

# Integration endpoints and connection information
output "sharepoint_integration_ready" {
  description = "Whether the infrastructure is ready for SharePoint integration"
  value       = true
}

output "power_platform_connection_info" {
  description = "Information needed for Power Platform connections"
  value = {
    storage_account_name = azurerm_storage_account.main.name
    key_vault_name      = azurerm_key_vault.main.name
    logic_app_name      = azurerm_logic_app_standard.main.name
    resource_group_name = azurerm_resource_group.main.name
  }
}

# Dataverse environment configuration (for manual setup)
output "dataverse_configuration" {
  description = "Configuration information for Dataverse environment setup"
  value = {
    display_name    = var.power_platform_environment_display_name
    environment_type = var.power_platform_environment_type
    language_code   = var.dataverse_language_code
    currency_code   = var.dataverse_currency_code
    location        = var.location
  }
}

# Security credentials (for secure integration setup)
output "integration_credentials" {
  description = "Key Vault secret names for integration credentials"
  value = {
    document_intelligence_endpoint = azurerm_key_vault_secret.document_intelligence_endpoint.name
    document_intelligence_key     = azurerm_key_vault_secret.document_intelligence_key.name
    storage_connection_string     = azurerm_key_vault_secret.storage_connection_string.name
  }
}

# Resource naming convention outputs
output "resource_naming_convention" {
  description = "Resource naming convention used in this deployment"
  value = {
    prefix = local.resource_prefix
    suffix = local.resource_suffix
    pattern = "${var.project_name}-${var.environment}-{resource-type}-${local.resource_suffix}"
  }
}

# Tags applied to resources
output "common_tags" {
  description = "Common tags applied to all resources"
  value       = local.common_tags
}

# Deployment summary
output "deployment_summary" {
  description = "Summary of deployed resources and their purposes"
  value = {
    "Azure AI Document Intelligence" = "Intelligent document processing and data extraction"
    "Logic Apps Standard"           = "Workflow orchestration and automation"
    "Storage Account"              = "Document storage and Logic Apps runtime"
    "Key Vault"                    = "Secure credential and secret management"
    "Log Analytics Workspace"      = "Centralized logging and monitoring"
    "Application Insights"         = "Application performance monitoring"
    "Action Group"                 = "Alert notifications and incident response"
    "Private Endpoints"            = var.enable_private_endpoints ? "Secure network connectivity" : "Not configured"
  }
}

# Post-deployment instructions
output "next_steps" {
  description = "Instructions for completing the solution setup"
  value = [
    "1. Set up Power Platform environment for Dataverse in the Power Platform Admin Center",
    "2. Create custom tables in Dataverse for document validation records",
    "3. Configure Logic Apps workflows using the Azure portal",
    "4. Build Power Apps interface for document validation and approval",
    "5. Set up SharePoint document library and configure trigger connections",
    "6. Test end-to-end document processing workflow",
    "7. Configure additional business rules and approval processes as needed",
    "8. Set up backup and disaster recovery procedures",
    "9. Review and adjust monitoring alerts based on operational requirements",
    "10. Document operational procedures and train end users"
  ]
}

# Cost optimization recommendations
output "cost_optimization_tips" {
  description = "Recommendations for optimizing costs"
  value = [
    "Monitor Document Intelligence usage and consider F0 tier for development",
    "Review Log Analytics retention settings and adjust based on compliance requirements",
    "Use storage lifecycle policies to move older documents to cheaper tiers",
    "Monitor Logic Apps execution frequency and optimize workflows",
    "Consider scaling down non-production environments during off-hours",
    "Review and remove unused storage containers and blobs regularly",
    "Use Azure Cost Management to set up budget alerts and spending limits"
  ]
}