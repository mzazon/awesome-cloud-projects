# Outputs for Azure Voice-Enabled Business Process Automation Infrastructure
# This file defines the output values that will be displayed after deployment

# Resource Group Information
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.voice_automation.name
}

output "resource_group_location" {
  description = "Location of the resource group"
  value       = azurerm_resource_group.voice_automation.location
}

# Speech Service Outputs
output "speech_service_name" {
  description = "Name of the Azure Speech Service"
  value       = azurerm_cognitive_account.speech_service.name
}

output "speech_service_endpoint" {
  description = "Endpoint URL for the Azure Speech Service"
  value       = azurerm_cognitive_account.speech_service.endpoint
}

output "speech_service_key" {
  description = "Primary access key for the Speech Service (sensitive)"
  value       = azurerm_cognitive_account.speech_service.primary_access_key
  sensitive   = true
}

output "speech_service_region" {
  description = "Region where the Speech Service is deployed"
  value       = azurerm_cognitive_account.speech_service.location
}

# Logic App Outputs
output "logic_app_name" {
  description = "Name of the Logic App"
  value       = azurerm_logic_app_standard.voice_processor.name
}

output "logic_app_default_hostname" {
  description = "Default hostname for the Logic App"
  value       = azurerm_logic_app_standard.voice_processor.default_hostname
}

output "logic_app_identity_principal_id" {
  description = "Principal ID of the Logic App managed identity"
  value       = azurerm_logic_app_standard.voice_processor.identity[0].principal_id
}

output "logic_app_webhook_url" {
  description = "Base URL for Logic App webhooks (append specific trigger path)"
  value       = "https://${azurerm_logic_app_standard.voice_processor.default_hostname}/api"
}

# Storage Account Outputs
output "storage_account_name" {
  description = "Name of the storage account"
  value       = azurerm_storage_account.voice_automation.name
}

output "storage_account_primary_connection_string" {
  description = "Primary connection string for the storage account (sensitive)"
  value       = azurerm_storage_account.voice_automation.primary_connection_string
  sensitive   = true
}

output "storage_account_primary_blob_endpoint" {
  description = "Primary blob endpoint for the storage account"
  value       = azurerm_storage_account.voice_automation.primary_blob_endpoint
}

# Key Vault Outputs
output "key_vault_name" {
  description = "Name of the Key Vault"
  value       = azurerm_key_vault.voice_automation.name
}

output "key_vault_uri" {
  description = "URI of the Key Vault"
  value       = azurerm_key_vault.voice_automation.vault_uri
}

output "key_vault_id" {
  description = "Resource ID of the Key Vault"
  value       = azurerm_key_vault.voice_automation.id
}

# Monitoring Outputs
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.voice_automation.name
}

output "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.voice_automation.id
}

output "application_insights_name" {
  description = "Name of the Application Insights instance"
  value       = azurerm_application_insights.voice_automation.name
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key for Application Insights (sensitive)"
  value       = azurerm_application_insights.voice_automation.instrumentation_key
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Connection string for Application Insights (sensitive)"
  value       = azurerm_application_insights.voice_automation.connection_string
  sensitive   = true
}

# Service Plan Output
output "service_plan_name" {
  description = "Name of the App Service Plan"
  value       = azurerm_service_plan.logic_apps.name
}

output "service_plan_id" {
  description = "Resource ID of the App Service Plan"
  value       = azurerm_service_plan.logic_apps.id
}

# Network Outputs (if private endpoints are enabled)
output "virtual_network_name" {
  description = "Name of the virtual network (if created)"
  value       = var.enable_private_endpoints ? azurerm_virtual_network.voice_automation[0].name : null
}

output "virtual_network_id" {
  description = "Resource ID of the virtual network (if created)"
  value       = var.enable_private_endpoints ? azurerm_virtual_network.voice_automation[0].id : null
}

output "private_endpoint_subnet_id" {
  description = "Resource ID of the private endpoint subnet (if created)"
  value       = var.enable_private_endpoints ? azurerm_subnet.private_endpoints[0].id : null
}

# Configuration Instructions
output "power_platform_integration_instructions" {
  description = "Instructions for integrating with Power Platform"
  value = <<-EOT
    To complete the Power Platform integration:
    
    1. Navigate to Power Automate (https://make.powerautomate.com)
    2. Create a new flow with HTTP trigger
    3. Use this Logic App webhook URL: https://${azurerm_logic_app_standard.voice_processor.default_hostname}/api/{workflow-name}/triggers/manual/invoke
    4. Configure the flow to process voice commands from the Logic App
    5. Connect to Dataverse for data storage and business process automation
    
    Speech Service Configuration:
    - Endpoint: ${azurerm_cognitive_account.speech_service.endpoint}
    - Region: ${azurerm_cognitive_account.speech_service.location}
    - Access Key: (stored in Key Vault: ${azurerm_key_vault.voice_automation.name})
    
    For Speech Studio configuration:
    1. Navigate to Speech Studio (https://speech.microsoft.com)
    2. Create a new Custom Commands project
    3. Use the Speech Service created above
    4. Import the custom commands configuration from the recipe
  EOT
}

# Resource Tags Applied
output "applied_tags" {
  description = "Tags applied to all resources"
  value       = var.tags
}

# Cost Information
output "estimated_monthly_cost_usd" {
  description = "Estimated monthly cost in USD (varies by usage)"
  value = <<-EOT
    Estimated monthly costs (USD):
    - Speech Service (${var.speech_service_sku}): ${var.speech_service_sku == "F0" ? "$0 (5 hours free)" : "$1-50 (pay-per-use)"}
    - Logic Apps Standard: $25-100 (based on executions)
    - Storage Account: $5-20 (based on usage)
    - Log Analytics: $2-10 (based on data ingestion)
    - Key Vault: $0.50-2 (based on operations)
    - Application Insights: $2-15 (based on telemetry volume)
    
    Total estimated range: $35-200/month
    Note: Actual costs depend on usage patterns and Power Platform licensing
  EOT
}

# Security Recommendations
output "security_recommendations" {
  description = "Security recommendations for production deployment"
  value = <<-EOT
    Security Recommendations:
    
    1. Enable Private Endpoints:
       - Set enable_private_endpoints = true
       - Configure network security groups
    
    2. Configure Conditional Access:
       - Implement Azure AD conditional access policies
       - Enable MFA for administrative access
    
    3. Monitor and Alert:
       - Review Log Analytics queries regularly
       - Set up custom alerts for suspicious activities
    
    4. Key Management:
       - Rotate Speech Service keys regularly
       - Use Azure Key Vault for all secrets
    
    5. Network Security:
       - Implement firewall rules
       - Use Web Application Firewall (WAF) if exposed to internet
    
    6. Data Protection:
       - Enable encryption in transit and at rest
       - Implement data loss prevention policies
  EOT
}