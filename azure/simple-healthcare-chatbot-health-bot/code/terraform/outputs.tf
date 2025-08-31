# Output values for Azure Health Bot deployment

output "resource_group_name" {
  description = "Name of the resource group containing Health Bot resources"
  value       = azurerm_resource_group.health_bot_rg.name
}

output "resource_group_location" {
  description = "Azure region where resources are deployed"
  value       = azurerm_resource_group.health_bot_rg.location
}

output "health_bot_name" {
  description = "Name of the Azure Health Bot instance"
  value       = azurerm_healthbot.health_bot.name
}

output "health_bot_id" {
  description = "Resource ID of the Azure Health Bot instance"
  value       = azurerm_healthbot.health_bot.id
}

output "health_bot_sku" {
  description = "SKU of the Health Bot service"
  value       = azurerm_healthbot.health_bot.sku_name
}

output "health_bot_management_portal_url" {
  description = "URL to access the Health Bot Management Portal for configuration"
  value       = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_healthbot.health_bot.id}/overview"
}

output "health_bot_bot_management_url" {
  description = "Direct URL to the Health Bot management interface"
  value       = "https://portal.healthbot.microsoft.com/account/${data.azurerm_client_config.current.tenant_id}/bot/${azurerm_healthbot.health_bot.name}"
}

output "web_chat_embed_instructions" {
  description = "Instructions for embedding the Health Bot web chat"
  value = <<-EOT
    To embed the Health Bot web chat in your website:
    1. Access the Health Bot Management Portal: ${output.health_bot_management_portal_url}
    2. Navigate to Integration > Channels
    3. Enable the Web Chat channel
    4. Copy the provided embed code
    5. Add the embed code to your website or patient portal
    
    The web chat will provide HIPAA-compliant conversations with built-in medical intelligence.
  EOT
}

output "application_insights_name" {
  description = "Name of the Application Insights instance (if created)"
  value       = var.enable_hipaa_compliance ? azurerm_application_insights.health_bot_insights[0].name : null
}

output "application_insights_instrumentation_key" {
  description = "Application Insights instrumentation key for monitoring (if created)"
  value       = var.enable_hipaa_compliance ? azurerm_application_insights.health_bot_insights[0].instrumentation_key : null
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Application Insights connection string for monitoring (if created)"
  value       = var.enable_hipaa_compliance ? azurerm_application_insights.health_bot_insights[0].connection_string : null
  sensitive   = true
}

output "deployment_summary" {
  description = "Summary of deployed resources and next steps"
  value = {
    resource_group         = azurerm_resource_group.health_bot_rg.name
    health_bot_name       = azurerm_healthbot.health_bot.name
    health_bot_sku        = azurerm_healthbot.health_bot.sku_name
    management_portal_url = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_healthbot.health_bot.id}/overview"
    next_steps = [
      "Access the Health Bot Management Portal to configure scenarios",
      "Enable Web Chat channel for website integration",
      "Test built-in healthcare scenarios (symptom checker, disease lookup)",
      "Configure custom scenarios for your organization's specific needs",
      "Review HIPAA compliance settings and audit trails"
    ]
  }
}

output "healthcare_scenarios_info" {
  description = "Information about built-in healthcare scenarios"
  value = {
    symptom_checker     = "Built-in symptom assessment and triage capabilities"
    disease_lookup      = "Comprehensive disease information and guidance"
    medication_info     = "Medication lookup and interaction checking"
    provider_guidance   = "Doctor type recommendations based on symptoms"
    compliance_features = var.enable_hipaa_compliance ? "HIPAA compliance features enabled with audit trails" : "Basic compliance features"
  }
}

output "cost_information" {
  description = "Cost information for the deployed Health Bot"
  value = {
    sku                    = azurerm_healthbot.health_bot.sku_name
    pricing_tier          = var.health_bot_sku == "F0" ? "Free (limited conversations)" : "Standard ($500/month)"
    cost_optimization_tip = "Monitor usage through Azure Cost Management and consider Free tier for testing"
    billing_url           = "https://portal.azure.com/#blade/Microsoft_Azure_Billing/SubscriptionsBlade"
  }
}