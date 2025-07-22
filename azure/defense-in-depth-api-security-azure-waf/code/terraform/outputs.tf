# Core resource outputs
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Location of the resource group"
  value       = azurerm_resource_group.main.location
}

output "resource_suffix" {
  description = "Unique suffix used for resource naming"
  value       = local.resource_suffix
}

# Network outputs
output "virtual_network_name" {
  description = "Name of the virtual network"
  value       = azurerm_virtual_network.main.name
}

output "virtual_network_id" {
  description = "ID of the virtual network"
  value       = azurerm_virtual_network.main.id
}

output "agw_subnet_id" {
  description = "ID of the Application Gateway subnet"
  value       = azurerm_subnet.agw.id
}

output "apim_subnet_id" {
  description = "ID of the API Management subnet"
  value       = azurerm_subnet.apim.id
}

output "private_endpoint_subnet_id" {
  description = "ID of the Private Endpoint subnet"
  value       = azurerm_subnet.pe.id
}

# API Management outputs
output "api_management_name" {
  description = "Name of the API Management service"
  value       = azurerm_api_management.main.name
}

output "api_management_id" {
  description = "ID of the API Management service"
  value       = azurerm_api_management.main.id
}

output "api_management_gateway_url" {
  description = "Gateway URL of the API Management service"
  value       = azurerm_api_management.main.gateway_url
}

output "api_management_management_api_url" {
  description = "Management API URL of the API Management service"
  value       = azurerm_api_management.main.management_api_url
}

output "api_management_developer_portal_url" {
  description = "Developer portal URL of the API Management service"
  value       = azurerm_api_management.main.developer_portal_url
}

output "api_management_principal_id" {
  description = "Principal ID of the API Management managed identity"
  value       = azurerm_api_management.main.identity[0].principal_id
  sensitive   = true
}

# Application Gateway outputs
output "application_gateway_name" {
  description = "Name of the Application Gateway"
  value       = azurerm_application_gateway.main.name
}

output "application_gateway_id" {
  description = "ID of the Application Gateway"
  value       = azurerm_application_gateway.main.id
}

output "application_gateway_public_ip" {
  description = "Public IP address of the Application Gateway"
  value       = azurerm_public_ip.agw.ip_address
}

output "application_gateway_fqdn" {
  description = "FQDN of the Application Gateway public IP"
  value       = azurerm_public_ip.agw.fqdn
}

# WAF outputs
output "waf_policy_name" {
  description = "Name of the Web Application Firewall policy"
  value       = azurerm_web_application_firewall_policy.main.name
}

output "waf_policy_id" {
  description = "ID of the Web Application Firewall policy"
  value       = azurerm_web_application_firewall_policy.main.id
}

# Monitoring outputs
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.name
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.id
}

output "log_analytics_workspace_workspace_id" {
  description = "Workspace ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.workspace_id
  sensitive   = true
}

output "application_insights_name" {
  description = "Name of the Application Insights component"
  value       = azurerm_application_insights.main.name
}

output "application_insights_id" {
  description = "ID of the Application Insights component"
  value       = azurerm_application_insights.main.id
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key of the Application Insights component"
  value       = azurerm_application_insights.main.instrumentation_key
  sensitive   = true
}

output "application_insights_app_id" {
  description = "App ID of the Application Insights component"
  value       = azurerm_application_insights.main.app_id
}

# Private networking outputs
output "private_dns_zone_name" {
  description = "Name of the private DNS zone"
  value       = azurerm_private_dns_zone.apim.name
}

output "private_dns_zone_id" {
  description = "ID of the private DNS zone"
  value       = azurerm_private_dns_zone.apim.id
}

output "private_endpoint_name" {
  description = "Name of the private endpoint"
  value       = azurerm_private_endpoint.apim.name
}

output "private_endpoint_id" {
  description = "ID of the private endpoint"
  value       = azurerm_private_endpoint.apim.id
}

output "private_endpoint_ip_address" {
  description = "Private IP address of the private endpoint"
  value       = azurerm_private_endpoint.apim.private_service_connection[0].private_ip_address
}

