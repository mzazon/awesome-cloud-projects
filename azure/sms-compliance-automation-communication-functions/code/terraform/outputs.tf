# Output values for SMS Compliance Automation Infrastructure
# These outputs provide important information for accessing and integrating with the deployed resources

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

# Azure Communication Services Information
output "communication_service_name" {
  description = "Name of the Azure Communication Services resource"
  value       = azurerm_communication_service.main.name
}

output "communication_service_id" {
  description = "ID of the Azure Communication Services resource"
  value       = azurerm_communication_service.main.id
}

output "communication_service_immutable_resource_id" {
  description = "Immutable resource ID of the Communication Services"
  value       = azurerm_communication_service.main.immutable_resource_id
}

output "communication_service_primary_connection_string" {
  description = "Primary connection string for Azure Communication Services"
  value       = azurerm_communication_service.main.primary_connection_string
  sensitive   = true
}

output "communication_service_secondary_connection_string" {
  description = "Secondary connection string for Azure Communication Services"
  value       = azurerm_communication_service.main.secondary_connection_string
  sensitive   = true
}

# Function App Information
output "function_app_name" {
  description = "Name of the Function App"
  value       = azurerm_linux_function_app.main.name
}

output "function_app_id" {
  description = "ID of the Function App"
  value       = azurerm_linux_function_app.main.id
}

output "function_app_default_hostname" {
  description = "Default hostname of the Function App"
  value       = azurerm_linux_function_app.main.default_hostname
}

output "function_app_kind" {
  description = "Kind of Function App"
  value       = azurerm_linux_function_app.main.kind
}

output "function_app_principal_id" {
  description = "Principal ID of the Function App's managed identity"
  value       = azurerm_linux_function_app.main.identity[0].principal_id
}

output "function_app_tenant_id" {
  description = "Tenant ID of the Function App's managed identity"
  value       = azurerm_linux_function_app.main.identity[0].tenant_id
}

# Function App URLs for webhook endpoints
output "opt_out_processor_url" {
  description = "URL for the opt-out processor function (append function key)"
  value       = "https://${azurerm_linux_function_app.main.default_hostname}/api/OptOutProcessor"
}

output "compliance_monitor_info" {
  description = "Information about the compliance monitoring function"
  value = {
    schedule    = var.compliance_check_schedule
    description = "Timer-triggered function for compliance monitoring"
  }
}

# Storage Account Information
output "storage_account_name" {
  description = "Name of the storage account"
  value       = azurerm_storage_account.main.name
}

output "storage_account_id" {
  description = "ID of the storage account"
  value       = azurerm_storage_account.main.id
}

output "storage_account_primary_endpoint" {
  description = "Primary blob endpoint of the storage account"
  value       = azurerm_storage_account.main.primary_blob_endpoint
}

output "storage_account_primary_connection_string" {
  description = "Primary connection string for the storage account"
  value       = azurerm_storage_account.main.primary_connection_string
  sensitive   = true
}

output "audit_table_name" {
  description = "Name of the audit table for compliance logging"
  value       = azurerm_storage_table.audit.name
}

output "audit_table_url" {
  description = "URL of the audit table"
  value       = "https://${azurerm_storage_account.main.name}.table.core.windows.net/${azurerm_storage_table.audit.name}"
}

# Application Insights Information
output "application_insights_name" {
  description = "Name of the Application Insights resource"
  value       = azurerm_application_insights.main.name
}

output "application_insights_id" {
  description = "ID of the Application Insights resource"
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

output "application_insights_app_id" {
  description = "Application ID for Application Insights"
  value       = azurerm_application_insights.main.app_id
}

# Key Vault Information (conditional)
output "key_vault_name" {
  description = "Name of the Key Vault (if enabled)"
  value       = var.enable_key_vault ? azurerm_key_vault.main[0].name : null
}

output "key_vault_id" {
  description = "ID of the Key Vault (if enabled)"
  value       = var.enable_key_vault ? azurerm_key_vault.main[0].id : null
}

output "key_vault_uri" {
  description = "URI of the Key Vault (if enabled)"
  value       = var.enable_key_vault ? azurerm_key_vault.main[0].vault_uri : null
}

# Log Analytics Information (conditional)
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace (if enabled)"
  value       = var.enable_log_analytics ? azurerm_log_analytics_workspace.main[0].name : null
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace (if enabled)"
  value       = var.enable_log_analytics ? azurerm_log_analytics_workspace.main[0].id : null
}

