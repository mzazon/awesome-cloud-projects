# Output Values for User Onboarding Workflow Infrastructure
# This file defines the output values that will be displayed after deployment
# and can be used by other Terraform configurations or automation scripts

# Resource Group Information
output "resource_group_name" {
  description = "Name of the resource group containing all resources"
  value       = azurerm_resource_group.main.name
}

output "resource_group_id" {
  description = "ID of the resource group containing all resources"
  value       = azurerm_resource_group.main.id
}

output "resource_group_location" {
  description = "Location of the resource group"
  value       = azurerm_resource_group.main.location
}

# Key Vault Information
output "key_vault_name" {
  description = "Name of the Key Vault for secure credential storage"
  value       = azurerm_key_vault.main.name
}

output "key_vault_id" {
  description = "ID of the Key Vault"
  value       = azurerm_key_vault.main.id
}

output "key_vault_uri" {
  description = "URI of the Key Vault"
  value       = azurerm_key_vault.main.vault_uri
}

output "key_vault_tenant_id" {
  description = "Tenant ID associated with the Key Vault"
  value       = azurerm_key_vault.main.tenant_id
}

# Service Bus Information
output "service_bus_namespace_name" {
  description = "Name of the Service Bus namespace"
  value       = azurerm_servicebus_namespace.main.name
}

output "service_bus_namespace_id" {
  description = "ID of the Service Bus namespace"
  value       = azurerm_servicebus_namespace.main.id
}

output "service_bus_namespace_endpoint" {
  description = "Endpoint of the Service Bus namespace"
  value       = azurerm_servicebus_namespace.main.endpoint
}

output "service_bus_namespace_sku" {
  description = "SKU of the Service Bus namespace"
  value       = azurerm_servicebus_namespace.main.sku
}

# Service Bus Queue Information
output "service_bus_queue_name" {
  description = "Name of the Service Bus queue for user onboarding messages"
  value       = azurerm_servicebus_queue.onboarding.name
}

output "service_bus_queue_id" {
  description = "ID of the Service Bus queue"
  value       = azurerm_servicebus_queue.onboarding.id
}

# Service Bus Topic Information
output "service_bus_topic_name" {
  description = "Name of the Service Bus topic for onboarding events"
  value       = azurerm_servicebus_topic.onboarding_events.name
}

output "service_bus_topic_id" {
  description = "ID of the Service Bus topic"
  value       = azurerm_servicebus_topic.onboarding_events.id
}

# Storage Account Information
output "storage_account_name" {
  description = "Name of the storage account for Logic Apps"
  value       = azurerm_storage_account.logic_apps.name
}

output "storage_account_id" {
  description = "ID of the storage account"
  value       = azurerm_storage_account.logic_apps.id
}

output "storage_account_primary_endpoint" {
  description = "Primary endpoint of the storage account"
  value       = azurerm_storage_account.logic_apps.primary_blob_endpoint
}

output "storage_account_tier" {
  description = "Performance tier of the storage account"
  value       = azurerm_storage_account.logic_apps.account_tier
}

# Logic Apps Information
output "logic_app_name" {
  description = "Name of the Logic Apps workflow"
  value       = azurerm_logic_app_standard.main.name
}

output "logic_app_id" {
  description = "ID of the Logic Apps workflow"
  value       = azurerm_logic_app_standard.main.id
}

output "logic_app_default_hostname" {
  description = "Default hostname of the Logic Apps workflow"
  value       = azurerm_logic_app_standard.main.default_hostname
}

output "logic_app_identity_principal_id" {
  description = "Principal ID of the Logic Apps managed identity"
  value       = azurerm_logic_app_standard.main.identity[0].principal_id
}

output "logic_app_identity_tenant_id" {
  description = "Tenant ID of the Logic Apps managed identity"
  value       = azurerm_logic_app_standard.main.identity[0].tenant_id
}

# App Service Plan Information
output "app_service_plan_name" {
  description = "Name of the App Service Plan for Logic Apps"
  value       = azurerm_service_plan.logic_apps.name
}

output "app_service_plan_id" {
  description = "ID of the App Service Plan"
  value       = azurerm_service_plan.logic_apps.id
}

output "app_service_plan_sku" {
  description = "SKU of the App Service Plan"
  value       = azurerm_service_plan.logic_apps.sku_name
}

# Azure AD Application Information
output "ad_application_id" {
  description = "Application ID of the Azure AD application"
  value       = azuread_application.onboarding.application_id
}

output "ad_application_object_id" {
  description = "Object ID of the Azure AD application"
  value       = azuread_application.onboarding.object_id
}

output "ad_application_display_name" {
  description = "Display name of the Azure AD application"
  value       = azuread_application.onboarding.display_name
}

output "ad_service_principal_id" {
  description = "Object ID of the service principal"
  value       = azuread_service_principal.onboarding.object_id
}

output "ad_service_principal_application_id" {
  description = "Application ID of the service principal"
  value       = azuread_service_principal.onboarding.application_id
}