# Sample API outputs (conditional)
output "sample_api_name" {
  description = "Name of the sample API (if enabled)"
  value       = var.enable_sample_api ? azurerm_api_management_api.sample[0].name : null
}

output "sample_api_id" {
  description = "ID of the sample API (if enabled)"
  value       = var.enable_sample_api ? azurerm_api_management_api.sample[0].id : null
}

output "sample_api_path" {
  description = "Path of the sample API (if enabled)"
  value       = var.enable_sample_api ? azurerm_api_management_api.sample[0].path : null
}

# Security and access information
output "api_access_urls" {
  description = "URLs for accessing the API through different endpoints"
  value = {
    public_via_agw    = "http://${azurerm_public_ip.agw.ip_address}${var.enable_sample_api ? "/secure/data" : ""}"
    private_via_apim  = "${azurerm_api_management.main.gateway_url}${var.enable_sample_api ? "/secure/data" : ""}"
  }
}

output "monitoring_urls" {
  description = "URLs for monitoring and management interfaces"
  value = {
    log_analytics    = "https://portal.azure.com/#@/resource${azurerm_log_analytics_workspace.main.id}/overview"
    application_insights = "https://portal.azure.com/#@/resource${azurerm_application_insights.main.id}/overview"
    api_management_portal = azurerm_api_management.main.developer_portal_url
  }
}

# Testing and validation information
output "validation_commands" {
  description = "Commands for testing and validating the deployment"
  value = {
    test_waf_protection = "curl -X GET 'http://${azurerm_public_ip.agw.ip_address}${var.enable_sample_api ? "/secure/data" : ""}' -H 'User-Agent: <script>alert(\"xss\")</script>' -v"
    test_rate_limiting  = "for i in {1..15}; do curl -X GET 'http://${azurerm_public_ip.agw.ip_address}${var.enable_sample_api ? "/secure/data" : ""}' -w '%{http_code}\\n' -s -o /dev/null; done"
    test_direct_apim    = "curl -X GET '${azurerm_api_management.main.gateway_url}${var.enable_sample_api ? "/secure/data" : ""}' --connect-timeout 10 --max-time 30"
  }
}

# Configuration summary
output "deployment_summary" {
  description = "Summary of the deployed zero-trust API security architecture"
  value = {
    environment           = var.environment
    location             = var.location
    api_management_sku   = var.apim_sku_name
    waf_mode            = var.waf_mode
    waf_rule_set        = var.waf_rule_set_version
    rate_limit_threshold = var.rate_limit_threshold
    log_retention_days  = var.log_retention_days
    sample_api_enabled  = var.enable_sample_api
    total_subnets       = 3
    security_layers     = [
      "Web Application Firewall",
      "Application Gateway",
      "API Management Policies",
      "Private Network Isolation",
      "Comprehensive Monitoring"
    ]
  }
}

# Cost estimation information
output "cost_estimation" {
  description = "Estimated monthly costs for the deployed resources"
  value = {
    note = "Costs vary by region, usage, and selected SKUs. Review Azure pricing calculator for accurate estimates."
    major_cost_components = [
      "API Management Standard: ~$250-500/month",
      "Application Gateway WAF v2: ~$50-150/month",
      "Log Analytics: ~$2-10/month (depends on data ingestion)",
      "Application Insights: ~$5-25/month (depends on telemetry volume)",
      "Virtual Network: Minimal cost",
      "Public IP: ~$3-5/month"
    ]
    estimated_total = "$300-700/month depending on usage and data retention"
  }
}

# Next steps and recommendations
output "next_steps" {
  description = "Recommended next steps after deployment"
  value = [
    "Configure custom domain and SSL certificate for Application Gateway",
    "Set up Azure AD B2C integration for API authentication",
    "Configure custom API policies based on specific requirements",
    "Set up alerts and monitoring rules in Azure Monitor",
    "Implement backup and disaster recovery procedures",
    "Review and adjust WAF rules based on legitimate traffic patterns",
    "Configure Azure Policy for governance and compliance",
    "Set up CI/CD pipelines for API deployment automation"
  ]
}