output "log_analytics_workspace_workspace_id" {
  description = "Workspace ID of the Log Analytics workspace (if enabled)"
  value       = var.enable_log_analytics ? azurerm_log_analytics_workspace.main[0].workspace_id : null
}

output "log_analytics_primary_shared_key" {
  description = "Primary shared key of the Log Analytics workspace (if enabled)"
  value       = var.enable_log_analytics ? azurerm_log_analytics_workspace.main[0].primary_shared_key : null
  sensitive   = true
}

# Service Plan Information
output "service_plan_name" {
  description = "Name of the App Service Plan"
  value       = azurerm_service_plan.main.name
}

output "service_plan_id" {
  description = "ID of the App Service Plan"
  value       = azurerm_service_plan.main.id
}

output "service_plan_kind" {
  description = "Kind of the App Service Plan"
  value       = azurerm_service_plan.main.kind
}

output "service_plan_sku_name" {
  description = "SKU name of the App Service Plan"
  value       = azurerm_service_plan.main.sku_name
}

# Deployment Information
output "deployment_info" {
  description = "Important deployment information and next steps"
  value = {
    function_app_url            = "https://${azurerm_linux_function_app.main.default_hostname}"
    opt_out_endpoint           = "/api/OptOutProcessor"
    compliance_monitor_schedule = var.compliance_check_schedule
    data_location              = var.data_location
    environment                = var.environment
    deployment_timestamp       = timestamp()
  }
}

# Configuration Summary
output "configuration_summary" {
  description = "Summary of key configuration settings"
  value = {
    location                    = var.location
    data_location              = var.data_location
    environment                = var.environment
    key_vault_enabled          = var.enable_key_vault
    log_analytics_enabled      = var.enable_log_analytics
    compliance_monitoring      = var.enable_compliance_monitoring
    storage_replication        = var.storage_replication_type
    node_version              = var.node_version
    function_runtime_version   = var.function_app_runtime_version
  }
}

# Security Information
output "security_configuration" {
  description = "Security-related configuration information"
  value = {
    managed_identity_enabled  = var.enable_managed_identity
    public_access_allowed     = var.allow_public_access
    key_vault_enabled        = var.enable_key_vault
    diagnostic_settings      = var.enable_diagnostic_settings
    https_only               = true
    tls_version              = "1.2"
  }
}

# Integration Endpoints
output "integration_endpoints" {
  description = "Endpoints for integrating with the SMS compliance system"
  value = {
    opt_out_webhook = {
      url    = "https://${azurerm_linux_function_app.main.default_hostname}/api/OptOutProcessor"
      method = "POST"
      headers = {
        "Content-Type" = "application/json"
      }
      body_example = jsonencode({
        phoneNumber = "+15551234567"
        fromNumber  = "+18005551234"
        channel     = "web"
      })
    }
    application_insights_dashboard = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_application_insights.main.id}/overview"
  }
}

# Cost Information
output "cost_information" {
  description = "Estimated cost information and optimization tips"
  value = {
    consumption_plan = "Pay-per-execution model - no charges when idle"
    storage_costs   = "Minimal costs for audit logs and function storage"
    communication_services = "Pay-per-SMS sent - no base charges"
    estimated_monthly_minimum = "$5-10 USD for development/testing workloads"
    cost_optimization_tips = [
      "Use Consumption plan for cost-effective serverless scaling",
      "Monitor Application Insights retention settings",
      "Implement proper cleanup for audit logs",
      "Use resource tags for cost allocation"
    ]
  }
}

# Compliance Information
output "compliance_features" {
  description = "Compliance features and capabilities"
  value = {
    opt_out_management = "Automated SMS opt-out processing via Communication Services API"
    audit_logging     = "Comprehensive audit trails stored in Table Storage"
    data_retention    = "${var.compliance_audit_retention_days} days"
    monitoring        = var.enable_compliance_monitoring ? "Enabled with daily checks" : "Disabled"
    regulatory_support = [
      "TCPA compliance for SMS opt-outs",
      "CAN-SPAM Act compliance",
      "GDPR data processing requirements",
      "Audit trail maintenance"
    ]
  }
}