# Security Information
output "rbac_authorization_enabled" {
  description = "Whether RBAC authorization is enabled for Key Vault"
  value       = var.enable_rbac_authorization
}

output "https_only_enabled" {
  description = "Whether HTTPS-only access is enabled for storage account"
  value       = var.enable_https_only
}

output "diagnostic_logs_enabled" {
  description = "Whether diagnostic logs are enabled for resources"
  value       = var.enable_diagnostic_logs
}

# Monitoring Information
output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace (if enabled)"
  value       = var.enable_diagnostic_logs ? azurerm_log_analytics_workspace.main[0].id : null
}

output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace (if enabled)"
  value       = var.enable_diagnostic_logs ? azurerm_log_analytics_workspace.main[0].name : null
}

output "application_insights_name" {
  description = "Name of the Application Insights instance"
  value       = azurerm_application_insights.main.name
}

output "application_insights_id" {
  description = "ID of the Application Insights instance"
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

# Configuration Information
output "environment" {
  description = "Environment name for the deployment"
  value       = var.environment
}

output "project_name" {
  description = "Project name used for resource naming"
  value       = var.project_name
}

output "resource_suffix" {
  description = "Random suffix used for resource naming"
  value       = local.resource_suffix
}

# Network and Security Configuration
output "allowed_ip_ranges" {
  description = "List of IP ranges allowed to access resources"
  value       = var.allowed_ip_ranges
}

output "private_endpoint_enabled" {
  description = "Whether private endpoints are enabled for supported resources"
  value       = var.enable_private_endpoint
}

# Backup and Retention Configuration
output "backup_retention_days" {
  description = "Number of days to retain backups"
  value       = var.backup_retention_days
}

output "log_retention_days" {
  description = "Number of days to retain diagnostic logs"
  value       = var.log_retention_days
}

output "key_vault_soft_delete_retention_days" {
  description = "Number of days to retain soft-deleted Key Vault items"
  value       = var.key_vault_soft_delete_retention_days
}

# Cost Optimization Information
output "auto_shutdown_enabled" {
  description = "Whether auto-shutdown is enabled for development environments"
  value       = var.auto_shutdown_enabled
}

output "auto_shutdown_time" {
  description = "Auto-shutdown time for development environments"
  value       = var.auto_shutdown_time
}

# Key Vault Secrets (Names Only - Values are Sensitive)
output "key_vault_secret_names" {
  description = "List of secret names stored in Key Vault"
  value = [
    azurerm_key_vault_secret.service_bus_connection.name,
    azurerm_key_vault_secret.app_client_id.name,
    azurerm_key_vault_secret.app_client_secret.name
  ]
}

# Service Bus Authorization Rule Information
output "service_bus_authorization_rule_name" {
  description = "Name of the Service Bus authorization rule for Logic Apps"
  value       = azurerm_servicebus_namespace_authorization_rule.logic_apps.name
}

output "service_bus_authorization_rule_id" {
  description = "ID of the Service Bus authorization rule"
  value       = azurerm_servicebus_namespace_authorization_rule.logic_apps.id
}

# Resource Tags
output "common_tags" {
  description = "Common tags applied to all resources"
  value       = local.common_tags
}

# Current Azure Configuration
output "current_tenant_id" {
  description = "Current Azure tenant ID"
  value       = data.azurerm_client_config.current.tenant_id
}

output "current_client_id" {
  description = "Current Azure client ID"
  value       = data.azurerm_client_config.current.client_id
}

output "current_subscription_id" {
  description = "Current Azure subscription ID"
  value       = data.azurerm_client_config.current.subscription_id
}

# Deployment Information
output "deployment_summary" {
  description = "Summary of deployed resources"
  value = {
    resource_group    = azurerm_resource_group.main.name
    key_vault        = azurerm_key_vault.main.name
    service_bus      = azurerm_servicebus_namespace.main.name
    logic_app        = azurerm_logic_app_standard.main.name
    storage_account  = azurerm_storage_account.logic_apps.name
    ad_application   = azuread_application.onboarding.display_name
    environment      = var.environment
    location         = var.location
  }
}

# Connectivity Information
output "connectivity_endpoints" {
  description = "Key endpoints for accessing deployed services"
  value = {
    key_vault_uri           = azurerm_key_vault.main.vault_uri
    service_bus_endpoint    = azurerm_servicebus_namespace.main.endpoint
    logic_app_hostname      = azurerm_logic_app_standard.main.default_hostname
    storage_blob_endpoint   = azurerm_storage_account.logic_apps.primary_blob_endpoint
  }
}

# Security and Compliance Information
output "security_configuration" {
  description = "Security configuration summary"
  value = {
    rbac_enabled                = var.enable_rbac_authorization
    https_only                  = var.enable_https_only
    diagnostic_logs_enabled     = var.enable_diagnostic_logs
    soft_delete_enabled         = true
    purge_protection_enabled    = var.key_vault_purge_protection_enabled
    private_endpoints_enabled   = var.enable_private_endpoint
    min_tls_version            = var.storage_account_min_tls_version
  }
}